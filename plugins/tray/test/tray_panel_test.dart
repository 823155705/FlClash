import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray/src/tray_codec.dart';
import 'package:tray/tray.dart';

const MethodChannel _channel = MethodChannel('tray');
const StandardMethodCodec _codec = StandardMethodCodec();

TrayPanelTheme _theme({bool isDark = true, int primary = 0xFFD8C0C3}) {
  return TrayPanelTheme(
    isDark: isDark,
    pureBlack: false,
    glassTint: 0x9E2B2929,
    cardBg: 0xFF201F1F,
    blockBg: 0xFF2B2929,
    insetBg: 0xFF1C1B1B,
    hairline: 0x24E6E1E1,
    primary: primary,
    onPrimary: 0xFF3B292C,
    onSurface: 0xFFE6E1E1,
    onSurfaceVariant: 0xFFD0C4C5,
    success: 0xFF4CAF50,
    warning: 0xFFC57F0A,
    error: 0xFFFFB4AB,
    onError: 0xFF690005,
  );
}

TrayPanelLabels _labels({String appName = 'FlClash'}) {
  return TrayPanelLabels(
    appName: appName,
    showWindow: 'Show',
    start: 'Start',
    stop: 'Stop',
    modeRule: 'Rule',
    modeGlobal: 'Global',
    modeDirect: 'Direct',
    tun: 'TUN',
    systemProxy: 'System Proxy',
    speedStatistics: 'Speed',
    monochromeIcon: 'Monochrome Icon',
    autoLaunch: 'Auto Launch',
    proxies: 'Proxies',
    search: 'Search',
    testAllDelays: 'Test all delays',
    delayTest: 'Delay test',
    timeout: 'Timeout',
    delayFailed: 'Failed',
    copyEnvVar: 'Copy env var',
    exit: 'Exit',
    noProxies: 'No proxies',
    safeMode: 'Safe Mode',
  );
}

TrayPanelShortcuts _shortcuts({String showWindow = '⌘⇧O'}) {
  return TrayPanelShortcuts(
    showWindow: showWindow,
    toggleRunning: '⌘⇧R',
    modeRule: '⌘1',
    modeGlobal: '⌘2',
    modeDirect: '⌘3',
    testAllDelays: '⌘T',
    tun: '⌘⇧T',
    systemProxy: '⌘⇧P',
    copyEnv: '⌘⇧C',
    exit: '⌘Q',
  );
}

TrayPanelState _panelState({
  bool isStart = true,
  bool suspended = false,
  bool safeMode = false,
  String mode = 'rule',
  bool tunEnable = false,
  bool systemProxy = true,
  bool showTrayTitle = true,
  bool monochromeTrayIcon = false,
  bool autoLaunch = false,
  int port = 7890,
  bool testingAll = false,
  TrayPanelTheme? theme,
  TrayPanelLabels? labels,
  TrayPanelShortcuts? shortcuts,
  List<TrayPanelGroup> groups = const <TrayPanelGroup>[
    TrayPanelGroup(
      name: 'Proxy',
      type: 'Selector',
      selectedProxyName: 'HK-01',
      selectedDelay: 42,
      testing: false,
      proxies: <TrayPanelProxy>[
        TrayPanelProxy(
          name: 'HK-01',
          type: 'Shadowsocks',
          delay: 42,
          selected: true,
        ),
        TrayPanelProxy(name: 'US-01', type: 'VMess', delay: -1),
      ],
    ),
  ],
}) {
  return TrayPanelState(
    isStart: isStart,
    suspended: suspended,
    safeMode: safeMode,
    mode: mode,
    tunEnable: tunEnable,
    systemProxy: systemProxy,
    showTrayTitle: showTrayTitle,
    monochromeTrayIcon: monochromeTrayIcon,
    autoLaunch: autoLaunch,
    port: port,
    testingAll: testingAll,
    theme: theme ?? _theme(),
    labels: labels ?? _labels(),
    shortcuts: shortcuts ?? _shortcuts(),
    groups: groups,
  );
}

TraySpec _traySpec() {
  return const TraySpec(
    icon: TrayIcon.asset('assets/icon.png', isTemplate: true),
    toolTip: 'FlClash',
  );
}

Future<void> _emit(String method, Object? arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        _codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Object? setPanelStateResult;
  Completer<void>? showGate;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls = <MethodCall>[];
    setPanelStateResult = true;
    showGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'show') {
            await showGate?.future;
            return true;
          }
          if (call.method == 'setPanelState') {
            return setPanelStateResult;
          }
          return true;
        });
    Tray.instance.resetForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    Tray.instance.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
  });

  test('panel capability is enabled only on macOS', () {
    expect(TrayCapabilities.macOS.panel, isTrue);
    expect(TrayCapabilities.windows.panel, isFalse);
    expect(TrayCapabilities.linux.panel, isFalse);
    expect(TrayCapabilities.none.panel, isFalse);
    expect(TrayCapabilities.of(TargetPlatform.macOS).panel, isTrue);
    expect(TrayCapabilities.of(TargetPlatform.windows).panel, isFalse);
    expect(TrayCapabilities.of(TargetPlatform.linux).panel, isFalse);
    expect(TrayCapabilities.of(TargetPlatform.android).panel, isFalse);
  });

  test('panel models support value equality, hashCode, and wire maps', () {
    expect(
      <String>[
        TrayPanelActionNames.showWindow,
        TrayPanelActionNames.toggleRunning,
        TrayPanelActionNames.setMode,
        TrayPanelActionNames.toggleTun,
        TrayPanelActionNames.toggleSystemProxy,
        TrayPanelActionNames.toggleSpeedStatistics,
        TrayPanelActionNames.toggleMonochromeIcon,
        TrayPanelActionNames.toggleAutoLaunch,
        TrayPanelActionNames.selectProxy,
        TrayPanelActionNames.testGroupDelay,
        TrayPanelActionNames.testAllDelays,
        TrayPanelActionNames.copyEnv,
        TrayPanelActionNames.quit,
      ],
      <String>[
        'showWindow',
        'toggleRunning',
        'setMode',
        'toggleTun',
        'toggleSystemProxy',
        'toggleSpeedStatistics',
        'toggleMonochromeIcon',
        'toggleAutoLaunch',
        'selectProxy',
        'testGroupDelay',
        'testAllDelays',
        'copyEnv',
        'quit',
      ],
    );

    final a = _panelState();
    final b = _panelState();
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a.toMap(), equals(b.toMap()));

    const defaultShortcuts = TrayPanelShortcuts();
    expect(defaultShortcuts.toMap().values.every((v) => v == ''), isTrue);
    expect(_shortcuts(), isNot(equals(defaultShortcuts)));

    const trafficA = TrayPanelTraffic(up: '1 KB/s', down: '2 KB/s');
    const trafficB = TrayPanelTraffic(up: '1 KB/s', down: '2 KB/s');
    const trafficC = TrayPanelTraffic(up: '3 KB/s', down: '2 KB/s');
    expect(trafficA, equals(trafficB));
    expect(trafficA.hashCode, equals(trafficB.hashCode));
    expect(trafficA, isNot(equals(trafficC)));
    expect(trafficA.toMap(), <String, Object?>{
      'up': '1 KB/s',
      'down': '2 KB/s',
    });
  });

  test('encodePanelState serializes expected wire keys and tracks changes', () {
    final base = _panelState();
    final encoded = TrayCodec.encodePanelState(base);

    expect(encoded.payload['isStart'], isTrue);
    expect(encoded.payload['suspended'], isFalse);
    expect(encoded.payload['safeMode'], isFalse);
    expect(encoded.payload['mode'], 'rule');
    expect(encoded.payload['monochromeTrayIcon'], isFalse);
    expect(encoded.payload['port'], 7890);
    expect((encoded.payload['theme'] as Map)['glassTint'], 0x9E2B2929);
    expect((encoded.payload['theme'] as Map)['hairline'], 0x24E6E1E1);
    expect((encoded.payload['labels'] as Map)['safeMode'], 'Safe Mode');
    expect((encoded.payload['labels'] as Map)['delayFailed'], 'Failed');
    expect(
      (encoded.payload['labels'] as Map)['monochromeIcon'],
      'Monochrome Icon',
    );
    expect((encoded.payload['shortcuts'] as Map)['showWindow'], '⌘⇧O');
    final groups = encoded.payload['groups'] as List;
    expect((groups.single as Map)['selectedProxyName'], 'HK-01');

    expect(
      TrayCodec.encodePanelState(_panelState()).signature,
      encoded.signature,
    );
    expect(
      TrayCodec.encodePanelState(_panelState(suspended: true)).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(_panelState(safeMode: true)).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(
        _panelState(monochromeTrayIcon: true),
      ).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(
        _panelState(shortcuts: _shortcuts(showWindow: '⌘O')),
      ).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(_panelState(mode: 'global')).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(
        _panelState(theme: _theme(isDark: false)),
      ).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(
        _panelState(labels: _labels(appName: 'Other')),
      ).signature,
      isNot(encoded.signature),
    );
    expect(
      TrayCodec.encodePanelState(
        _panelState(
          groups: const <TrayPanelGroup>[
            TrayPanelGroup(
              name: 'Proxy',
              type: 'Selector',
              selectedProxyName: 'HK-01',
              selectedDelay: 120,
            ),
          ],
        ),
      ).signature,
      isNot(encoded.signature),
    );
  });

  test('setPanelState suppresses duplicates and retries on false', () async {
    await Tray.instance.setPanelState(_panelState());
    await Tray.instance.setPanelState(_panelState());

    expect(calls.where((c) => c.method == 'setPanelState'), hasLength(1));

    setPanelStateResult = false;
    await Tray.instance.setPanelState(_panelState(mode: 'global'));
    setPanelStateResult = true;
    await Tray.instance.setPanelState(_panelState(mode: 'global'));

    expect(calls.where((c) => c.method == 'setPanelState'), hasLength(3));

    setPanelStateResult = null;
    await Tray.instance.setPanelState(_panelState(mode: 'direct'));
    await Tray.instance.setPanelState(_panelState(mode: 'direct'));

    expect(calls.where((c) => c.method == 'setPanelState'), hasLength(4));
  });

  test('panel methods are gated by capabilities and visibility', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await Tray.instance.show(_traySpec());
    await Tray.instance.setPanelState(_panelState());
    await Tray.instance.setPanelTraffic(
      const TrayPanelTraffic(up: '1 B/s', down: '2 B/s'),
    );
    await Tray.instance.openPanel();
    await Tray.instance.closePanel();
    await Tray.instance.togglePanel();

    expect(calls.where((c) => c.method != 'show'), isEmpty);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    Tray.instance.resetForTesting();
    calls.clear();

    await Tray.instance.openPanel();
    await Tray.instance.togglePanel();
    await Tray.instance.setPanelTraffic(
      const TrayPanelTraffic(up: '1 B/s', down: '2 B/s'),
    );
    await Tray.instance.closePanel();
    expect(calls.map((c) => c.method), ['closePanel']);

    calls.clear();
    await Tray.instance.show(_traySpec());
    await Tray.instance.openPanel();
    await Tray.instance.togglePanel();
    await Tray.instance.closePanel();
    expect(calls.map((c) => c.method), [
      'show',
      'openPanel',
      'togglePanel',
      'closePanel',
    ]);
  });

  test(
    'setPanelTraffic coalesces queued ticks and suppresses unchanged',
    () async {
      await Tray.instance.show(_traySpec());

      final gate = Completer<void>();
      showGate = gate;
      final stalled = Tray.instance.show(
        const TraySpec(
          icon: TrayIcon.asset('assets/other.png', isTemplate: true),
        ),
      );
      unawaited(
        Tray.instance.setPanelTraffic(
          const TrayPanelTraffic(up: '1 KB/s', down: '1 KB/s'),
        ),
      );
      unawaited(
        Tray.instance.setPanelTraffic(
          const TrayPanelTraffic(up: '2 KB/s', down: '2 KB/s'),
        ),
      );
      final settled = Tray.instance.setPanelTraffic(
        const TrayPanelTraffic(up: '3 KB/s', down: '4 KB/s'),
      );
      gate.complete();
      await stalled;
      await settled;

      await Tray.instance.setPanelTraffic(
        const TrayPanelTraffic(up: '3 KB/s', down: '4 KB/s'),
      );

      final trafficCalls = calls
          .where((c) => c.method == 'setPanelTraffic')
          .map((c) => c.arguments)
          .toList();
      expect(trafficCalls, [
        <String, Object?>{'up': '3 KB/s', 'down': '4 KB/s'},
      ]);
    },
  );

  test(
    'hide and resetForTesting clear cached panel state and traffic',
    () async {
      await Tray.instance.show(_traySpec());
      await Tray.instance.setPanelState(_panelState());
      await Tray.instance.setPanelTraffic(
        const TrayPanelTraffic(up: '1 KB/s', down: '2 KB/s'),
      );
      await Tray.instance.hide();

      calls.clear();
      await Tray.instance.show(_traySpec());
      await Tray.instance.setPanelState(_panelState());
      await Tray.instance.setPanelTraffic(
        const TrayPanelTraffic(up: '1 KB/s', down: '2 KB/s'),
      );

      expect(calls.map((c) => c.method), [
        'show',
        'setPanelState',
        'setPanelTraffic',
      ]);

      calls.clear();
      Tray.instance.resetForTesting();
      await Tray.instance.show(_traySpec());
      await Tray.instance.setPanelState(_panelState());
      await Tray.instance.setPanelTraffic(
        const TrayPanelTraffic(up: '1 KB/s', down: '2 KB/s'),
      );

      expect(calls.map((c) => c.method), [
        'show',
        'setPanelState',
        'setPanelTraffic',
      ]);
    },
  );

  test('dispatches panel visibility and action events safely', () async {
    final events = <TrayEvent>[];
    final subscription = Tray.instance.events.listen(events.add);
    addTearDown(subscription.cancel);

    await _emit('onPanelVisibilityChanged', <String, Object?>{'visible': true});
    await _emit('onPanelVisibilityChanged', <String, Object?>{
      'visible': false,
    });
    await _emit('onPanelVisibilityChanged', <String, Object?>{
      'visible': 'yes',
    });
    await _emit('onPanelVisibilityChanged', <String, Object?>{});
    await _emit('onPanelVisibilityChanged', null);

    await _emit('onPanelAction', <String, Object?>{
      'action': TrayPanelActionNames.selectProxy,
      'payload': <Object?, Object?>{
        'groupName': 'Proxy',
        'proxyName': 'HK-01',
        1: 'ignored',
      },
    });
    await _emit('onPanelAction', <String, Object?>{
      'action': TrayPanelActionNames.quit,
    });
    await _emit('onPanelAction', <String, Object?>{
      'action': TrayPanelActionNames.toggleMonochromeIcon,
      'payload': 'not-a-map',
    });
    await _emit('onPanelAction', <String, Object?>{'action': ''});
    await _emit('onPanelAction', <String, Object?>{'action': 123});
    await _emit('onPanelAction', 'bad');

    expect(events, hasLength(5));
    expect(
      events[0],
      isA<TrayPanelVisibilityChanged>().having(
        (e) => e.visible,
        'visible',
        isTrue,
      ),
    );
    expect(
      events[1],
      isA<TrayPanelVisibilityChanged>().having(
        (e) => e.visible,
        'visible',
        isFalse,
      ),
    );
    expect(
      events[2],
      isA<TrayPanelAction>()
          .having((e) => e.action, 'action', TrayPanelActionNames.selectProxy)
          .having((e) => e.payload, 'payload', <String, Object?>{
            'groupName': 'Proxy',
            'proxyName': 'HK-01',
          }),
    );
    expect(
      events[3],
      isA<TrayPanelAction>()
          .having((e) => e.action, 'action', TrayPanelActionNames.quit)
          .having((e) => e.payload, 'payload', isEmpty),
    );
    expect(
      events[4],
      isA<TrayPanelAction>()
          .having(
            (e) => e.action,
            'action',
            TrayPanelActionNames.toggleMonochromeIcon,
          )
          .having((e) => e.payload, 'payload', isEmpty),
    );
  });
}
