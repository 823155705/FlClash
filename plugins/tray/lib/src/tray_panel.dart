import 'package:flutter/foundation.dart';

abstract final class TrayPanelActionNames {
  static const String showWindow = 'showWindow';
  static const String toggleRunning = 'toggleRunning';
  static const String setMode = 'setMode';
  static const String toggleTun = 'toggleTun';
  static const String toggleSystemProxy = 'toggleSystemProxy';
  static const String toggleSpeedStatistics = 'toggleSpeedStatistics';
  static const String toggleMonochromeIcon = 'toggleMonochromeIcon';
  static const String toggleAutoLaunch = 'toggleAutoLaunch';
  static const String selectProxy = 'selectProxy';
  static const String testGroupDelay = 'testGroupDelay';
  static const String testAllDelays = 'testAllDelays';
  static const String copyEnv = 'copyEnv';
  static const String quit = 'quit';
}

final class TrayPanelTheme {
  const TrayPanelTheme({
    required this.isDark,
    required this.pureBlack,
    required this.glassTint,
    required this.cardBg,
    required this.blockBg,
    required this.insetBg,
    required this.hairline,
    required this.primary,
    required this.onPrimary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
  });

  final bool isDark;
  final bool pureBlack;
  final int glassTint;
  final int cardBg;
  final int blockBg;
  final int insetBg;
  final int hairline;
  final int primary;
  final int onPrimary;
  final int onSurface;
  final int onSurfaceVariant;
  final int success;
  final int warning;
  final int error;
  final int onError;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'isDark': isDark,
      'pureBlack': pureBlack,
      'glassTint': glassTint,
      'cardBg': cardBg,
      'blockBg': blockBg,
      'insetBg': insetBg,
      'hairline': hairline,
      'primary': primary,
      'onPrimary': onPrimary,
      'onSurface': onSurface,
      'onSurfaceVariant': onSurfaceVariant,
      'success': success,
      'warning': warning,
      'error': error,
      'onError': onError,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelTheme &&
        other.isDark == isDark &&
        other.pureBlack == pureBlack &&
        other.glassTint == glassTint &&
        other.cardBg == cardBg &&
        other.blockBg == blockBg &&
        other.insetBg == insetBg &&
        other.hairline == hairline &&
        other.primary == primary &&
        other.onPrimary == onPrimary &&
        other.onSurface == onSurface &&
        other.onSurfaceVariant == onSurfaceVariant &&
        other.success == success &&
        other.warning == warning &&
        other.error == error &&
        other.onError == onError;
  }

  @override
  int get hashCode {
    return Object.hash(
      isDark,
      pureBlack,
      glassTint,
      cardBg,
      blockBg,
      insetBg,
      hairline,
      primary,
      onPrimary,
      onSurface,
      onSurfaceVariant,
      success,
      warning,
      error,
      onError,
    );
  }
}

final class TrayPanelLabels {
  const TrayPanelLabels({
    required this.appName,
    required this.showWindow,
    required this.start,
    required this.stop,
    required this.modeRule,
    required this.modeGlobal,
    required this.modeDirect,
    required this.tun,
    required this.systemProxy,
    required this.speedStatistics,
    required this.monochromeIcon,
    required this.autoLaunch,
    required this.proxies,
    required this.search,
    required this.testAllDelays,
    required this.delayTest,
    required this.timeout,
    required this.delayFailed,
    required this.copyEnvVar,
    required this.exit,
    required this.noProxies,
    required this.safeMode,
  });

  final String appName;
  final String showWindow;
  final String start;
  final String stop;
  final String modeRule;
  final String modeGlobal;
  final String modeDirect;
  final String tun;
  final String systemProxy;
  final String speedStatistics;
  final String monochromeIcon;
  final String autoLaunch;
  final String proxies;
  final String search;
  final String testAllDelays;
  final String delayTest;
  final String timeout;
  final String delayFailed;
  final String copyEnvVar;
  final String exit;
  final String noProxies;
  final String safeMode;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'appName': appName,
      'showWindow': showWindow,
      'start': start,
      'stop': stop,
      'modeRule': modeRule,
      'modeGlobal': modeGlobal,
      'modeDirect': modeDirect,
      'tun': tun,
      'systemProxy': systemProxy,
      'speedStatistics': speedStatistics,
      'monochromeIcon': monochromeIcon,
      'autoLaunch': autoLaunch,
      'proxies': proxies,
      'search': search,
      'testAllDelays': testAllDelays,
      'delayTest': delayTest,
      'timeout': timeout,
      'delayFailed': delayFailed,
      'copyEnvVar': copyEnvVar,
      'exit': exit,
      'noProxies': noProxies,
      'safeMode': safeMode,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelLabels &&
        other.appName == appName &&
        other.showWindow == showWindow &&
        other.start == start &&
        other.stop == stop &&
        other.modeRule == modeRule &&
        other.modeGlobal == modeGlobal &&
        other.modeDirect == modeDirect &&
        other.tun == tun &&
        other.systemProxy == systemProxy &&
        other.speedStatistics == speedStatistics &&
        other.monochromeIcon == monochromeIcon &&
        other.autoLaunch == autoLaunch &&
        other.proxies == proxies &&
        other.search == search &&
        other.testAllDelays == testAllDelays &&
        other.delayTest == delayTest &&
        other.timeout == timeout &&
        other.delayFailed == delayFailed &&
        other.copyEnvVar == copyEnvVar &&
        other.exit == exit &&
        other.noProxies == noProxies &&
        other.safeMode == safeMode;
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object?>[
      appName,
      showWindow,
      start,
      stop,
      modeRule,
      modeGlobal,
      modeDirect,
      tun,
      systemProxy,
      speedStatistics,
      monochromeIcon,
      autoLaunch,
      proxies,
      search,
      testAllDelays,
      delayTest,
      timeout,
      delayFailed,
      copyEnvVar,
      exit,
      noProxies,
      safeMode,
    ]);
  }
}

final class TrayPanelShortcuts {
  const TrayPanelShortcuts({
    this.showWindow = '',
    this.toggleRunning = '',
    this.modeRule = '',
    this.modeGlobal = '',
    this.modeDirect = '',
    this.testAllDelays = '',
    this.tun = '',
    this.systemProxy = '',
    this.copyEnv = '',
    this.exit = '',
  });

  final String showWindow;
  final String toggleRunning;
  final String modeRule;
  final String modeGlobal;
  final String modeDirect;
  final String testAllDelays;
  final String tun;
  final String systemProxy;
  final String copyEnv;
  final String exit;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'showWindow': showWindow,
      'toggleRunning': toggleRunning,
      'modeRule': modeRule,
      'modeGlobal': modeGlobal,
      'modeDirect': modeDirect,
      'testAllDelays': testAllDelays,
      'tun': tun,
      'systemProxy': systemProxy,
      'copyEnv': copyEnv,
      'exit': exit,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelShortcuts &&
        other.showWindow == showWindow &&
        other.toggleRunning == toggleRunning &&
        other.modeRule == modeRule &&
        other.modeGlobal == modeGlobal &&
        other.modeDirect == modeDirect &&
        other.testAllDelays == testAllDelays &&
        other.tun == tun &&
        other.systemProxy == systemProxy &&
        other.copyEnv == copyEnv &&
        other.exit == exit;
  }

  @override
  int get hashCode {
    return Object.hash(
      showWindow,
      toggleRunning,
      modeRule,
      modeGlobal,
      modeDirect,
      testAllDelays,
      tun,
      systemProxy,
      copyEnv,
      exit,
    );
  }
}

final class TrayPanelProxy {
  const TrayPanelProxy({
    required this.name,
    required this.type,
    this.delay,
    this.testing = false,
    this.selected = false,
  });

  final String name;
  final String type;
  final int? delay;
  final bool testing;
  final bool selected;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'type': type,
      'delay': delay,
      'testing': testing,
      'selected': selected,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelProxy &&
        other.name == name &&
        other.type == type &&
        other.delay == delay &&
        other.testing == testing &&
        other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(name, type, delay, testing, selected);
}

final class TrayPanelGroup {
  const TrayPanelGroup({
    required this.name,
    required this.type,
    required this.selectedProxyName,
    this.selectedDelay,
    this.testing = false,
    this.proxies = const <TrayPanelProxy>[],
  });

  final String name;
  final String type;
  final String selectedProxyName;
  final int? selectedDelay;
  final bool testing;
  final List<TrayPanelProxy> proxies;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'type': type,
      'selectedProxyName': selectedProxyName,
      'selectedDelay': selectedDelay,
      'testing': testing,
      'proxies': <Map<String, Object?>>[
        for (final proxy in proxies) proxy.toMap(),
      ],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelGroup &&
        other.name == name &&
        other.type == type &&
        other.selectedProxyName == selectedProxyName &&
        other.selectedDelay == selectedDelay &&
        other.testing == testing &&
        listEquals(other.proxies, proxies);
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      type,
      selectedProxyName,
      selectedDelay,
      testing,
      Object.hashAll(proxies),
    );
  }
}

final class TrayPanelState {
  const TrayPanelState({
    required this.isStart,
    this.suspended = false,
    this.safeMode = false,
    required this.mode,
    required this.tunEnable,
    required this.systemProxy,
    required this.showTrayTitle,
    this.monochromeTrayIcon = false,
    required this.autoLaunch,
    required this.port,
    this.testingAll = false,
    required this.theme,
    required this.labels,
    this.shortcuts = const TrayPanelShortcuts(),
    this.groups = const <TrayPanelGroup>[],
  });

  final bool isStart;
  final bool suspended;
  final bool safeMode;
  final String mode;
  final bool tunEnable;
  final bool systemProxy;
  final bool showTrayTitle;
  final bool monochromeTrayIcon;
  final bool autoLaunch;
  final int port;
  final bool testingAll;
  final TrayPanelTheme theme;
  final TrayPanelLabels labels;
  final TrayPanelShortcuts shortcuts;
  final List<TrayPanelGroup> groups;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'isStart': isStart,
      'suspended': suspended,
      'safeMode': safeMode,
      'mode': mode,
      'tunEnable': tunEnable,
      'systemProxy': systemProxy,
      'showTrayTitle': showTrayTitle,
      'monochromeTrayIcon': monochromeTrayIcon,
      'autoLaunch': autoLaunch,
      'port': port,
      'testingAll': testingAll,
      'theme': theme.toMap(),
      'labels': labels.toMap(),
      'shortcuts': shortcuts.toMap(),
      'groups': <Map<String, Object?>>[
        for (final group in groups) group.toMap(),
      ],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelState &&
        other.isStart == isStart &&
        other.suspended == suspended &&
        other.safeMode == safeMode &&
        other.mode == mode &&
        other.tunEnable == tunEnable &&
        other.systemProxy == systemProxy &&
        other.showTrayTitle == showTrayTitle &&
        other.monochromeTrayIcon == monochromeTrayIcon &&
        other.autoLaunch == autoLaunch &&
        other.port == port &&
        other.testingAll == testingAll &&
        other.theme == theme &&
        other.labels == labels &&
        other.shortcuts == shortcuts &&
        listEquals(other.groups, groups);
  }

  @override
  int get hashCode {
    return Object.hash(
      isStart,
      suspended,
      safeMode,
      mode,
      tunEnable,
      systemProxy,
      showTrayTitle,
      monochromeTrayIcon,
      autoLaunch,
      port,
      testingAll,
      theme,
      labels,
      shortcuts,
      Object.hashAll(groups),
    );
  }
}

final class TrayPanelTraffic {
  const TrayPanelTraffic({required this.up, required this.down});

  final String up;
  final String down;

  Map<String, Object?> toMap() {
    return <String, Object?>{'up': up, 'down': down};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is TrayPanelTraffic && other.up == up && other.down == down;
  }

  @override
  int get hashCode => Object.hash(up, down);
}
