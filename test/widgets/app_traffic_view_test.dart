import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/traffic/app_traffic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/segmented_control.dart';
import 'package:prism_ui/tooltip.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  late Database database;
  late ProviderContainer container;

  setUp(() async {
    database = Database(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        profilesProvider.overrideWith(
          () => TestProfiles([
            const Profile(
              id: 1,
              label: 'Test plan',
              autoUpdateDuration: Duration.zero,
            ),
          ]),
        ),
      ],
    );
    final now = DateTime.now();
    await database.appTrafficDao.addAll([
      AppTrafficDelta(
        day: DateTime(now.year, now.month, now.day),
        hour: 6,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'browser',
        applicationLabel: 'Google Chrome',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 100,
        download: 200,
      ),
      AppTrafficDelta(
        day: DateTime(now.year, now.month, now.day),
        hour: 18,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'sync',
        applicationLabel: 'Cloud Sync',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 150,
        download: 30,
      ),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  testWidgets('renders preserved usage with the current app components', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: AppTrafficView(trafficDao: database.appTrafficDao),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.text('Test plan').hitTestable(), findsOneWidget);
    expect(find.text('App Traffic'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    Finder barAt(String time) => find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message.startsWith(time),
    );
    Finder markerOf(Finder bar) =>
        find.descendant(of: bar, matching: find.byType(ColoredBox)).first;
    final hour = barAt('06:00');
    final marker = markerOf(hour);
    expect(
      tester.widget<ColoredBox>(marker).color,
      isNot(tester.widget<ColoredBox>(markerOf(barAt('18:00'))).color),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(hour));
    await tester.pumpAndSettle();
    expect(find.textContaining('06:00\n'), findsOneWidget);
    expect(find.textContaining('100.0%'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();

    await tester.tap(hour);
    await tester.pumpAndSettle();
    final selected = find.textContaining('06:00 ·');
    expect(selected, findsOneWidget);
    Focus.of(tester.element(marker)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, findsNothing);
    final sort = find.byType(SegmentedControl<AppTrafficSort>);
    final range = find.byType(SegmentedControl<AppTrafficRange>);
    double position(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(position('Google Chrome'), lessThan(position('Cloud Sync')));

    await tester.tap(find.descendant(of: sort, matching: find.text('Upload')));
    await tester.pumpAndSettle();
    expect(position('Cloud Sync'), lessThan(position('Google Chrome')));
    await tester.tap(
      find.descendant(of: sort, matching: find.text('Download')),
    );
    await tester.pumpAndSettle();
    expect(position('Google Chrome'), lessThan(position('Cloud Sync')));

    await tester.tap(
      find.descendant(of: range, matching: find.text('Last 7 days')),
    );
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.month}/${now.day}'), findsOneWidget);
    await tester.tap(
      find.descendant(of: range, matching: find.text('All time')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('${now.year}-${now.month.toString().padLeft(2, '0')}'),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedControl<AppTrafficSort>), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
