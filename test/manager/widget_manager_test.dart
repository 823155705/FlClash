import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/widget_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class _TestWidgetHost {
  _TestWidgetHost(this.channelName)
    : methodChannel = MethodChannel(channelName),
      channel = WidgetChannel.scoped(MethodChannel(channelName));

  final String channelName;
  final MethodChannel methodChannel;
  final WidgetChannel channel;

  bool active = true;
  Map<String, Object?>? pendingAction;
  final snapshots = <Map<String, Object?>>[];
  final invokedMethods = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          invokedMethods.add(call.method);
          switch (call.method) {
            case 'hasActiveWidgets':
              return active;
            case 'consumePendingAction':
              final next = pendingAction;
              pendingAction = null;
              return next;
            case 'updateSnapshot':
              snapshots.add(
                Map<String, Object?>.from(
                  call.arguments as Map<Object?, Object?>,
                ),
              );
              return true;
          }
          return null;
        });
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    channel.resetForTesting();
  }

  Future<void> emit(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: '', proxyName: ''),
    );
    loadAppLocalizations(const Locale('en'));
  });

  late _MockCoreHandlerInterface core;
  late _TestWidgetHost host;
  late ProviderContainer container;
  var channelCounter = 0;

  Profile buildProfile({
    int id = 1,
    String label = 'MainSub',
    Map<String, String> selectedMap = const {'Proxy': 'HK-01'},
    String? currentGroupName,
  }) {
    return Profile(
      id: id,
      label: label,
      autoUpdateDuration: const Duration(days: 1),
      selectedMap: selectedMap,
      currentGroupName: currentGroupName,
    );
  }

  List<Group> buildGroups() {
    return const [
      Group(
        type: GroupType.Selector,
        name: 'HiddenGroup',
        hidden: true,
        all: [Proxy(name: 'H1', type: 'ss')],
      ),
      Group(
        type: GroupType.Selector,
        name: 'Proxy',
        hidden: false,
        now: 'HK-01',
        all: [
          Proxy(name: 'HK-01', type: 'ss'),
          Proxy(name: 'JP-01', type: 'ss'),
        ],
      ),
      Group(
        type: GroupType.URLTest,
        name: 'Auto',
        hidden: false,
        now: 'SG-01',
        all: [
          Proxy(name: 'SG-01', type: 'ss'),
          Proxy(name: 'US-01', type: 'ss'),
        ],
      ),
      Group(
        type: GroupType.Selector,
        name: 'GLOBAL',
        hidden: false,
        now: 'Proxy',
        all: [
          Proxy(name: 'Proxy', type: 'Selector'),
          Proxy(name: 'DIRECT', type: 'Direct'),
        ],
      ),
    ];
  }

  ProviderContainer createContainer({
    bool safeMode = false,
    List<Profile> profiles = const [],
    int? currentProfileId,
    bool initialized = true,
  }) {
    return ProviderContainer(
      overrides: [
        safeModeProvider.overrideWithValue(safeMode),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        currentProfileIdProvider.overrideWithBuild((_, _) => currentProfileId),
        initProvider.overrideWithBuild((_, _) => initialized),
      ],
    );
  }

  Future<void> pumpWidgetManager(
    WidgetTester tester, {
    required ProviderContainer container,
  }) async {
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          home: WidgetManager(
            channel: host.channel,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    loadAppLocalizations(const Locale('en'));
    core = _MockCoreHandlerInterface();
    when(() => core.changeProxy(any())).thenAnswer(
      (_) async => const ChangeProxyResult(changed: true, message: ''),
    );
    when(() => core.resetConnections()).thenAnswer((_) async => true);
    when(() => core.closeConnections()).thenAnswer((_) async => true);
    host = _TestWidgetHost('com.follow.clash/widget_test_${channelCounter++}')
      ..install();
  });

  tearDown(() {
    host.dispose();
    container.dispose();
  });

  testWidgets('renders its child untouched', (tester) async {
    container = createContainer();
    await pumpWidgetManager(tester, container: container);

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('does nothing in safe mode', (tester) async {
    container = createContainer(
      safeMode: true,
      profiles: [buildProfile()],
      currentProfileId: 1,
    );
    await pumpWidgetManager(tester, container: container);

    expect(host.invokedMethods, isEmpty);
    expect(host.snapshots, isEmpty);

    await host.emit('cycleMode');
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  testWidgets('gates snapshot updates on active widgets and deduplicates', (
    tester,
  ) async {
    host.active = false;
    container = createContainer(
      profiles: [buildProfile()],
      currentProfileId: 1,
    );
    container.read(groupsProvider.notifier).value = buildGroups();
    await pumpWidgetManager(tester, container: container);

    expect(host.snapshots, isEmpty);

    await host.emit('widgetsActiveChanged', true);
    await tester.pumpAndSettle();
    expect(host.snapshots, hasLength(1));

    // Unrelated config fields do not emit duplicate snapshots.
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 7891));
    await tester.pumpAndSettle();
    expect(host.snapshots, hasLength(1));

    await host.emit('widgetsActiveChanged', false);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    await tester.pumpAndSettle();
    expect(host.snapshots, hasLength(1));

    await host.emit('widgetsActiveChanged', true);
    await tester.pumpAndSettle();
    expect(host.snapshots, hasLength(2));
    expect(host.snapshots.last['mode'], 'global');
  });

  testWidgets('builds accurate snapshots across modes, groups, and theme', (
    tester,
  ) async {
    container = createContainer(
      profiles: [buildProfile(label: 'WorkProfile')],
      currentProfileId: 1,
    );
    container.read(groupsProvider.notifier).value = buildGroups();
    await pumpWidgetManager(tester, container: container);

    final ruleSnapshot = host.snapshots.last;
    expect(ruleSnapshot['hasProfile'], isTrue);
    expect(ruleSnapshot['profileName'], 'WorkProfile');
    expect(ruleSnapshot['mode'], 'rule');
    expect(ruleSnapshot['groupName'], 'Proxy');
    expect(ruleSnapshot['nodeName'], 'HK-01');
    expect(ruleSnapshot['canSelectProxy'], isTrue);
    expect(ruleSnapshot['proxyNames'], ['HK-01', 'JP-01']);
    expect(ruleSnapshot['suspended'], isFalse);
    expect(ruleSnapshot['tunEnabled'], isFalse);
    expect(ruleSnapshot['pureBlack'], isFalse);
    expect(ruleSnapshot['primaryColorLight'], isA<int>());
    expect(ruleSnapshot['primaryColorDark'], isA<int>());

    final labels = ruleSnapshot['labels'] as Map<Object?, Object?>;
    expect(labels.keys.toSet(), const {
      'running',
      'notRunning',
      'connecting',
      'stopping',
      'suspended',
      'noProfile',
      'tapToStart',
      'modeRule',
      'modeGlobal',
      'modeDirect',
      'direct',
      'selectNodeTitle',
      'noNodesAvailable',
      'openApp',
    });

    // Switching currentGroupName to a URLTest group disables manual selection.
    container
        .read(profilesProvider.notifier)
        .put(buildProfile(label: 'WorkProfile', currentGroupName: 'Auto'));
    await tester.pumpAndSettle();
    final urlTestSnapshot = host.snapshots.last;
    expect(urlTestSnapshot['groupName'], 'Auto');
    expect(urlTestSnapshot['nodeName'], 'SG-01');
    expect(urlTestSnapshot['canSelectProxy'], isFalse);
    expect(urlTestSnapshot['proxyNames'], isEmpty);

    // Mode.global resolves GLOBAL group.
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.global));
    await tester.pumpAndSettle();
    final globalSnapshot = host.snapshots.last;
    expect(globalSnapshot['mode'], 'global');
    expect(globalSnapshot['groupName'], 'GLOBAL');
    expect(globalSnapshot['canSelectProxy'], isTrue);

    // Mode.direct clears group and disables node selection.
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.direct));
    await tester.pumpAndSettle();
    final directSnapshot = host.snapshots.last;
    expect(directSnapshot['mode'], 'direct');
    expect(directSnapshot['groupName'], '');
    expect(directSnapshot['nodeName'], '');
    expect(directSnapshot['canSelectProxy'], isFalse);
    expect(directSnapshot['proxyNames'], isEmpty);

    // No profile clears hasProfile and profileName.
    container.read(currentProfileIdProvider.notifier).value = null;
    await tester.pumpAndSettle();
    final noProfileSnapshot = host.snapshots.last;
    expect(noProfileSnapshot['hasProfile'], isFalse);
    expect(noProfileSnapshot['profileName'], '');
    expect(noProfileSnapshot['canSelectProxy'], isFalse);
  });

  testWidgets('cycles mode through SetupAction.changeMode', (tester) async {
    container = createContainer(
      profiles: [buildProfile()],
      currentProfileId: 1,
    );
    container.read(groupsProvider.notifier).value = buildGroups();
    await pumpWidgetManager(tester, container: container);

    await host.emit('cycleMode');
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mode, Mode.global);
    expect(container.read(currentProfileProvider)?.currentGroupName, 'GLOBAL');

    await host.emit('cycleMode');
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mode, Mode.direct);

    await host.emit('cycleMode');
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  testWidgets(
    'selects proxy via ProxiesAction and preserves rollback on error',
    (tester) async {
      container = createContainer(
        profiles: [buildProfile()],
        currentProfileId: 1,
      );
      container.read(groupsProvider.notifier).value = buildGroups();
      await pumpWidgetManager(tester, container: container);

      await host.emit('selectProxy', {
        'groupName': 'Proxy',
        'proxyName': 'JP-01',
      });
      await tester.pumpAndSettle();

      expect(container.read(selectedMapProvider)['Proxy'], 'JP-01');
      verify(
        () => core.changeProxy(
          const ChangeProxyParams(groupName: 'Proxy', proxyName: 'JP-01'),
        ),
      ).called(1);

      // Next core change fails: selectedMap must roll back to 'JP-01'.
      when(() => core.changeProxy(any())).thenAnswer(
        (_) async => const ChangeProxyResult(changed: false, message: 'failed'),
      );
      await host.emit('selectProxy', {
        'groupName': 'Proxy',
        'proxyName': 'HK-01',
      });
      await tester.pumpAndSettle();

      expect(container.read(selectedMapProvider)['Proxy'], 'JP-01');

      // Clear the error banner timer before tearing down.
      await tester.pump(const Duration(seconds: 10));
    },
  );

  testWidgets('ignores selectProxy for computed or unknown groups/proxies', (
    tester,
  ) async {
    container = createContainer(
      profiles: [buildProfile()],
      currentProfileId: 1,
    );
    container.read(groupsProvider.notifier).value = buildGroups();
    await pumpWidgetManager(tester, container: container);

    await host.emit('selectProxy', {'groupName': 'Auto', 'proxyName': 'SG-01'});
    await host.emit('selectProxy', {
      'groupName': 'Proxy',
      'proxyName': 'MISSING',
    });
    await host.emit('selectProxy', {
      'groupName': 'MissingGroup',
      'proxyName': 'HK-01',
    });
    await tester.pumpAndSettle();

    verifyNever(() => core.changeProxy(any()));
  });

  testWidgets(
    'defers cold-start pending action until init and groups are ready',
    (tester) async {
      host.pendingAction = {
        'action': 'selectProxy',
        'groupName': 'Proxy',
        'proxyName': 'JP-01',
      };
      container = createContainer(
        profiles: [buildProfile()],
        currentProfileId: 1,
        initialized: false,
      );
      await pumpWidgetManager(tester, container: container);

      // Not initialized and no groups yet: must not call changeProxy yet.
      verifyNever(() => core.changeProxy(any()));

      container.read(initProvider.notifier).value = true;
      await tester.pumpAndSettle();
      verifyNever(() => core.changeProxy(any()));

      container.read(groupsProvider.notifier).value = buildGroups();
      await tester.pumpAndSettle();

      verify(
        () => core.changeProxy(
          const ChangeProxyParams(groupName: 'Proxy', proxyName: 'JP-01'),
        ),
      ).called(1);
      expect(container.read(selectedMapProvider)['Proxy'], 'JP-01');
    },
  );

  testWidgets(
    'executes cold-start pending cycleMode and updates on locale/theme',
    (tester) async {
      host.pendingAction = {'action': 'cycleMode'};
      container = createContainer(
        profiles: [buildProfile()],
        currentProfileId: 1,
        initialized: true,
      );
      container.read(groupsProvider.notifier).value = buildGroups();
      await pumpWidgetManager(tester, container: container);

      expect(container.read(patchClashConfigProvider).mode, Mode.global);

      loadAppLocalizations(const Locale('zh'));
      container.read(loadedLocaleProvider.notifier).value = const Locale('zh');
      container
          .read(themeSettingProvider.notifier)
          .update((state) => state.copyWith(pureBlack: true));
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      await tester.pumpAndSettle();

      final latest = host.snapshots.last;
      expect(latest['pureBlack'], isTrue);
      expect(latest['tunEnabled'], isTrue);
      final labels = latest['labels'] as Map<Object?, Object?>;
      expect(labels['running'], '运行中');
      expect(labels['stopping'], '停止中…');
    },
  );
}
