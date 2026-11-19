import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/common/compute.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/l10n_labels.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tray/tray.dart';

import '../helpers/app_paths.dart';

const _channel = MethodChannel('tray');

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

List<Map<Object?, Object?>> _items(MethodCall? call) {
  final menu = (call?.arguments as Map?)?['menu'] as List?;
  return menu?.cast<Map<Object?, Object?>>() ?? const [];
}

Map<Object?, Object?> _item(MethodCall? call, String label) {
  return _items(call).firstWhere((item) => item['label'] == label);
}

List<String> _labels(MethodCall? call) {
  return _items(call).map((item) => item['label']).whereType<String>().toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late ProviderContainer container;
  late AppTray tray;

  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('tray_menu_test');
    await useAppPaths(root);
    await AppLocalizations.load(const Locale('en'));
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
    calls = [];
    tray = AppTray.forPlatform(isMacOS: true, isWindows: false);
    container = ProviderContainer();
    Tray.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  MethodCall? showCall() {
    for (final call in calls.reversed) {
      if (call.method == 'show') {
        return call;
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

  test('builds the stopped menu without the running-only toggles', () async {
    await update(_trayState());

    final labels = _labels(showCall());
    final l10n = currentAppLocalizations;
    expect(labels, contains(l10n.show));
    expect(labels, contains(l10n.start));
    expect(labels, contains(l10n.autoLaunch));
    expect(labels, contains(l10n.copyEnvVar));
    expect(labels, contains(l10n.exit));
    expect(labels, isNot(contains(l10n.tun)));
    expect(labels, isNot(contains(l10n.systemProxy)));
  });

  test('adds TUN and system proxy toggles once the core is running', () async {
    await update(_trayState(isStart: true));

    final labels = _labels(showCall());
    final l10n = currentAppLocalizations;
    expect(labels, contains(l10n.stop), reason: 'start flips to stop');
    expect(labels, contains(l10n.tun));
    expect(labels, contains(l10n.systemProxy));
  });

  group('safe mode', () {
    test('keeps the full menu', () async {
      await update(_trayState(isStart: true, safeMode: true));

      final labels = _labels(showCall());
      final l10n = currentAppLocalizations;
      expect(labels, contains(l10n.stop));
      expect(labels, contains(l10n.tun));
      expect(labels, contains(l10n.systemProxy));
      expect(labels, contains(l10n.copyEnvVar));
    });

    test('names the mode in the tooltip and ships the safe icon', () async {
      await update(_trayState(isStart: true, safeMode: true));

      final arguments = showCall()!.arguments as Map;
      final l10n = currentAppLocalizations;
      expect(arguments['toolTip'], '$appName (${l10n.safeMode})');
      final reps = ((arguments['icon'] as Map)['reps'] as List).cast<Map>();
      final base = reps.firstWhere((rep) => rep['scale'] == 1.0);
      expect(
        base['bytes'],
        base64Encode(
          File('assets/images/tray/macos/status_4.png').readAsBytesSync(),
        ),
      );
    });
  });

  test('offers every outbound mode as a menu entry', () async {
    await update(_trayState(mode: Mode.global));

    final checkedModes = _items(showCall())
        .where((item) => item['checked'] == true)
        .map((item) => item['label'])
        .toList();
    expect(checkedModes, contains(Intl.message(Mode.global.name)));
  });

  test('sends icon, tooltip and menu in a single show call', () async {
    await update(_trayState(isStart: true, tunEnable: true));

    final showCalls = calls.where((call) => call.method == 'show').toList();
    expect(showCalls, hasLength(1));

    final arguments = showCalls.single.arguments as Map;
    expect(arguments['toolTip'], appName);
    expect(arguments['menu'], isNotEmpty);
    final reps = ((arguments['icon'] as Map)['reps'] as List).cast<Map>();
    expect(reps.map((rep) => rep['scale']), containsAll([1.0, 2.0, 3.0, 4.0]));
    expect(reps.map((rep) => rep['bytes']), everyElement(isNotEmpty));
    expect((arguments['icon'] as Map)['isTemplate'], isTrue);
  });

  test('ships the color status icon once monochrome is off', () async {
    await update(
      _trayState(isStart: true, tunEnable: true, monochromeTrayIcon: false),
    );

    final arguments = showCall()!.arguments as Map;
    expect((arguments['icon'] as Map)['isTemplate'], isFalse);
    final reps = ((arguments['icon'] as Map)['reps'] as List).cast<Map>();
    final base = reps.firstWhere((rep) => rep['scale'] == 1.0);
    expect(
      base['bytes'],
      base64Encode(
        File('assets/images/tray/unix/status_3.png').readAsBytesSync(),
      ),
    );
    expect(
      _item(showCall(), currentAppLocalizations.monochromeIcon)['checked'],
      isFalse,
    );
  });

  test('skips the platform call when the tray state is unchanged', () async {
    await update(_trayState(isStart: true));
    await update(_trayState(isStart: true));

    expect(calls.where((call) => call.method == 'show'), hasLength(1));
  });

  test('menu item ids are stable across identical rebuilds', () async {
    await update(_trayState());
    final first = _items(showCall()).map((item) => item['id']).toList();

    Tray.instance.resetForTesting();
    calls.clear();

    await update(_trayState());
    final second = _items(showCall()).map((item) => item['id']).toList();

    expect(second, first);
    expect(first.first, 1024);
  });

  test('group submenus carry their proxies as nested items', () async {
    await update(
      _trayState(
        groups: [
          const Group(
            name: 'Proxy',
            type: GroupType.Selector,
            all: [Proxy(name: 'A', type: 'Direct')],
          ),
        ],
      ),
    );

    final submenu = _items(
      showCall(),
    ).firstWhere((item) => item['type'] == 'submenu');
    expect(submenu['label'], 'Proxy');
    final children = (submenu['items'] as List).cast<Map<Object?, Object?>>();
    expect(children.map((item) => item['label']), contains('A'));
  });

  test('shows each bound hotkey dimmed beside its entry', () async {
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
        },
      ),
    );

    final l10n = currentAppLocalizations;
    final call = showCall();
    expect(_item(call, l10n.show)['detail'], '⌃⇧V');
    expect(_item(call, Mode.global.label)['detail'], '⌃⇧G');
    expect(_item(call, l10n.tun)['detail'], '⌃⇧T');
    expect(_item(call, l10n.exit), isNot(contains('detail')));
    expect(_item(call, Mode.rule.label), isNot(contains('detail')));
  });

  test(
    'group submenus show the delay of the selection and of each proxy',
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

      final submenu = _item(showCall(), 'Proxy');
      expect(submenu['detail'], '120');
      final children = (submenu['items'] as List).cast<Map<Object?, Object?>>();
      expect(children.map((item) => item['detail']), [
        '120',
        currentAppLocalizations.timeout,
        currentAppLocalizations.delayFailed,
        null,
      ]);
    },
  );

  test('a delay test entry follows the groups', () async {
    await update(
      _trayState(
        groups: [_proxyGroup],
        hotKeys: {
          HotAction.delayTest: _bind(
            HotAction.delayTest,
            PhysicalKeyboardKey.keyD,
          ),
        },
      ),
    );

    final items = _items(showCall());
    final index = items.indexWhere((item) => item['type'] == 'submenu');
    expect(items[index + 1]['label'], HotAction.delayTest.label);
    expect(items[index + 1]['detail'], '⌃⇧D');
  });

  group('a platform that is not macOS', () {
    late AppTray windows;

    setUp(() {
      windows = AppTray.forPlatform(isMacOS: false, isWindows: true);
    });

    test('gets a plain icon, no group submenus and no speed toggle', () async {
      await update(
        _trayState(
          isStart: true,
          groups: [
            const Group(
              name: 'Proxy',
              type: GroupType.Selector,
              all: [Proxy(name: 'A', type: 'Direct')],
            ),
          ],
        ),
        on: windows,
      );

      final arguments = showCall()!.arguments as Map;
      expect((arguments['icon'] as Map)['isTemplate'], isFalse);
      expect(
        _items(showCall()).where((item) => item['type'] == 'submenu'),
        isEmpty,
      );
      expect(
        _labels(showCall()),
        isNot(contains(currentAppLocalizations.speedStatistics)),
      );
      expect(
        _labels(showCall()),
        isNot(contains(currentAppLocalizations.monochromeIcon)),
      );
      expect(_labels(showCall()), isNot(contains(HotAction.delayTest.label)));
    });

    test('joins modifiers with + in the hotkey hints', () async {
      await update(
        _trayState(
          hotKeys: {
            HotAction.view: _bind(HotAction.view, PhysicalKeyboardKey.keyV),
          },
        ),
        on: windows,
      );

      expect(
        _item(showCall(), currentAppLocalizations.show)['detail'],
        'Ctrl+Shift+V',
      );
    });

    test('never pushes a tray title', () async {
      await windows.updateTitle(showTrayTitle: true, traffic: const Traffic());

      expect(calls.where((call) => call.method == 'setTitle'), isEmpty);
    });

    test('never pushes tray panel state or traffic', () async {
      await windows.updatePanel(
        trayState: _trayState(isStart: true),
        read: container.read,
      );
      await windows.updatePanelTraffic(const Traffic(up: 1024, down: 2048));

      expect(calls.where((call) => call.method == 'setPanelState'), isEmpty);
      expect(calls.where((call) => call.method == 'setPanelTraffic'), isEmpty);
    });
  });

  group('tray panel', () {
    test(
      'buildPanelState maps state, prism_ui theme, labels, shortcuts and groups',
      () {
        container.dispose();
        container = ProviderContainer(
          overrides: [
            systemBrightnessProvider.overrideWithBuild(
              (_, _) => Brightness.dark,
            ),
            selectedProxyNameProvider('Proxy').overrideWithValue('A'),
            trayDelaysProvider.overrideWithValue({
              'Proxy': {'A': 85, 'B': -1, 'C': -2},
            }),
            pendingDelayTestsProvider.overrideWithBuild(
              (_, _) => {
                delayTestKey(defaultTestUrl, 'C'): DelayTestPhase.running,
              },
            ),
          ],
        );
        container
            .read(themeSettingProvider.notifier)
            .update(
              (state) =>
                  state.copyWith(themeMode: ThemeMode.dark, pureBlack: true),
            );
        const group = Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [
            Proxy(name: 'A', type: 'Shadowsocks'),
            Proxy(name: 'B', type: 'Trojan'),
            Proxy(name: 'C', type: 'VMess'),
          ],
        );
        final panel = tray.buildPanelState(
          trayState: TrayState(
            mode: Mode.global,
            port: 7890,
            autoLaunch: true,
            systemProxy: true,
            tunEnable: true,
            isStart: true,
            suspended: true,
            groups: const [group],
            selectedMap: const {'Proxy': 'A'},
            showTrayTitle: true,
            monochromeTrayIcon: false,
            safeMode: true,
            hotKeys: {
              HotAction.view: _bind(HotAction.view, PhysicalKeyboardKey.keyV),
              HotAction.delayTest: _bind(
                HotAction.delayTest,
                PhysicalKeyboardKey.keyD,
              ),
              HotAction.copyEnv: _bind(
                HotAction.copyEnv,
                PhysicalKeyboardKey.keyC,
              ),
            },
          ),
          read: container.read,
        );

        final scheme = container.read(genColorSchemeProvider(Brightness.dark));
        final l10n = currentAppLocalizations;
        expect(panel.isStart, isTrue);
        expect(panel.suspended, isTrue);
        expect(panel.safeMode, isTrue);
        expect(panel.mode, 'global');
        expect(panel.tunEnable, isTrue);
        expect(panel.systemProxy, isTrue);
        expect(panel.showTrayTitle, isTrue);
        expect(panel.monochromeTrayIcon, isFalse);
        expect(panel.autoLaunch, isTrue);
        expect(panel.port, 7890);
        expect(panel.theme.isDark, isTrue);
        expect(panel.theme.pureBlack, isTrue);
        expect(
          panel.theme.glassTint,
          Colors.black.withValues(alpha: 0.86).toARGB32(),
        );
        expect(
          panel.theme.cardBg,
          SurfaceLevel.card.colorOf(scheme).toARGB32(),
        );
        expect(
          panel.theme.blockBg,
          SurfaceLevel.block.colorOf(scheme).toARGB32(),
        );
        expect(
          panel.theme.insetBg,
          SurfaceLevel.inset.colorOf(scheme).toARGB32(),
        );
        expect(panel.theme.primary, scheme.primary.toARGB32());
        expect(panel.theme.success, scheme.success.toARGB32());
        expect(panel.theme.warning, scheme.warning.toARGB32());
        expect(panel.theme.error, scheme.error.toARGB32());
        expect(panel.labels.monochromeIcon, l10n.monochromeIcon);
        expect(panel.labels.noProxies, l10n.nullTip(l10n.proxies));
        expect(panel.labels.safeMode, l10n.safeMode);
        expect(panel.shortcuts.showWindow, '⌃⇧V');
        expect(panel.shortcuts.testAllDelays, '⌃⇧D');
        expect(panel.shortcuts.copyEnv, '⌃⇧C');
        expect(panel.shortcuts.exit, '');
        expect(panel.groups, hasLength(1));
        final panelGroup = panel.groups.single;
        expect(panelGroup.selectedProxyName, 'A');
        expect(panelGroup.selectedDelay, 85);
        expect(panelGroup.testing, isTrue);
        expect(panelGroup.proxies[0].selected, isTrue);
        expect(panelGroup.proxies[0].delay, 85);
        expect(panelGroup.proxies[2].testing, isTrue);
      },
    );

    test('buildPanelTraffic formats up and down speeds', () {
      final traffic = tray.buildPanelTraffic(
        const Traffic(up: 1024, down: 2048),
      );
      expect(traffic.up, '1 KB/s');
      expect(traffic.down, '2 KB/s');
    });

    test(
      'handlePanelAction routes all 13 actions and tracks testAllDelays',
      () async {
        final events = <String>[];
        final testAllCompleter = Completer<void>();
        final windowCalls = <String>[];
        const windowChannel = MethodChannel('window');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, (call) async {
              windowCalls.add(call.method);
              return call.method == 'isMinimized' ? false : null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(windowChannel, null),
        );

        container.dispose();
        container = ProviderContainer(
          overrides: [
            commonActionProvider.overrideWith(() => _TestCommonAction(events)),
            systemActionProvider.overrideWith(() => _TestSystemAction(events)),
            setupActionProvider.overrideWith(() => _TestSetupAction(events)),
            proxiesActionProvider.overrideWith(
              () => _TestProxiesAction(events, testAllCompleter.future),
            ),
            groupsProvider.overrideWithBuild(
              (_, _) => [_proxyGroup.copyWith(hidden: false)],
            ),
          ],
        );

        for (final action in [
          const TrayPanelAction(TrayPanelActionNames.showWindow),
          const TrayPanelAction(TrayPanelActionNames.toggleRunning),
          const TrayPanelAction(TrayPanelActionNames.setMode, {
            'mode': 'direct',
          }),
          const TrayPanelAction(TrayPanelActionNames.setMode, {
            'mode': 'bogus',
          }),
          const TrayPanelAction(TrayPanelActionNames.toggleTun),
          const TrayPanelAction(TrayPanelActionNames.toggleSystemProxy),
          const TrayPanelAction(TrayPanelActionNames.toggleSpeedStatistics),
          const TrayPanelAction(TrayPanelActionNames.toggleMonochromeIcon),
          const TrayPanelAction(TrayPanelActionNames.toggleAutoLaunch),
          const TrayPanelAction(TrayPanelActionNames.selectProxy, {
            'groupName': 'Proxy',
            'proxyName': 'B',
          }),
          const TrayPanelAction(TrayPanelActionNames.testGroupDelay, {
            'groupName': 'Proxy',
          }),
          const TrayPanelAction(TrayPanelActionNames.copyEnv),
          const TrayPanelAction(TrayPanelActionNames.quit),
        ]) {
          tray.handlePanelAction(action, read: container.read);
        }
        await Future<void>.delayed(Duration.zero);

        expect(
          calls.where((call) => call.method == 'closePanel'),
          hasLength(2),
        );
        expect(windowCalls, containsAll(<String>['show', 'focus']));
        expect(events, [
          'toggleRunning',
          'changeMode:direct',
          'updateTun',
          'updateSystemProxy',
          'updateSpeedStatistics',
          'updateMonochromeTrayIcon',
          'updateAutoLaunch',
          'changeProxy:Proxy->B',
          'delayTest:Proxy',
          'copyProxyEnv',
          'handleExit',
        ]);

        tray.handlePanelAction(
          const TrayPanelAction(TrayPanelActionNames.testAllDelays),
          read: container.read,
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          tray
              .buildPanelState(
                trayState: _trayState(groups: const [_proxyGroup]),
                read: container.read,
              )
              .testingAll,
          isTrue,
        );

        testAllCompleter.complete();
        await Future<void>.delayed(Duration.zero);
        expect(
          tray
              .buildPanelState(
                trayState: _trayState(groups: const [_proxyGroup]),
                read: container.read,
              )
              .testingAll,
          isFalse,
        );
      },
    );
  });
}

class _TestCommonAction extends CommonAction {
  _TestCommonAction(this.events);
  final List<String> events;

  @override
  void toggleRunning() => events.add('toggleRunning');

  @override
  void updateSpeedStatistics() => events.add('updateSpeedStatistics');

  @override
  void updateMonochromeTrayIcon() => events.add('updateMonochromeTrayIcon');
}

class _TestSystemAction extends SystemAction {
  _TestSystemAction(this.events);
  final List<String> events;

  @override
  void updateTun() => events.add('updateTun');

  @override
  void updateSystemProxy() => events.add('updateSystemProxy');

  @override
  void updateAutoLaunch() => events.add('updateAutoLaunch');

  @override
  Future<void> copyProxyEnv() async => events.add('copyProxyEnv');

  @override
  Future<void> handleExit([bool needSave = true]) async =>
      events.add('handleExit');
}

class _TestSetupAction extends SetupAction {
  _TestSetupAction(this.events);
  final List<String> events;

  @override
  void changeMode(Mode mode) => events.add('changeMode:${mode.name}');
}

class _TestProxiesAction extends ProxiesAction {
  _TestProxiesAction(this.events, this.testAllFuture);
  final List<String> events;
  final Future<void> testAllFuture;

  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    events.add('changeProxy:$groupName->$proxyName');
  }

  @override
  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    events.add('delayTest:Proxy');
  }

  @override
  Future<void> delayTestGroups(List<Group> groups) async {
    events.add('delayTestGroups:${groups.length}');
    await testAllFuture;
  }
}
