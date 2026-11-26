import 'dart:io';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/l10n_labels.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:rust_api/tray.dart';
import 'package:tray_panel/tray_panel.dart';

import '../helpers/app_paths.dart';
import '../helpers/fake_tray_host.dart';

const _proxyGroup = Group(
  name: 'Proxy',
  type: GroupType.Selector,
  all: [
    Proxy(name: 'A', type: 'Direct'),
    Proxy(name: 'B', type: 'Direct'),
    Proxy(name: 'C', type: 'Direct'),
  ],
);

HotKeyAction _bind(HotAction action, PhysicalKeyboardKey key) {
  return HotKeyAction(
    action: action,
    key: key.usbHidUsage,
    modifiers: const {KeyboardModifier.control, KeyboardModifier.shift},
  );
}

TrayState _trayState({
  bool isStart = false,
  bool tunEnable = false,
  bool systemProxy = false,
  bool autoLaunch = false,
  bool showTrayTitle = false,
  bool monochromeTrayIcon = true,
  bool safeMode = false,
  Mode mode = Mode.rule,
  List<Group> groups = const [],
  Map<HotAction, HotKeyAction> hotKeys = const {},
}) {
  return TrayState(
    mode: mode,
    port: 7890,
    autoLaunch: autoLaunch,
    systemProxy: systemProxy,
    tunEnable: tunEnable,
    isStart: isStart,
    groups: groups,
    selectedMap: const {},
    showTrayTitle: showTrayTitle,
    monochromeTrayIcon: monochromeTrayIcon,
    safeMode: safeMode,
    hotKeys: hotKeys,
  );
}

Map<String, Object?> _describe(TrayItem item) {
  return {
    'id': item.id,
    'type': item.kind.name,
    'label': item.label,
    if (item.detail != null) 'detail': item.detail,
    'enabled': item.enabled,
    'checked': item.checked,
    'items': item.items.map(_describe).toList(),
  };
}

List<Map<String, Object?>> _items(TrayContent? content) {
  return content?.menu.map(_describe).toList() ?? const [];
}

Map<String, Object?> _item(TrayContent? content, String label) {
  return _items(content).firstWhere((item) => item['label'] == label);
}

List<String> _labels(TrayContent? content) {
  return _items(
    content,
  ).map((item) => item['label']).whereType<String>().toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panelChannel = MethodChannel('tray_panel');
  late FakeTrayHost host;
  late List<MethodCall> panelCalls;
  late ProviderContainer container;
  late AppTray tray;

  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('tray_menu_test');
    await useAppPaths(root);
    loadAppLocalizations(const Locale('en'));
  });

  tearDownAll(() {
    // The shared system temp dir is not exclusively ours; another suite running
    // alongside this one can take the tree out from under the teardown, either
    // before the check or between the check and the delete.
    try {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    } on FileSystemException {
      return;
    }
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    host = FakeTrayHost();
    panelCalls = <MethodCall>[];
    tray = AppTray.forPlatform(isMacOS: true, isWindows: false);
    container = ProviderContainer();
    Tray.instance.resetForTesting(host);
    TrayPanel.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(panelChannel, (call) async {
          panelCalls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(panelChannel, null);
    TrayPanel.instance.resetForTesting();
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  TrayContent? showCall() => host.lastShown;

  Map<Object?, Object?>? lastPanelState() {
    for (final call in panelCalls.reversed) {
      if (call.method == 'setPanelState') {
        return call.arguments as Map<Object?, Object?>;
      }
    }
    return null;
  }

  Future<void> update(TrayState trayState, {AppTray? on}) {
    return (on ?? tray).update(
      trayState: trayState,
      traffic: const Traffic(),
      read: container.read,
    );
  }

  test(
    'SystemAction.updateTray builds the menu without reading itself',
    () async {
      globalState.container = container;
      trayPort = tray;
      addTearDown(() => trayPort = null);

      await container.read(systemActionProvider.notifier).updateTray();

      expect(showCall(), isNotNull);
      expect(_labels(showCall()), contains(currentAppLocalizations.exit));
    },
  );

  test('SystemAction.updateTray logs a tray the platform refuses, with its '
      'reason, rather than throwing', () async {
    globalState.container = container;
    trayPort = tray;
    addTearDown(() => trayPort = null);
    final wasAttached = globalState.isAttach;
    globalState.isAttach = true;
    addTearDown(() => globalState.isAttach = wasAttached);
    host.showFailure = 'no status notifier watcher';

    await container.read(systemActionProvider.notifier).updateTray();

    expect(
      container.read(logsProvider).list.map((log) => log.payload),
      contains(contains('no status notifier watcher')),
    );
  });

  test(
    'builds the slim panel menu on macOS and pushes stopped state',
    () async {
      await update(_trayState());

      final labels = _labels(showCall());
      final l10n = currentAppLocalizations;
      expect(labels, [
        l10n.show,
        l10n.start,
        '',
        l10n.copyEnvVar,
        '',
        l10n.exit,
      ]);
      expect(lastPanelState()?['isStart'], isFalse);
    },
  );

  test('flips start to stop and syncs TUN/proxy flags to the panel', () async {
    await update(_trayState(isStart: true, tunEnable: true, systemProxy: true));

    final labels = _labels(showCall());
    final l10n = currentAppLocalizations;
    expect(labels, contains(l10n.stop), reason: 'start flips to stop');
    final panel = lastPanelState()!;
    expect(panel['isStart'], isTrue);
    expect(panel['tunEnable'], isTrue);
    expect(panel['systemProxy'], isTrue);
  });

  group('safe mode', () {
    test('keeps the slim menu and marks safeMode in panel state', () async {
      await update(_trayState(isStart: true, safeMode: true));

      final labels = _labels(showCall());
      final l10n = currentAppLocalizations;
      expect(labels, [
        l10n.show,
        l10n.stop,
        '',
        l10n.copyEnvVar,
        '',
        l10n.exit,
      ]);
      expect(lastPanelState()?['safeMode'], isTrue);
    });

    test('names the mode in the tooltip and ships the safe icon', () async {
      await update(_trayState(isStart: true, safeMode: true));

      final content = showCall()!;
      final l10n = currentAppLocalizations;
      expect(content.toolTip, '$appName (${l10n.safeMode})');
      expect(
        content.image.pngs.first,
        File('assets/images/tray/macos/status_4.png').readAsBytesSync(),
      );
    });
  });

  test('sends the active outbound mode to the panel state', () async {
    await update(_trayState(mode: Mode.global));

    expect(lastPanelState()?['mode'], Mode.global.name);
  });

  test('sends icon, tooltip and menu in a single show call', () async {
    await update(_trayState(isStart: true, tunEnable: true));

    expect(host.shown, hasLength(1));

    final content = host.shown.single;
    expect(content.toolTip, appName);
    expect(content.menu, isNotEmpty);
    expect(content.image.pngs, hasLength(Tray.variantScales.length));
    expect(content.image.pngs, everyElement(isNotEmpty));
    expect(content.image.template, isTrue);
  });

  test('ships the color status icon once monochrome is off', () async {
    await update(
      _trayState(isStart: true, tunEnable: true, monochromeTrayIcon: false),
    );

    final content = showCall()!;
    expect(content.image.template, isFalse);
    expect(
      content.image.pngs.first,
      File('assets/images/tray/unix/status_3.png').readAsBytesSync(),
    );
    expect(lastPanelState()?['monochromeTrayIcon'], isFalse);
  });

  test('skips the platform call when the tray state is unchanged', () async {
    await update(_trayState(isStart: true));
    await update(_trayState(isStart: true));

    expect(host.shown, hasLength(1));
  });

  test('menu item ids are stable across identical rebuilds', () async {
    await update(_trayState());
    final first = _items(showCall()).map((item) => item['id']).toList();

    host = FakeTrayHost();
    Tray.instance.resetForTesting(host);

    await update(_trayState());
    final second = _items(showCall()).map((item) => item['id']).toList();

    expect(second, first);
    expect(first.first, 1024);
  });

  test('panel groups carry their proxies', () async {
    await update(_trayState(groups: [_proxyGroup]));

    final groups = (lastPanelState()?['groups'] as List)
        .cast<Map<Object?, Object?>>();
    expect(groups, hasLength(1));
    expect(groups.first['name'], 'Proxy');
    final proxies = (groups.first['proxies'] as List)
        .cast<Map<Object?, Object?>>();
    expect(proxies.map((item) => item['name']), ['A', 'B', 'C']);
  });

  test('shows each bound hotkey in menu and panel shortcuts', () async {
    await update(
      _trayState(
        isStart: true,
        hotKeys: {
          HotAction.view: _bind(HotAction.view, PhysicalKeyboardKey.keyV),
          HotAction.globalMode: _bind(
            HotAction.globalMode,
            PhysicalKeyboardKey.keyG,
          ),
          HotAction.tun: _bind(HotAction.tun, PhysicalKeyboardKey.keyT),
          HotAction.delayTest: _bind(
            HotAction.delayTest,
            PhysicalKeyboardKey.keyD,
          ),
        },
      ),
    );

    final l10n = currentAppLocalizations;
    final call = showCall();
    expect(_item(call, l10n.show)['detail'], '⌃⇧V');
    expect(_item(call, l10n.exit), isNot(contains('detail')));
    final shortcuts = lastPanelState()?['shortcuts'] as Map<Object?, Object?>;
    expect(shortcuts['showWindow'], '⌃⇧V');
    expect(shortcuts['modeGlobal'], '⌃⇧G');
    expect(shortcuts['tun'], '⌃⇧T');
    expect(shortcuts['testAllDelays'], '⌃⇧D');
  });

  test(
    'panel groups show the delay of the selection and of each proxy',
    () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          selectedProxyNameProvider('Proxy').overrideWithValue('A'),
          trayDelaysProvider.overrideWithValue({
            'Proxy': {'A': 120, 'B': -1, 'C': -2},
          }),
        ],
      );
      const group = Group(
        name: 'Proxy',
        type: GroupType.Selector,
        all: [
          Proxy(name: 'A', type: 'Direct'),
          Proxy(name: 'B', type: 'Direct'),
          Proxy(name: 'C', type: 'Direct'),
          Proxy(name: 'D', type: 'Direct'),
        ],
      );
      await update(_trayState(groups: [group]));

      final groups = (lastPanelState()?['groups'] as List)
          .cast<Map<Object?, Object?>>();
      final proxyGroup = groups.single;
      expect(proxyGroup['selectedDelay'], 120);
      final proxies = (proxyGroup['proxies'] as List)
          .cast<Map<Object?, Object?>>();
      expect(proxies.map((item) => item['delay']), [120, -1, -2, null]);
    },
  );

  group('Windows tray panel and Linux full menu', () {
    test(
      'Windows builds slim menu, joins hotkeys with + and pushes panel state',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final windows = AppTray.forPlatform(isMacOS: false, isWindows: true);
        await update(
          _trayState(
            isStart: true,
            groups: [_proxyGroup],
            hotKeys: {
              HotAction.view: _bind(HotAction.view, PhysicalKeyboardKey.keyV),
            },
          ),
          on: windows,
        );

        expect(showCall()!.image.template, isFalse);
        expect(
          _item(showCall(), currentAppLocalizations.show)['detail'],
          'Ctrl+Shift+V',
        );
        expect(lastPanelState()?['showMacOSToggles'], isFalse);
        await windows.updateTitle(
          showTrayTitle: true,
          traffic: const Traffic(),
        );
        expect(host.titles, isEmpty);
      },
    );

    test('Linux keeps the full native menu without panel calls', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final linux = AppTray.forPlatform(isMacOS: false, isWindows: false);
      await update(_trayState(isStart: true), on: linux);

      final labels = _labels(showCall());
      final l10n = currentAppLocalizations;
      expect(labels, contains(l10n.tun));
      expect(labels, contains(l10n.systemProxy));
      expect(labels, contains(Mode.global.label));
      expect(panelCalls, isEmpty);
    });
  });
}
