import 'package:fl_clash/manager/app_traffic_tracker.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TrackerInfo connection({
    required String id,
    required int upload,
    required int download,
    String process = 'Google Chrome Helper',
    String processPath =
        '/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper',
    List<String> chains = const ['Proxy A', 'Selector'],
    List<String> providerChains = const ['Provider A', ''],
  }) {
    return TrackerInfo(
      id: id,
      upload: upload,
      download: download,
      start: DateTime(2026),
      metadata: Metadata(process: process, processPath: processPath),
      chains: chains,
      providerChains: providerChains,
      rule: 'MATCH',
      rulePayload: '',
    );
  }

  test('tracks live deltas and the final close delta exactly once', () async {
    final persisted = <AppTrafficDelta>[];
    final tracker = AppTrafficTracker(
      persist: (deltas) async => persisted.addAll(deltas),
      resolveProfile: () =>
          const AppTrafficProfileContext(id: 7, label: 'My plan'),
    );

    tracker.observeStart(connection(id: 'a', upload: 0, download: 0));
    await tracker.observeSnapshot([
      connection(id: 'a', upload: 100, download: 200),
    ]);
    await tracker.observeSnapshot([
      connection(id: 'a', upload: 100, download: 200),
    ]);
    tracker.observeClosed(connection(id: 'a', upload: 140, download: 260));
    tracker.observeClosed(connection(id: 'a', upload: 140, download: 260));
    await tracker.flush();

    expect(persisted, hasLength(2));
    expect(persisted.map((delta) => delta.upload), [100, 40]);
    expect(persisted.map((delta) => delta.download), [200, 60]);
    expect(persisted.first.applicationLabel, 'Google Chrome');
    expect(persisted.first.applicationId, '/Applications/Google Chrome.app/');
    expect(persisted.first.provider, 'Provider A');
    expect(persisted.first.proxy, 'Proxy A');
  });

  test('excludes direct traffic and groups missing process metadata', () async {
    final persisted = <AppTrafficDelta>[];
    final tracker = AppTrafficTracker(
      persist: (deltas) async => persisted.addAll(deltas),
      resolveProfile: () => const AppTrafficProfileContext(id: 0, label: ''),
    );

    tracker.observeClosed(
      connection(
        id: 'direct',
        upload: 100,
        download: 200,
        chains: const ['DIRECT'],
      ),
    );
    tracker.observeClosed(
      connection(
        id: 'dialer',
        upload: 700,
        download: 900,
      ).copyWith(internal: true),
    );
    tracker.observeClosed(
      connection(
        id: 'proxy',
        upload: 5,
        download: 7,
        process: '',
        processPath: '',
      ),
    );
    await tracker.flush();

    expect(persisted, hasLength(1));
    expect(persisted.single.applicationId, 'unknown');
    expect(persisted.single.total, 12);
  });

  test('keeps the subscription that owned the connection at start', () async {
    var profile = const AppTrafficProfileContext(id: 1, label: 'First');
    final persisted = <AppTrafficDelta>[];
    final tracker = AppTrafficTracker(
      persist: (deltas) async => persisted.addAll(deltas),
      resolveProfile: () => profile,
    );

    tracker.observeStart(connection(id: 'a', upload: 0, download: 0));
    profile = const AppTrafficProfileContext(id: 2, label: 'Second');
    tracker.observeClosed(connection(id: 'a', upload: 10, download: 20));
    await tracker.flush();

    expect(persisted.single.profileId, 1);
    expect(persisted.single.profileLabel, 'First');
  });

  test('excludes renamed direct outbounds reported by the core', () async {
    final persisted = <AppTrafficDelta>[];
    final tracker = AppTrafficTracker(
      persist: (deltas) async => persisted.addAll(deltas),
      resolveProfile: () =>
          const AppTrafficProfileContext(id: 1, label: 'Plan'),
    );
    tracker.observeClosed(
      connection(
        id: 'direct',
        upload: 120,
        download: 340,
      ).copyWith(chains: const ['Local network', 'Selector'], direct: true),
    );
    await tracker.flush();
    expect(persisted, isEmpty);
  });

  test(
    'retries a failed batch with newer deltas and never double counts',
    () async {
      var fail = true;
      final persisted = <AppTrafficDelta>[];
      final tracker = AppTrafficTracker(
        persist: (batch) async {
          if (fail) throw StateError('database temporarily unavailable');
          persisted.addAll(batch);
        },
        resolveProfile: () =>
            const AppTrafficProfileContext(id: 1, label: 'Plan'),
      );
      tracker.observeStart(connection(id: 'a', upload: 5, download: 0));
      tracker.observeChanges({'a': (upload: 20, download: 1)});
      await expectLater(tracker.flush(), throwsStateError);
      fail = false;
      tracker.observeClosed(connection(id: 'a', upload: 30, download: 4));
      tracker.observeChanges({'a': (upload: 30, download: 4)});
      await tracker.flush();
      await tracker.flush();
      expect(persisted.single.upload, 30);
      expect(persisted.single.download, 4);
    },
  );

  test(
    'does not double count late events after clearConnections on disconnect',
    () async {
      final persisted = <AppTrafficDelta>[];
      final tracker = AppTrafficTracker(
        persist: (deltas) async => persisted.addAll(deltas),
        resolveProfile: () =>
            const AppTrafficProfileContext(id: 1, label: 'Plan'),
      );

      tracker.observeStart(connection(id: 'a', upload: 0, download: 0));
      tracker.observeChanges({'a': (upload: 500, download: 900)});
      await tracker.flush();

      tracker.clearConnections();
      tracker.observeClosed(connection(id: 'a', upload: 500, download: 900));
      tracker.observeStart(connection(id: 'a', upload: 500, download: 900));
      await tracker.flush();

      expect(persisted, hasLength(1));
      expect(persisted.single.upload, 500);
      expect(persisted.single.download, 900);
    },
  );

  test(
    'snapshotToken prunes stale closed connections while preserving newer ones',
    () async {
      final persisted = <AppTrafficDelta>[];
      final tracker = AppTrafficTracker(
        persist: (deltas) async => persisted.addAll(deltas),
        resolveProfile: () =>
            const AppTrafficProfileContext(id: 1, label: 'Plan'),
      );

      tracker.observeStart(connection(id: 'stale', upload: 10, download: 20));
      final token = tracker.beginSnapshot();
      tracker.observeStart(connection(id: 'fresh', upload: 5, download: 15));

      await tracker.observeSnapshot(const [], snapshotToken: token);

      tracker.observeClosed(connection(id: 'stale', upload: 10, download: 20));
      tracker.observeClosed(connection(id: 'fresh', upload: 8, download: 20));
      await tracker.flush();

      final totalUpload = persisted.fold(0, (sum, d) => sum + d.upload);
      final totalDownload = persisted.fold(0, (sum, d) => sum + d.download);
      expect(totalUpload, 18);
      expect(totalDownload, 40);
    },
  );

  test(
    'clearPending drops matching profile deltas even across failed in-flight flushes',
    () async {
      final persisted = <AppTrafficDelta>[];
      var fail = true;
      late Future<void> inFlightFlush;
      final tracker = AppTrafficTracker(
        persist: (deltas) async {
          if (fail) throw StateError('db locked');
          persisted.addAll(deltas);
        },
        resolveProfile: () =>
            const AppTrafficProfileContext(id: 1, label: 'Plan'),
      );

      tracker.observeClosed(connection(id: 'a', upload: 100, download: 200));
      expect(tracker.hasPending, isTrue);

      inFlightFlush = tracker.flush();
      tracker.clearPending(profileId: 1);
      await expectLater(inFlightFlush, throwsStateError);
      expect(tracker.hasPending, isFalse);

      fail = false;
      await tracker.flush();
      expect(persisted, isEmpty);
    },
  );

  test('extracts Windows executable name when process is empty', () async {
    final persisted = <AppTrafficDelta>[];
    final tracker = AppTrafficTracker(
      persist: (deltas) async => persisted.addAll(deltas),
      resolveProfile: () =>
          const AppTrafficProfileContext(id: 1, label: 'Plan'),
    );

    tracker.observeClosed(
      connection(
        id: 'win',
        upload: 10,
        download: 20,
        process: '',
        processPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ),
    );
    await tracker.flush();

    expect(persisted.single.applicationLabel, 'chrome.exe');
    expect(AppTrafficSort.upload.amount(upload: 10, download: 20), 10);
    expect(AppTrafficSort.download.amount(upload: 10, download: 20), 20);
    expect(AppTrafficSort.total.amount(upload: 10, download: 20), 30);
  });
}
