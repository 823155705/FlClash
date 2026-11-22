import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingWidgetListener with WidgetListener {
  final events = <String>[];

  @override
  void onCycleMode() => events.add('cycleMode');

  @override
  void onSelectProxy(String groupName, String proxyName) =>
      events.add('selectProxy:$groupName/$proxyName');

  @override
  void onWidgetsActiveChanged(bool active) => events.add('active:$active');
}

class _ThrowingWidgetListener with WidgetListener {
  var called = false;

  @override
  void onCycleMode() {
    called = true;
    throw StateError('widget listener error');
  }
}

class _MutatingWidgetListener with WidgetListener {
  final WidgetChannel channel;
  final WidgetListener target;

  _MutatingWidgetListener(this.channel, this.target);

  @override
  void onCycleMode() {
    channel.removeListener(target);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = '$packageName/widget';
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    WidgetChannel.instance.resetForTesting();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), null);
    WidgetChannel.instance.resetForTesting();
  });

  Future<void> emitFromPlatform(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
  }

  test('routes every widget action to its listener callback', () async {
    final listener = _RecordingWidgetListener();
    WidgetChannel.instance.addListener(listener);

    await emitFromPlatform('cycleMode');
    await emitFromPlatform('selectProxy', {
      'groupName': 'Proxy',
      'proxyName': 'HK-01',
    });
    await emitFromPlatform('widgetsActiveChanged', true);
    await emitFromPlatform('widgetsActiveChanged', false);

    expect(listener.events, [
      'cycleMode',
      'selectProxy:Proxy/HK-01',
      'active:true',
      'active:false',
    ]);
  });

  test('ignores malformed arguments and unknown methods', () async {
    final listener = _RecordingWidgetListener();
    WidgetChannel.instance.addListener(listener);

    await emitFromPlatform('selectProxy', 'HK-01');
    await emitFromPlatform('selectProxy', {'groupName': '', 'proxyName': 'A'});
    await emitFromPlatform('selectProxy', {'groupName': 'Proxy'});
    await emitFromPlatform('widgetsActiveChanged', 'yes');
    await emitFromPlatform('unknownAction');

    expect(listener.events, isEmpty);
  });

  test(
    'isolates throwing listeners and handles mutation during dispatch',
    () async {
      final channel = WidgetChannel.scoped(const MethodChannel(channelName));
      final throwing = _ThrowingWidgetListener();
      final healthy = _RecordingWidgetListener();
      final mutating = _MutatingWidgetListener(channel, healthy);

      channel.addListener(throwing);
      channel.addListener(mutating);
      channel.addListener(healthy);

      await expectLater(emitFromPlatform('cycleMode'), completes);
      expect(throwing.called, isTrue);
      expect(healthy.events, ['cycleMode']);

      healthy.events.clear();
      await emitFromPlatform('cycleMode');
      expect(healthy.events, isEmpty);
    },
  );

  test('removed listener stops receiving actions', () async {
    final listener = _RecordingWidgetListener();
    expect(WidgetChannel.instance.hasListeners, isFalse);
    WidgetChannel.instance.addListener(listener);
    expect(WidgetChannel.instance.hasListeners, isTrue);

    WidgetChannel.instance.removeListener(listener);
    expect(WidgetChannel.instance.hasListeners, isFalse);

    await emitFromPlatform('cycleMode');
    expect(listener.events, isEmpty);
  });

  test(
    'updateSnapshot forwards map and handles channel errors gracefully',
    () async {
      final calls = <MethodCall>[];
      const methodChannel = MethodChannel(channelName);
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return true;
      });

      await WidgetChannel.instance.updateSnapshot({'hasProfile': true});
      expect(calls.single.method, 'updateSnapshot');
      expect(calls.single.arguments, {'hasProfile': true});

      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        throw PlatformException(code: 'ERR', message: 'boom');
      });
      await expectLater(
        WidgetChannel.instance.updateSnapshot({'hasProfile': false}),
        completes,
      );

      messenger.setMockMethodCallHandler(methodChannel, null);
      await expectLater(
        WidgetChannel.instance.updateSnapshot({'hasProfile': false}),
        completes,
      );
    },
  );

  test(
    'hasActiveWidgets decodes bool and defaults to false on failure',
    () async {
      const methodChannel = MethodChannel(channelName);
      messenger.setMockMethodCallHandler(methodChannel, (_) async => true);
      expect(await WidgetChannel.instance.hasActiveWidgets(), isTrue);

      messenger.setMockMethodCallHandler(methodChannel, (_) async => null);
      expect(await WidgetChannel.instance.hasActiveWidgets(), isFalse);

      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await WidgetChannel.instance.hasActiveWidgets(), isFalse);

      messenger.setMockMethodCallHandler(methodChannel, null);
      expect(await WidgetChannel.instance.hasActiveWidgets(), isFalse);
    },
  );

  test(
    'consumePendingAction decodes valid actions and rejects invalid ones',
    () async {
      const methodChannel = MethodChannel(channelName);

      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => {'action': 'cycleMode'},
      );
      expect(
        await WidgetChannel.instance.consumePendingAction(),
        isA<PendingWidgetCycleMode>(),
      );

      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => {
          'action': 'selectProxy',
          'groupName': 'Proxy',
          'proxyName': 'JP-01',
        },
      );
      expect(
        await WidgetChannel.instance.consumePendingAction(),
        isA<PendingWidgetSelectProxy>()
            .having((e) => e.groupName, 'groupName', 'Proxy')
            .having((e) => e.proxyName, 'proxyName', 'JP-01'),
      );

      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => {
          'action': 'selectProxy',
          'groupName': '',
          'proxyName': 'A',
        },
      );
      expect(await WidgetChannel.instance.consumePendingAction(), isNull);

      messenger.setMockMethodCallHandler(methodChannel, (_) async => null);
      expect(await WidgetChannel.instance.consumePendingAction(), isNull);

      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await WidgetChannel.instance.consumePendingAction(), isNull);
    },
  );
}
