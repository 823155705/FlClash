import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class WidgetListener {
  void onCycleMode() {}

  void onCycleNode() {}

  void onSelectProxy(String proxyName) {}
}

class WidgetChannel {
  final MethodChannel _channel = const MethodChannel('$packageName/widget');

  WidgetChannel._() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  static final WidgetChannel instance = WidgetChannel._();

  final ObserverList<WidgetListener> _listeners =
      ObserverList<WidgetListener>();

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final WidgetListener listener in List.of(_listeners)) {
      switch (call.method) {
        case 'cycleMode':
          listener.onCycleMode();
          break;
        case 'cycleNode':
          listener.onCycleNode();
          break;
        case 'selectProxy':
          if (call.arguments is String) {
            listener.onSelectProxy(call.arguments as String);
          }
          break;
      }
    }
  }

  void addListener(WidgetListener listener) {
    _listeners.add(listener);
  }

  void removeListener(WidgetListener listener) {
    _listeners.remove(listener);
  }

  Future<void> updateWidget({
    required bool isStart,
    required String mode,
    required String nodeName,
    required String groupName,
    required num upSpeed,
    required num downSpeed,
    required String proxyNames,
    Uint8List? chartBytes,
  }) async {
    final data = <String, dynamic>{
      'isStart': isStart,
      'mode': mode,
      'nodeName': nodeName,
      'groupName': groupName,
      'upSpeed': upSpeed,
      'downSpeed': downSpeed,
      'proxyNames': proxyNames,
    };
    if (chartBytes != null) {
      data['chartBytes'] = chartBytes;
    }
    await _channel.invokeMethod('updateWidget', data);
  }
}

final widgetChannel = system.isAndroid ? WidgetChannel.instance : null;
