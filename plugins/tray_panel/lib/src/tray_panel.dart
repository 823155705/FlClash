import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tray_panel_models.dart';

const String _methodSetPanelState = 'setPanelState';
const String _methodSetPanelTraffic = 'setPanelTraffic';
const String _methodOpenPanel = 'openPanel';
const String _methodClosePanel = 'closePanel';
const String _methodTogglePanel = 'togglePanel';

const String _eventPanelVisibilityChanged = 'onPanelVisibilityChanged';
const String _eventPanelAction = 'onPanelAction';

sealed class TrayPanelEvent {
  const TrayPanelEvent();
}

final class TrayPanelVisibilityChanged extends TrayPanelEvent {
  const TrayPanelVisibilityChanged(this.visible);

  final bool visible;
}

final class TrayPanelAction extends TrayPanelEvent {
  const TrayPanelAction(
    this.action, [
    this.payload = const <String, Object?>{},
  ]);

  final String action;
  final Map<String, Object?> payload;
}

final class TrayPanelCapabilities {
  const TrayPanelCapabilities({
    required this.supported,
    required this.openOnActivate,
  });

  final bool supported;
  final bool openOnActivate;

  static const TrayPanelCapabilities desktopPanel = TrayPanelCapabilities(
    supported: true,
    openOnActivate: true,
  );

  static const TrayPanelCapabilities none = TrayPanelCapabilities(
    supported: false,
    openOnActivate: false,
  );

  static TrayPanelCapabilities of(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS || TargetPlatform.windows => desktopPanel,
      _ => none,
    };
  }
}

final class TrayPanel {
  TrayPanel._() {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  static final TrayPanel instance = TrayPanel._();

  final MethodChannel _channel = const MethodChannel('tray_panel');
  final StreamController<TrayPanelEvent> _events =
      StreamController<TrayPanelEvent>.broadcast();

  Future<void> _queue = Future<void>.value();
  String? _panelSignature;
  TrayPanelTraffic? _panelTraffic;
  TrayPanelTraffic? _requestedPanelTraffic;

  Stream<TrayPanelEvent> get events => _events.stream;

  TrayPanelCapabilities get capabilities =>
      TrayPanelCapabilities.of(defaultTargetPlatform);

  Future<void> setState(TrayPanelState state) {
    return _serialize(() => _setState(state));
  }

  Future<void> setTraffic(TrayPanelTraffic traffic) {
    _requestedPanelTraffic = traffic;
    return _serialize(() => _setTraffic(_requestedPanelTraffic));
  }

  Future<void> open() {
    return _serialize(_open);
  }

  Future<void> close() {
    return _serialize(_close);
  }

  Future<void> toggle() {
    return _serialize(_toggle);
  }

  @visibleForTesting
  void resetForTesting() {
    _queue = Future<void>.value();
    _panelSignature = null;
    _panelTraffic = null;
    _requestedPanelTraffic = null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _setState(TrayPanelState state) async {
    if (!capabilities.supported) {
      return;
    }
    final payload = state.toMap();
    final signature = jsonEncode(payload);
    if (signature == _panelSignature) {
      return;
    }
    final isApplied = await _channel.invokeMethod<bool>(
      _methodSetPanelState,
      payload,
    );
    if (isApplied == false) {
      _panelSignature = null;
      return;
    }
    _panelSignature = signature;
  }

  Future<void> _setTraffic(TrayPanelTraffic? traffic) async {
    if (!capabilities.supported ||
        traffic == null ||
        _panelTraffic == traffic) {
      return;
    }
    _panelTraffic = traffic;
    await _channel.invokeMethod(_methodSetPanelTraffic, traffic.toMap());
  }

  Future<void> _open() async {
    if (!capabilities.supported) {
      return;
    }
    await _channel.invokeMethod(_methodOpenPanel);
  }

  Future<void> _close() async {
    if (!capabilities.supported) {
      return;
    }
    await _channel.invokeMethod(_methodClosePanel);
  }

  Future<void> _toggle() async {
    if (!capabilities.supported) {
      return;
    }
    await _channel.invokeMethod(_methodTogglePanel);
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case _eventPanelVisibilityChanged:
        final arguments = call.arguments;
        if (arguments is! Map) {
          return;
        }
        final visible = arguments['visible'];
        if (visible is! bool) {
          return;
        }
        _events.add(TrayPanelVisibilityChanged(visible));
      case _eventPanelAction:
        final arguments = call.arguments;
        if (arguments is! Map) {
          return;
        }
        final action = arguments['action'];
        if (action is! String || action.isEmpty) {
          return;
        }
        final rawPayload = arguments['payload'];
        final payload = rawPayload is Map
            ? <String, Object?>{
                for (final entry in rawPayload.entries)
                  if (entry.key is String) entry.key as String: entry.value,
              }
            : const <String, Object?>{};
        _events.add(TrayPanelAction(action, payload));
    }
  }
}
