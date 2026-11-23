import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WidgetPinKind {
  compact2x2('2x2'),
  wide4x2('4x2'),
  bar4x1('4x1');

  const WidgetPinKind(this.wireValue);

  final String wireValue;
}

sealed class PendingWidgetAction {
  const PendingWidgetAction();
}

final class PendingWidgetCycleMode extends PendingWidgetAction {
  const PendingWidgetCycleMode();
}

final class PendingWidgetSelectProxy extends PendingWidgetAction {
  final String groupName;
  final String proxyName;

  const PendingWidgetSelectProxy({
    required this.groupName,
    required this.proxyName,
  });
}

abstract mixin class WidgetListener {
  void onCycleMode() {}

  void onSelectProxy(String groupName, String proxyName) {}

  void onWidgetsActiveChanged(bool active) {}
}

class WidgetChannel {
  static const _defaultChannel = MethodChannel('$packageName/widget');

  WidgetChannel._([MethodChannel? channel])
    : _channel = channel ?? _defaultChannel {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  @visibleForTesting
  factory WidgetChannel.scoped(MethodChannel channel) =>
      WidgetChannel._(channel);

  static final WidgetChannel instance = WidgetChannel._();

  MethodChannel _channel;
  final ObserverList<WidgetListener> _listeners =
      ObserverList<WidgetListener>();

  @visibleForTesting
  void resetForTesting([MethodChannel? channel]) {
    _listeners.clear();
    _channel.setMethodCallHandler(null);
    _channel = channel ?? _defaultChannel;
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final WidgetListener listener in List.of(_listeners)) {
      try {
        switch (call.method) {
          case 'cycleMode':
            listener.onCycleMode();
          case 'selectProxy':
            final args = call.arguments;
            if (args is Map) {
              final groupName = args['groupName'];
              final proxyName = args['proxyName'];
              if (groupName is String &&
                  groupName.isNotEmpty &&
                  proxyName is String &&
                  proxyName.isNotEmpty) {
                listener.onSelectProxy(groupName, proxyName);
              }
            }
          case 'widgetsActiveChanged':
            if (call.arguments is bool) {
              listener.onWidgetsActiveChanged(call.arguments as bool);
            }
        }
      } catch (error) {
        commonPrint.log(
          'Unable to dispatch Widget event ${call.method}: $error',
          logLevel: LogLevel.error,
        );
      }
    }
  }

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(WidgetListener listener) {
    _listeners.add(listener);
  }

  void removeListener(WidgetListener listener) {
    _listeners.remove(listener);
  }

  Future<void> updateSnapshot(Map<String, Object?> snapshot) async {
    try {
      await _channel.invokeMethod<Object?>('updateSnapshot', snapshot);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      commonPrint.log(
        'Unable to update widget snapshot: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<bool> hasActiveWidgets() async {
    try {
      return await _channel.invokeMethod<bool>('hasActiveWidgets') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      commonPrint.log(
        'Unable to query active widgets: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  Future<bool> isRequestPinSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isRequestPinWidgetSupported') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      commonPrint.log(
        'Unable to query widget pin support: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  Future<bool> requestPinWidget(WidgetPinKind kind) async {
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget', {
            'kind': kind.wireValue,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      commonPrint.log(
        'Unable to request widget pin: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  Future<PendingWidgetAction?> consumePendingAction() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'consumePendingAction',
      );
      if (raw == null) {
        return null;
      }
      return switch (raw['action']) {
        'cycleMode' => const PendingWidgetCycleMode(),
        'selectProxy' => switch ((raw['groupName'], raw['proxyName'])) {
          (final String groupName, final String proxyName)
              when groupName.isNotEmpty && proxyName.isNotEmpty =>
            PendingWidgetSelectProxy(
              groupName: groupName,
              proxyName: proxyName,
            ),
          _ => null,
        },
        _ => null,
      };
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      commonPrint.log(
        'Unable to consume pending widget action: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }
}

final widgetChannel = system.isAndroid ? WidgetChannel.instance : null;
