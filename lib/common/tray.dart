import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_ui/prism_ui.dart';
import 'package:tray/tray.dart';

import 'app_localizations.dart';
import 'app_ports.dart';
import 'compute.dart';
import 'constant.dart';
import 'keyboard.dart';
import 'l10n_labels.dart';
import 'num.dart';
import 'provider_reader.dart';
import 'string.dart';
import 'system.dart';
import 'window.dart';

class AppTray implements TrayPort {
  static AppTray? _instance;

  final bool isMacOS;
  final bool isWindows;

  bool _isShutDown = false;
  int _testingAllInFlight = 0;

  AppTray._internal({required this.isMacOS, required this.isWindows});

  factory AppTray() {
    _instance ??= AppTray._internal(
      isMacOS: system.isMacOS,
      isWindows: system.isWindows,
    );
    return _instance!;
  }

  @visibleForTesting
  factory AppTray.forPlatform({
    required bool isMacOS,
    required bool isWindows,
  }) {
    return AppTray._internal(isMacOS: isMacOS, isWindows: isWindows);
  }

  String get _trayIconSuffix {
    return isWindows ? 'ico' : 'png';
  }

  bool _isTemplate(bool monochrome) => isMacOS && monochrome;

  String _trayIconDir(bool monochrome) {
    if (isWindows) {
      return 'assets/images/tray/windows';
    }
    return _isTemplate(monochrome)
        ? 'assets/images/tray/macos'
        : 'assets/images/tray/unix';
  }

  String getTrayIcon({
    required bool isStart,
    required bool tunEnable,
    required bool safeMode,
    bool monochrome = true,
  }) {
    final status = switch ((
      safeMode,
      _isTemplate(monochrome) || !isStart,
      tunEnable,
    )) {
      (true, _, _) => 4,
      (false, true, _) => 1,
      (false, false, false) => 2,
      (false, false, true) => 3,
    };
    return '${_trayIconDir(monochrome)}/status_$status.$_trayIconSuffix';
  }

  @override
  Future<void> shutdown() async {
    _isShutDown = true;
    // Removing a status item makes macOS forget where the user dragged it in
    // the menu bar; one that goes away with the process keeps its place.
    if (isMacOS) {
      await Tray.instance.closePanel();
      return;
    }
    await Tray.instance.hide();
  }

  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {
    if (_isShutDown) {
      return;
    }
    await Tray.instance.show(
      TraySpec(
        icon: TrayIcon.asset(
          getTrayIcon(
            isStart: trayState.isStart && !trayState.suspended,
            tunEnable: trayState.tunEnable,
            safeMode: trayState.safeMode,
            monochrome: trayState.monochromeTrayIcon,
          ),
          isTemplate: _isTemplate(trayState.monochromeTrayIcon),
          size: isMacOS ? 18 : 16,
        ),
        toolTip: trayState.safeMode
            ? currentAppLocalizations.safeModeAppTitle(appName)
            : appName,
        menu: _buildMenu(trayState: trayState, read: read),
      ),
    );
    await updateTitle(showTrayTitle: trayState.showTrayTitle, traffic: traffic);
    await updatePanel(trayState: trayState, read: read);
  }

  Future<void> updateTitle({
    required bool showTrayTitle,
    required Traffic traffic,
  }) async {
    if (_isShutDown || !isMacOS) {
      return;
    }
    await Tray.instance.setTitle(showTrayTitle ? traffic.trayTitle : '');
  }

  Future<void> updatePanel({
    required TrayState trayState,
    required ProviderReader read,
  }) async {
    if (_isShutDown || !isMacOS || !Tray.instance.capabilities.panel) {
      return;
    }
    await Tray.instance.setPanelState(
      buildPanelState(trayState: trayState, read: read),
    );
  }

  Future<void> updatePanelTraffic(Traffic traffic) async {
    if (_isShutDown || !isMacOS || !Tray.instance.capabilities.panel) {
      return;
    }
    await Tray.instance.setPanelTraffic(buildPanelTraffic(traffic));
  }

  @visibleForTesting
  TrayPanelTraffic buildPanelTraffic(Traffic traffic) {
    return TrayPanelTraffic(
      up: '${traffic.up.shortTraffic.show}/s',
      down: '${traffic.down.shortTraffic.show}/s',
    );
  }

  @visibleForTesting
  TrayPanelState buildPanelState({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final appLocalizations = currentAppLocalizations;
    String shortcut(HotAction action) => _shortcut(trayState, action) ?? '';
    return TrayPanelState(
      isStart: trayState.isStart,
      suspended: trayState.suspended,
      safeMode: trayState.safeMode,
      mode: trayState.mode.name,
      tunEnable: trayState.tunEnable,
      systemProxy: trayState.systemProxy,
      showTrayTitle: trayState.showTrayTitle,
      monochromeTrayIcon: trayState.monochromeTrayIcon,
      autoLaunch: trayState.autoLaunch,
      port: trayState.port,
      testingAll: _testingAllInFlight > 0,
      theme: _buildPanelTheme(read),
      labels: TrayPanelLabels(
        appName: appName,
        showWindow: appLocalizations.show,
        start: appLocalizations.start,
        stop: appLocalizations.stop,
        modeRule: Mode.rule.label,
        modeGlobal: Mode.global.label,
        modeDirect: Mode.direct.label,
        tun: appLocalizations.tun,
        systemProxy: appLocalizations.systemProxy,
        speedStatistics: appLocalizations.speedStatistics,
        monochromeIcon: appLocalizations.monochromeIcon,
        autoLaunch: appLocalizations.autoLaunch,
        proxies: appLocalizations.proxies,
        search: appLocalizations.search,
        testAllDelays: HotAction.delayTest.label,
        delayTest: appLocalizations.delayTest,
        timeout: appLocalizations.timeout,
        delayFailed: appLocalizations.delayFailed,
        copyEnvVar: appLocalizations.copyEnvVar,
        exit: appLocalizations.exit,
        noProxies: appLocalizations.nullTip(appLocalizations.proxies),
        safeMode: appLocalizations.safeMode,
      ),
      shortcuts: TrayPanelShortcuts(
        showWindow: shortcut(HotAction.view),
        toggleRunning: shortcut(HotAction.start),
        modeRule: shortcut(HotAction.ruleMode),
        modeGlobal: shortcut(HotAction.globalMode),
        modeDirect: shortcut(HotAction.directMode),
        testAllDelays: shortcut(HotAction.delayTest),
        tun: shortcut(HotAction.tun),
        systemProxy: shortcut(HotAction.proxy),
        copyEnv: shortcut(HotAction.copyEnv),
        exit: shortcut(HotAction.exit),
      ),
      groups: _buildPanelGroups(trayState: trayState, read: read),
    );
  }

  TrayPanelTheme _buildPanelTheme(ProviderReader read) {
    final brightness = read(currentBrightnessProvider);
    final isDark = brightness == Brightness.dark;
    final pureBlack = isDark && read(themeSettingProvider).pureBlack;
    final colorScheme = read(genColorSchemeProvider(brightness));
    final glassTint = pureBlack
        ? Colors.black.withValues(alpha: 0.86)
        : isDark
        ? colorScheme.surfaceContainer.shiftTone(7.0).withValues(alpha: 0.62)
        : colorScheme.surfaceBright.withValues(alpha: 0.55);
    return TrayPanelTheme(
      isDark: isDark,
      pureBlack: pureBlack,
      glassTint: glassTint.toARGB32(),
      cardBg: SurfaceLevel.card.colorOf(colorScheme).toARGB32(),
      blockBg: SurfaceLevel.block.colorOf(colorScheme).toARGB32(),
      insetBg: SurfaceLevel.inset.colorOf(colorScheme).toARGB32(),
      hairline: colorScheme.onSurface.withValues(alpha: 0.14).toARGB32(),
      primary: colorScheme.primary.toARGB32(),
      onPrimary: colorScheme.onPrimary.toARGB32(),
      onSurface: colorScheme.onSurface.toARGB32(),
      onSurfaceVariant: colorScheme.onSurfaceVariant.toARGB32(),
      success: colorScheme.success.toARGB32(),
      warning: colorScheme.warning.toARGB32(),
      error: colorScheme.error.toARGB32(),
      onError: colorScheme.onError.toARGB32(),
    );
  }

  List<TrayPanelGroup> _buildPanelGroups({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    if (trayState.groups.isEmpty) {
      return const [];
    }
    final delays = read(trayDelaysProvider);
    final pendingTests = read(pendingDelayTestsProvider);
    final testingGroups = read(delayTestingGroupsProvider);
    final allGroups = read(groupsProvider);
    final defaultTestUrl = read(patchClashConfigProvider).testUrl;
    return [
      for (final group in trayState.groups)
        _buildPanelGroup(
          group,
          selectedName: read(selectedProxyNameProvider(group.name)) ?? '',
          groupDelays: delays[group.name] ?? const {},
          groupTestUrl: group.testUrl.takeFirstValid([defaultTestUrl]),
          allGroups: allGroups,
          selectedMap: trayState.selectedMap,
          pendingTests: pendingTests,
          isGroupTesting: testingGroups.contains(group.name),
        ),
    ];
  }

  TrayPanelGroup _buildPanelGroup(
    Group group, {
    required String selectedName,
    required Map<String, int> groupDelays,
    required String groupTestUrl,
    required List<Group> allGroups,
    required Map<String, String> selectedMap,
    required Map<String, DelayTestPhase> pendingTests,
    required bool isGroupTesting,
  }) {
    var anyProxyTesting = false;
    final proxies = <TrayPanelProxy>[];
    for (final proxy in group.all) {
      final realState = computeRealSelectedProxyState(
        proxy.name,
        groups: allGroups,
        selectedMap: selectedMap,
      );
      final effectiveTestUrl = realState.testUrl.takeFirstValid([groupTestUrl]);
      final testing = pendingTests.containsKey(
        delayTestKey(effectiveTestUrl, realState.proxyName),
      );
      if (testing) {
        anyProxyTesting = true;
      }
      proxies.add(
        TrayPanelProxy(
          name: proxy.name,
          type: proxy.type,
          delay: groupDelays[proxy.name],
          testing: testing,
          selected: selectedName == proxy.name,
        ),
      );
    }
    return TrayPanelGroup(
      name: group.name,
      type: group.type.name,
      selectedProxyName: selectedName,
      selectedDelay: groupDelays[selectedName],
      testing: anyProxyTesting || isGroupTesting,
      proxies: proxies,
    );
  }

  void handlePanelAction(
    TrayPanelAction event, {
    required ProviderReader read,
  }) {
    if (_isShutDown) {
      return;
    }
    switch (event.action) {
      case TrayPanelActionNames.showWindow:
        unawaited(Tray.instance.closePanel());
        unawaited(window?.show());
      case TrayPanelActionNames.toggleRunning:
        read(commonActionProvider.notifier).toggleRunning();
      case TrayPanelActionNames.setMode:
        final modeName = event.payload['mode'];
        if (modeName is! String) {
          return;
        }
        final mode = Mode.values
            .where((item) => item.name == modeName)
            .firstOrNull;
        if (mode != null) {
          read(setupActionProvider.notifier).changeMode(mode);
        }
      case TrayPanelActionNames.toggleTun:
        read(systemActionProvider.notifier).updateTun();
      case TrayPanelActionNames.toggleSystemProxy:
        read(systemActionProvider.notifier).updateSystemProxy();
      case TrayPanelActionNames.toggleSpeedStatistics:
        read(commonActionProvider.notifier).updateSpeedStatistics();
      case TrayPanelActionNames.toggleMonochromeIcon:
        read(commonActionProvider.notifier).updateMonochromeTrayIcon();
      case TrayPanelActionNames.toggleAutoLaunch:
        read(systemActionProvider.notifier).updateAutoLaunch();
      case TrayPanelActionNames.selectProxy:
        final groupName = event.payload['groupName'];
        final proxyName = event.payload['proxyName'];
        if (groupName is! String || proxyName is! String) {
          return;
        }
        unawaited(
          read(
            proxiesActionProvider.notifier,
          ).changeProxy(groupName: groupName, proxyName: proxyName),
        );
      case TrayPanelActionNames.testGroupDelay:
        final groupName = event.payload['groupName'];
        if (groupName is! String) {
          return;
        }
        final group = read(trayStateProvider).groups.getGroup(groupName);
        if (group == null) {
          return;
        }
        unawaited(
          read(
            proxiesActionProvider.notifier,
          ).delayTest(group.all, group.testUrl),
        );
      case TrayPanelActionNames.testAllDelays:
        final groups = read(trayStateProvider).groups;
        if (groups.isEmpty) {
          return;
        }
        unawaited(_runTestAllDelays(groups, read));
      case TrayPanelActionNames.copyEnv:
        unawaited(read(systemActionProvider.notifier).copyProxyEnv());
      case TrayPanelActionNames.quit:
        unawaited(Tray.instance.closePanel());
        unawaited(read(systemActionProvider.notifier).handleExit());
    }
  }

  Future<void> _runTestAllDelays(
    List<Group> groups,
    ProviderReader read,
  ) async {
    _testingAllInFlight++;
    await updatePanel(trayState: read(trayStateProvider), read: read);
    try {
      await read(proxiesActionProvider.notifier).delayTestGroups(groups);
    } finally {
      _testingAllInFlight = math.max(0, _testingAllInFlight - 1);
      if (!_isShutDown) {
        await updatePanel(trayState: read(trayStateProvider), read: read);
      }
    }
  }

  List<TrayMenuItem> _buildMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final commonAction = read(commonActionProvider.notifier);
    final systemAction = read(systemActionProvider.notifier);
    final setupAction = read(setupActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;
    String? shortcut(HotAction action) => _shortcut(trayState, action);
    final showItem = TrayMenuAction(
      label: appLocalizations.show,
      detail: shortcut(HotAction.view),
      onSelected: () {
        window?.show();
      },
    );
    final exitItem = TrayMenuAction(
      label: appLocalizations.exit,
      detail: shortcut(HotAction.exit),
      onSelected: () {
        systemAction.handleExit();
      },
    );

    return [
      showItem,
      TrayMenuCheckbox(
        label: trayState.isStart
            ? appLocalizations.stop
            : appLocalizations.start,
        checked: false,
        detail: shortcut(HotAction.start),
        onSelected: commonAction.toggleRunning,
      ),
      if (isMacOS) ...[
        TrayMenuCheckbox(
          label: appLocalizations.speedStatistics,
          checked: trayState.showTrayTitle,
          onSelected: commonAction.updateSpeedStatistics,
        ),
        TrayMenuCheckbox(
          label: appLocalizations.monochromeIcon,
          checked: trayState.monochromeTrayIcon,
          onSelected: commonAction.updateMonochromeTrayIcon,
        ),
      ],
      const TrayMenuSeparator(),
      for (final mode in Mode.values)
        TrayMenuCheckbox(
          label: mode.label,
          checked: mode == trayState.mode,
          detail: shortcut(switch (mode) {
            Mode.rule => HotAction.ruleMode,
            Mode.global => HotAction.globalMode,
            Mode.direct => HotAction.directMode,
          }),
          onSelected: () {
            setupAction.changeMode(mode);
          },
        ),
      const TrayMenuSeparator(),
      if (isMacOS) ..._buildGroupMenu(trayState: trayState, read: read),
      if (trayState.isStart) ...[
        TrayMenuCheckbox(
          label: appLocalizations.tun,
          checked: trayState.tunEnable,
          detail: shortcut(HotAction.tun),
          onSelected: systemAction.updateTun,
        ),
        TrayMenuCheckbox(
          label: appLocalizations.systemProxy,
          checked: trayState.systemProxy,
          detail: shortcut(HotAction.proxy),
          onSelected: systemAction.updateSystemProxy,
        ),
        const TrayMenuSeparator(),
      ],
      TrayMenuCheckbox(
        label: appLocalizations.autoLaunch,
        checked: trayState.autoLaunch,
        onSelected: systemAction.updateAutoLaunch,
      ),
      TrayMenuAction(
        label: appLocalizations.copyEnvVar,
        detail: shortcut(HotAction.copyEnv),
        onSelected: systemAction.copyProxyEnv,
      ),
      const TrayMenuSeparator(),
      exitItem,
    ];
  }

  String? _shortcut(TrayState trayState, HotAction action) {
    final hotKey = trayState.hotKeys[action];
    final key = hotKey?.key;
    if (hotKey == null || key == null) {
      return null;
    }
    return ShortcutLabels(
      isMacOS: isMacOS,
      isWindows: isWindows,
    ).text(hotKey.modifiers, key);
  }

  String? _delayText(int? delay) {
    if (delay == null) {
      return null;
    }
    return delay > 0
        ? '$delay'
        : delayFailureText(delay, currentAppLocalizations);
  }

  List<TrayMenuItem> _buildGroupMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    if (trayState.groups.isEmpty) {
      return const [];
    }
    final delays = read(trayDelaysProvider);
    final proxiesAction = read(proxiesActionProvider.notifier);
    return [
      for (final group in trayState.groups)
        _buildGroupSubmenu(
          group,
          selectedName: read(selectedProxyNameProvider(group.name)),
          delays: delays[group.name] ?? const {},
          onSelected: (proxyName) {
            proxiesAction.changeProxy(
              groupName: group.name,
              proxyName: proxyName,
            );
          },
        ),
      TrayMenuAction(
        label: HotAction.delayTest.label,
        detail: _shortcut(trayState, HotAction.delayTest),
        onSelected: () {
          proxiesAction.delayTestGroups(trayState.groups);
        },
      ),
      const TrayMenuSeparator(),
    ];
  }

  TrayMenuSubmenu _buildGroupSubmenu(
    Group group, {
    required String? selectedName,
    required Map<String, int> delays,
    required void Function(String proxyName) onSelected,
  }) {
    return TrayMenuSubmenu(
      label: group.name,
      detail: _delayText(delays[selectedName]),
      items: [
        for (final proxy in group.all)
          TrayMenuCheckbox(
            label: proxy.name,
            checked: selectedName == proxy.name,
            detail: _delayText(delays[proxy.name]),
            onSelected: () {
              onSelected(proxy.name);
            },
          ),
      ],
    );
  }
}

final appTray = system.isDesktop ? AppTray() : null;
