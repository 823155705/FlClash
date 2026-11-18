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
import 'package:prism_ui/card.dart';
import 'package:prism_ui/segmented_control.dart';
import 'package:prism_ui/shape.dart';
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
        hour: 6,
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
    Finder segmentOf(String app) => find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message.startsWith('$app\n'),
    );
    Finder markerOf(Finder segment) =>
        find.descendant(of: segment, matching: find.byType(ColoredBox)).first;
    Color markerColor(Finder segment) =>
        tester.widget<ColoredBox>(markerOf(segment)).color;
    Color rowColor(String app) {
      final card = find.ancestor(
        of: find.text(app),
        matching: find.byType(Card),
      );
      final swatch = tester.widget<DecoratedBox>(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).shape == AppShape.circle,
          ),
        ),
      );
      return (swatch.decoration as ShapeDecoration).color!;
    }

    final browser = segmentOf('Google Chrome');
    final sync = segmentOf('Cloud Sync');
    final browserColor = markerColor(browser);
    final syncColor = markerColor(sync);
    expect(browserColor, isNot(syncColor));
    expect(browserColor, rowColor('Google Chrome'));
    expect(syncColor, rowColor('Cloud Sync'));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(browser));
    await tester.pumpAndSettle();
    expect(find.text('Google Chrome\n300B · 62.5%'), findsOneWidget);
    expect(markerColor(browser), browserColor);
    final muted = markerColor(sync);
    expect(muted, isNot(syncColor));
    expect(HSLColor.fromColor(muted).saturation, 0);

    await mouse.moveTo(tester.getCenter(sync));
    await tester.pumpAndSettle();
    expect(find.text('Cloud Sync\n180B · 37.5%'), findsOneWidget);
    expect(markerColor(sync), syncColor);
    expect(markerColor(browser), muted);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(markerColor(browser), browserColor);
    expect(markerColor(sync), syncColor);

    await tester.tap(browser);
    await tester.pumpAndSettle();
    final selected = find.textContaining('06:00 · Google Chrome ·');
    expect(selected, findsOneWidget);
    Focus.of(tester.element(markerOf(browser))).requestFocus();
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
    final now = DateTime.now();
    final dayLabel = find.text('${now.month}/${now.day}');
    for (var frame = 0; frame < 20 && !dayLabel.tryEvaluate(); frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(dayLabel, findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('00:00'), findsNothing);
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
