import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/locale_manager.dart';
import 'package:fl_clash/manager/tray_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tray/tray.dart';

import '../helpers/test_profiles.dart';
import '../helpers/test_app.dart';

const _trayChannel = MethodChannel('tray');
const _windowChannel = MethodChannel('window');
const _codec = StandardMethodCodec();

class _RecordingSystemAction extends SystemAction {
  static int updateTrayCount = 0;
  static final List<String> updateTrayLocales = <String>[];

  @override
  Future<void> updateTray() async {
    updateTrayCount++;
    updateTrayLocales.add(Intl.getCurrentLocale());
  }
}

class _FailingSystemAction extends SystemAction {
  @override
  Future<void> updateTray() async {
    throw StateError('tray boom');
  }
}

class _SlowFirstFailureSystemAction extends SystemAction {
  static int updateTrayCount = 0;
  static Completer<void> firstUpdate = Completer<void>();

  @override
  Future<void> updateTray() async {
    if (updateTrayCount++ == 0) {
      await firstUpdate.future;
      throw StateError('tray boom');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late List<String> windowCalls;
  late List<MethodCall> trayCalls;

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    _RecordingSystemAction.updateTrayCount = 0;
    _RecordingSystemAction.updateTrayLocales.clear();
    windowCalls = <String>[];
    trayCalls = <MethodCall>[];
    Tray.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_trayChannel, (call) async {
          trayCalls.add(call);
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          windowCalls.add(call.method);
          return call.method == 'isMinimized' ? false : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_trayChannel, null)
      ..setMockMethodCallHandler(_windowChannel, null);
    container.dispose();
  });

  Future<void> emitTrayEvent(String event, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _trayChannel.name,
          _codec.encodeMethodCall(MethodCall(event, arguments)),
          null,
        );
  }

  Future<void> pumpTrayManager(
    WidgetTester tester, {
    SystemAction Function()? systemAction,
    AppTray? tray,
  }) async {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        systemActionProvider.overrideWith(
          systemAction ?? _RecordingSystemAction.new,
        ),
      ],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          home: TrayManager(tray: tray, child: const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpLocalizedTrayManager(
    WidgetTester tester,
    Locale locale,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          locale: locale,
          home: const LocaleManager(
            child: TrayManager(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders its child untouched', (tester) async {
    await pumpTrayManager(tester);

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('activating the icon brings the window back', (tester) async {
    await pumpTrayManager(tester);
    windowCalls.clear();

    await emitTrayEvent('onIconActivated');
    await tester.pumpAndSettle();
    // A macOS host arms the Dock settle timer on show; drain it so the binding
    // ends the test with no pending timer.
    await tester.pump(const Duration(seconds: 1));

    expect(windowCalls, containsAll(<String>['show', 'focus']));
  });

  testWidgets('a menu request is forwarded to the tray', (tester) async {
    await pumpTrayManager(tester);

    await emitTrayEvent('onMenuRequested');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a tray state change pushes the tray forward', (tester) async {
    await pumpTrayManager(tester);
    _RecordingSystemAction.updateTrayCount = 0;

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: state.mixedPort + 1));
    await tester.pumpAndSettle();

    expect(_RecordingSystemAction.updateTrayCount, 1);
  });

  testWidgets('an unchanged tray state does not touch the tray', (
    tester,
  ) async {
    await pumpTrayManager(tester);
    _RecordingSystemAction.updateTrayCount = 0;

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: state.mixedPort));
    await tester.pumpAndSettle();

    expect(_RecordingSystemAction.updateTrayCount, 0);
  });

  testWidgets('a failed tray update is reported instead of thrown', (
    tester,
  ) async {
    await pumpTrayManager(tester, systemAction: _FailingSystemAction.new);

    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: state.mixedPort + 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a change made during a failing update still reaches the tray', (
    tester,
  ) async {
    _SlowFirstFailureSystemAction.updateTrayCount = 0;
    _SlowFirstFailureSystemAction.firstUpdate = Completer<void>();
    await pumpTrayManager(
      tester,
      systemAction: _SlowFirstFailureSystemAction.new,
    );

    for (var i = 0; i < 2; i++) {
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: state.mixedPort + 1));
      await tester.pump();
    }
    expect(_SlowFirstFailureSystemAction.updateTrayCount, 1);

    _SlowFirstFailureSystemAction.firstUpdate.complete();
    await tester.pumpAndSettle();

    expect(_SlowFirstFailureSystemAction.updateTrayCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a language switch pushes the tray in the new language', (
    tester,
  ) async {
    addTearDown(() => AppLocalizations.load(const Locale('en')));
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        systemActionProvider.overrideWith(_RecordingSystemAction.new),
      ],
    );
    globalState.container = container;
    await pumpLocalizedTrayManager(tester, const Locale('en'));
    _RecordingSystemAction.updateTrayCount = 0;
    _RecordingSystemAction.updateTrayLocales.clear();

    await pumpLocalizedTrayManager(tester, const Locale('zh', 'CN'));

    expect(_RecordingSystemAction.updateTrayCount, 1);
    expect(_RecordingSystemAction.updateTrayLocales, <String>['zh_CN']);
  });

  testWidgets('the locale a language switch starts from does not push twice', (
    tester,
  ) async {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        systemActionProvider.overrideWith(_RecordingSystemAction.new),
      ],
    );
    globalState.container = container;
    await pumpLocalizedTrayManager(tester, const Locale('en'));
    _RecordingSystemAction.updateTrayCount = 0;

    await pumpLocalizedTrayManager(tester, const Locale('en'));

    expect(_RecordingSystemAction.updateTrayCount, 0);
  });

  testWidgets('tray events stop being handled after disposal', (tester) async {
    await pumpTrayManager(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    windowCalls.clear();

    await emitTrayEvent('onIconActivated');
    await tester.pumpAndSettle();

    expect(windowCalls, isEmpty);
  });

  group('tray panel integration', () {
    late AppTray macTray;

    setUp(() {
      macTray = AppTray.forPlatform(isMacOS: true, isWindows: false);
    });

    Future<void> runMacOS(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<void> showTrayIcon(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Tray.instance.show(
          const TraySpec(
            icon: TrayIcon.asset('assets/images/tray/macos/status_1.png'),
          ),
        );
      });
      expect(Tray.instance.isVisible, isTrue);
      trayCalls.clear();
    }

    Future<void> flushTray(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'menu request toggles panel on macOS and icon click closes open panel',
      (tester) async {
        await runMacOS(() async {
          await pumpTrayManager(tester, tray: macTray);
          await showTrayIcon(tester);

          await emitTrayEvent('onMenuRequested');
          await flushTray(tester);
          expect(trayCalls.map((c) => c.method), ['togglePanel']);

          trayCalls.clear();
          await emitTrayEvent('onPanelVisibilityChanged', {'visible': true});
          await flushTray(tester);

          trayCalls.clear();
          windowCalls.clear();
          await emitTrayEvent('onIconActivated');
          await flushTray(tester);
          await tester.pump(const Duration(seconds: 1));

          expect(trayCalls.map((c) => c.method), contains('closePanel'));
          expect(windowCalls, containsAll(<String>['show', 'focus']));
        });
      },
    );

    testWidgets('streams panel traffic, delays and theme only while visible', (
      tester,
    ) async {
      await runMacOS(() async {
        await pumpTrayManager(tester, tray: macTray);
        container
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(showTrayTitle: false));
        await showTrayIcon(tester);

        // Hidden: changes do not push panel traffic or panel state.
        container
            .read(trafficsProvider.notifier)
            .addTraffic(const Traffic(up: 100, down: 200));
        container.read(delayDataSourceProvider.notifier).setDelays([
          const Delay(url: defaultTestUrl, name: 'A', value: 42),
        ]);
        container
            .read(themeSettingProvider.notifier)
            .update((state) => state.copyWith(pureBlack: true));
        await tester.pump(const Duration(milliseconds: 80));
        await flushTray(tester);

        expect(trayCalls, isEmpty);
        expect(container.read(trayPanelVisibleProvider), isFalse);

        // Visible: immediately syncs state + traffic and attaches live streams.
        await emitTrayEvent('onPanelVisibilityChanged', {'visible': true});
        await flushTray(tester);

        expect(container.read(trayPanelVisibleProvider), isTrue);
        expect(
          trayCalls.map((c) => c.method),
          containsAll(['setPanelState', 'setPanelTraffic']),
        );

        trayCalls.clear();
        container
            .read(trafficsProvider.notifier)
            .addTraffic(const Traffic(up: 1024, down: 4096));
        await flushTray(tester);
        expect(trayCalls.map((c) => c.method), ['setPanelTraffic']);

        // Delay bursts coalesce over 50ms debounce.
        container.read(groupsProvider.notifier).value = const [
          Group(
            name: 'Proxy',
            type: GroupType.Selector,
            hidden: false,
            all: [Proxy(name: 'A', type: 'Direct')],
          ),
        ];
        await flushTray(tester);
        trayCalls.clear();
        container.read(delayDataSourceProvider.notifier).setDelays([
          const Delay(url: defaultTestUrl, name: 'A', value: 55),
        ]);
        container.read(delayDataSourceProvider.notifier).setDelays([
          const Delay(url: defaultTestUrl, name: 'A', value: 88),
        ]);
        await tester.pump(const Duration(milliseconds: 20));
        expect(trayCalls, isEmpty);
        await tester.pump(const Duration(milliseconds: 40));
        await flushTray(tester);
        expect(trayCalls.map((c) => c.method), ['setPanelState']);

        // Theme change pushes immediately while visible.
        trayCalls.clear();
        container
            .read(themeSettingProvider.notifier)
            .update((state) => state.copyWith(primaryColor: 0xFF34C759));
        await flushTray(tester);
        expect(trayCalls.map((c) => c.method), ['setPanelState']);

        // Closing detaches subscriptions.
        await emitTrayEvent('onPanelVisibilityChanged', {'visible': false});
        await flushTray(tester);
        expect(container.read(trayPanelVisibleProvider), isFalse);

        trayCalls.clear();
        container
            .read(trafficsProvider.notifier)
            .addTraffic(const Traffic(up: 2048, down: 8192));
        container
            .read(themeSettingProvider.notifier)
            .update((state) => state.copyWith(pureBlack: true));
        await tester.pump(const Duration(milliseconds: 80));
        await flushTray(tester);
        expect(trayCalls, isEmpty);
      });
    });

    testWidgets('forwards panel actions to AppTray', (tester) async {
      await runMacOS(() async {
        await pumpTrayManager(tester, tray: macTray);
        final before = container.read(appSettingProvider).monochromeTrayIcon;

        await emitTrayEvent('onPanelAction', {
          'action': TrayPanelActionNames.toggleMonochromeIcon,
          'payload': const <String, Object?>{},
        });
        await tester.pumpAndSettle();

        expect(container.read(appSettingProvider).monochromeTrayIcon, !before);
      });
    });
  });
}
