import 'dart:collection';
import 'dart:math';

import 'package:fl_clash/models/models.dart';

typedef AppTrafficPersist =
    Future<void> Function(Iterable<AppTrafficDelta> deltas);
typedef AppTrafficProfileResolver = AppTrafficProfileContext Function();
typedef _PendingKey = (int, int?, int, String, String, String);

class AppTrafficTracker {
  static const _maxClosedConnectionIds = 4096;
  static const _maxPendingEntries = 4096;
  static final _bundlePattern = RegExp(r'(^|/)([^/]+\.app)(/|$)');
  static final _pathSeparatorPattern = RegExp(r'[/\\]');

  final AppTrafficPersist persist;
  final AppTrafficProfileResolver resolveProfile;
  final Map<String, _TrackedConnection> _connections = {};
  final LinkedHashSet<String> _closedConnectionIds = LinkedHashSet();
  final Set<int?> _clearedDuringWrite = {};
  Map<_PendingKey, AppTrafficDelta> _pending = {};
  Future<void>? _writing;
  int _observationSeq = 0;

  AppTrafficTracker({required this.persist, required this.resolveProfile});

  bool get hasPending => _pending.isNotEmpty;

  int beginSnapshot() => ++_observationSeq;

  void observeStart(TrackerInfo connection) {
    if (!_countsTraffic(connection) ||
        _closedConnectionIds.contains(connection.id)) {
      return;
    }
    final tracked = _connections.putIfAbsent(
      connection.id,
      () => _TrackedConnection(connection, resolveProfile()),
    );
    tracked.lastSeenSeq = ++_observationSeq;
    _record(tracked, connection.upload, connection.download, DateTime.now());
  }

  Future<void> observeSnapshot(
    Iterable<TrackerInfo> connections, {
    int? snapshotToken,
  }) {
    final now = DateTime.now();
    final seenIds = snapshotToken == null ? null : <String>{};
    for (final connection in connections) {
      seenIds?.add(connection.id);
      if (!_countsTraffic(connection) ||
          _closedConnectionIds.contains(connection.id)) {
        continue;
      }
      final tracked = _connections.putIfAbsent(
        connection.id,
        () => _TrackedConnection(connection, resolveProfile()),
      );
      tracked.connection = connection;
      tracked.lastSeenSeq = ++_observationSeq;
      _record(tracked, connection.upload, connection.download, now);
    }
    if (snapshotToken != null && seenIds != null) {
      final staleIds = [
        for (final MapEntry(:key, :value) in _connections.entries)
          if (!seenIds.contains(key) && value.lastSeenSeq < snapshotToken) key,
      ];
      for (final id in staleIds) {
        _connections.remove(id);
        _markClosed(id);
      }
    }
    return flush();
  }

  void observeChanges(Map<String, RequestTraffic> traffic) {
    final now = DateTime.now();
    for (final MapEntry(:key, :value) in traffic.entries) {
      if (_connections[key] case final tracked?) {
        tracked.lastSeenSeq = ++_observationSeq;
        _record(tracked, value.upload, value.download, now);
      }
    }
  }

  void observeClosed(TrackerInfo connection) {
    if (!_countsTraffic(connection) ||
        _closedConnectionIds.contains(connection.id)) {
      return;
    }
    final tracked =
        _connections.remove(connection.id) ??
        _TrackedConnection(connection, resolveProfile());
    tracked.connection = connection;
    _record(tracked, connection.upload, connection.download, DateTime.now());
    _markClosed(connection.id);
  }

  void _markClosed(String id) {
    _closedConnectionIds.add(id);
    while (_closedConnectionIds.length > _maxClosedConnectionIds) {
      _closedConnectionIds.remove(_closedConnectionIds.first);
    }
  }

  bool _countsTraffic(TrackerInfo connection) =>
      !connection.internal &&
      !connection.direct &&
      connection.chains.isNotEmpty &&
      connection.chains.first != 'DIRECT';

  void clearConnections() {
    for (final id in _connections.keys) {
      _markClosed(id);
    }
    _connections.clear();
  }

  void clearPending({int? profileId}) {
    if (profileId == null) {
      _pending.clear();
    } else {
      _pending.removeWhere((key, _) => key.$3 == profileId);
    }
    if (_writing != null) {
      _clearedDuringWrite.add(profileId);
    }
  }

  Future<void> flush() {
    if (_writing case final writing?) return writing;
    if (_pending.isEmpty) return Future.value();
    final batch = _pending;
    _pending = {};
    _clearedDuringWrite.clear();
    return _writing = Future<void>.sync(() => persist(batch.values))
        .catchError((Object error, StackTrace stack) {
          if (!_clearedDuringWrite.contains(null)) {
            for (final MapEntry(:key, :value) in batch.entries) {
              if (_clearedDuringWrite.contains(key.$3)) {
                continue;
              }
              if (_pending.containsKey(key)) {
                _pending.update(key, value.plus);
              } else if (_pending.length < _maxPendingEntries) {
                _pending[key] = value;
              }
            }
          }
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(() {
          _clearedDuringWrite.clear();
          _writing = null;
        });
  }

  void _record(
    _TrackedConnection tracked,
    int uploaded,
    int downloaded,
    DateTime now,
  ) {
    final upload = max(0, uploaded - tracked.upload);
    final download = max(0, downloaded - tracked.download);
    tracked.upload = max(tracked.upload, uploaded);
    tracked.download = max(tracked.download, downloaded);
    if (upload == 0 && download == 0) {
      return;
    }
    final connection = tracked.connection;
    final proxy = connection.chains.first;
    final identity = tracked.identity ??= _applicationIdentity(
      connection.metadata,
    );
    final providers = connection.providerChains.where(
      (value) => value.isNotEmpty,
    );
    final provider = providers.isEmpty ? '' : providers.first;
    final day = DateTime(now.year, now.month, now.day);
    final delta = AppTrafficDelta(
      day: day,
      hour: now.hour,
      profileId: tracked.profile.id,
      profileLabel: tracked.profile.label,
      applicationId: identity.id,
      applicationLabel: identity.label,
      processPath: connection.metadata.processPath,
      proxy: proxy,
      provider: provider,
      upload: upload,
      download: download,
    );
    final key = (
      day.millisecondsSinceEpoch,
      now.hour,
      tracked.profile.id,
      identity.id,
      proxy,
      provider,
    );
    if (_pending.containsKey(key)) {
      _pending.update(key, (old) => old.plus(delta));
      return;
    }
    if (_pending.length >= _maxPendingEntries) {
      _pending.remove(_pending.keys.first);
    }
    _pending[key] = delta;
  }

  _ApplicationIdentity _applicationIdentity(Metadata metadata) {
    final path = metadata.processPath.trim();
    final match = _bundlePattern.firstMatch(path);
    if (match != null) {
      final bundleName = match.group(2)!;
      final bundleEnd = match.end;
      return _ApplicationIdentity(
        id: path.substring(0, bundleEnd),
        label: bundleName.substring(0, bundleName.length - 4),
      );
    }
    final process = metadata.process.trim();
    if (path.isNotEmpty) {
      final fallback = path
          .split(_pathSeparatorPattern)
          .lastWhere((segment) => segment.isNotEmpty, orElse: () => path);
      return _ApplicationIdentity(
        id: path,
        label: process.isEmpty ? fallback : process,
      );
    }
    if (process.isNotEmpty) {
      return _ApplicationIdentity(id: process, label: process);
    }
    return const _ApplicationIdentity(id: 'unknown', label: '');
  }
}

class _TrackedConnection {
  TrackerInfo connection;
  final AppTrafficProfileContext profile;
  _ApplicationIdentity? identity;
  int upload = 0;
  int download = 0;
  int lastSeenSeq = 0;

  _TrackedConnection(this.connection, this.profile);
}

class _ApplicationIdentity {
  final String id;
  final String label;

  const _ApplicationIdentity({required this.id, required this.label});
}
