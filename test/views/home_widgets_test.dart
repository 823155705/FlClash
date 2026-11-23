import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/home_widgets.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

class _FakeWidgetPinHost {
  _FakeWidgetPinHost(String channelName)
    : methodChannel = MethodChannel(channelName),
      channel = WidgetChannel.scoped(MethodChannel(channelName));

  final MethodChannel methodChannel;
  final WidgetChannel channel;

  bool supported = true;
  bool pinResult = true;
  bool throwOnPin = false;
  final pinnedKinds = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isRequestPinWidgetSupported':
              return supported;
            case 'requestPinWidget':
              if (throwOnPin) {
                throw PlatformException(code: 'PIN_ERR', message: 'boom');
              }
              final args = call.arguments as Map<Object?, Object?>;
              pinnedKinds.add(args['kind'] as String);
              return pinResult;
          }
          return null;
        });
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    channel.resetForTesting();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeWidgetPinHost host;
  var channelCounter = 0;

  setUp(() {
    host = _FakeWidgetPinHost(
      'com.follow.clash/home_widgets_test_${channelCounter++}',
    )..install();
  });

  tearDown(() {
    host.dispose();
    container.dispose();
  });

  Future<void> pumpToolsView(
    WidgetTester tester, {
    required bool isAndroid,
    bool safeMode = false,
  }) async {
    container = ProviderContainer(
      overrides: [safeModeProvider.overrideWithValue(safeMode)],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(400, 900);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: ToolsView(isAndroid: isAndroid, widgetChannel: host.channel),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hides home widgets entry on non-Android', (tester) async {
    await pumpToolsView(tester, isAndroid: false);
    final l = currentAppLocalizations;
    expect(find.text(l.homeWidgets), findsNothing);
  });

  testWidgets('hides home widgets entry in safe mode on Android', (
    tester,
  ) async {
    await pumpToolsView(tester, isAndroid: true, safeMode: true);
    final l = currentAppLocalizations;
    expect(find.text(l.homeWidgets), findsNothing);
  });

  testWidgets('opens home widgets sheet and requests pin for every size', (
    tester,
  ) async {
    await pumpToolsView(tester, isAndroid: true);
    final l = currentAppLocalizations;

    expect(find.text(l.homeWidgets), findsOneWidget);
    await tester.tap(find.text(l.homeWidgets));
    await tester.pumpAndSettle();

    expect(find.byType(HomeWidgetsSheet), findsOneWidget);
    expect(find.text(l.homeWidget2x2Title), findsOneWidget);
    expect(find.text(l.homeWidget2x2Desc), findsOneWidget);
    expect(find.text(l.homeWidget4x2Title), findsOneWidget);
    expect(find.text(l.homeWidget4x2Desc), findsOneWidget);
    expect(find.text(l.homeWidget4x1Title), findsOneWidget);
    expect(find.text(l.homeWidget4x1Desc), findsOneWidget);
    expect(find.text(l.homeWidgetsDesc), findsOneWidget);

    await tester.tap(find.text(l.homeWidget2x2Title));
    await tester.pumpAndSettle();
    expect(host.pinnedKinds, ['2x2']);
    expect(find.text(l.homeWidgetPinRequested), findsOneWidget);

    await tester.tap(find.text(l.homeWidget4x2Title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.homeWidget4x1Title));
    await tester.pumpAndSettle();
    expect(host.pinnedKinds, ['2x2', '4x2', '4x1']);

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('shows manual add guidance when launcher rejects pinning', (
    tester,
  ) async {
    host.supported = false;
    host.pinResult = false;
    await pumpToolsView(tester, isAndroid: true);
    final l = currentAppLocalizations;

    await tester.tap(find.text(l.homeWidgets));
    await tester.pumpAndSettle();
    expect(find.text(l.homeWidgetPinUnsupported), findsOneWidget);

    await tester.tap(find.text(l.homeWidget4x2Title));
    await tester.pumpAndSettle();
    expect(host.pinnedKinds, ['4x2']);
    expect(find.text(l.homeWidgetPinUnsupported), findsNWidgets(2));

    host.throwOnPin = true;
    await tester.tap(find.text(l.homeWidget4x1Title));
    await tester.pumpAndSettle();
    expect(find.text(l.homeWidgetPinUnsupported), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 10));
  });
}
