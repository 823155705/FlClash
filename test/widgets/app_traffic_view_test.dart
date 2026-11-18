import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
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
import 'package:prism_ui/prism_ui.dart' show ColorScheme;
import 'package:prism_ui/segmented_control.dart';
import 'package:prism_ui/shape.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  late Database database;
  late ProviderContainer container;

  Future<void> seedDefault() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await database.appTrafficDao.addAll([
      AppTrafficDelta(
        day: today,
        hour: 6,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'alpha-dl',
        applicationLabel: 'Video Stream',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 10,
        download: 400,
      ),
      AppTrafficDelta(
        day: today,
        hour: 6,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'beta-dl',
        applicationLabel: 'File Sync',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 20,
        download: 300,
      ),
      AppTrafficDelta(
        day: today,
        hour: 6,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'gamma-dl',
        applicationLabel: 'Web Browser',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 30,
        download: 200,
      ),
      AppTrafficDelta(
        day: today,
        hour: 6,
        profileId: 1,
        profileLabel: 'Test plan',
        applicationId: 'zeta-up',
        applicationLabel: 'Cloud Backup',
        processPath: '',
        proxy: 'Proxy A',
        provider: 'Provider A',
        upload: 150,
        download: 10,
      ),
    ]);
  }

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
    await seedDefault();
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpView(
    WidgetTester tester, {
    Size size = const Size(1000, 900),
  }) async {
    tester.view.physicalSize = size;
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
  }

  Finder chartPlot() => find.byWidgetPredicate(
    (widget) => widget is MouseRegion && widget.onHover != null,
  );

  Color? rowSwatchColor(WidgetTester tester, String app) {
    final card = find.ancestor(of: find.text(app), matching: find.byType(Card));
    final swatch = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is ShapeDecoration &&
                  (widget.decoration as ShapeDecoration).shape ==
                      AppShape.circle,
            ),
          )
          .first,
    );
    return (swatch.decoration as ShapeDecoration).color;
  }

  testWidgets(
    'uses active card colors, metric-synced Top-3, hover/pin/unpin, and range reset',
    (tester) async {
      await pumpView(tester);

      expect(find.text('App Traffic'), findsOneWidget);
      expect(find.text('Test plan').hitTestable(), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);

      final videoContext = tester.element(find.text('Video Stream'));
      final onSurface = ColorScheme.of(videoContext).onSurface;
      expect(
        tester.widget<Text>(find.text('Video Stream')).style?.color,
        onSurface,
      );
      expect(
        tester.widget<Text>(find.text(1120.traffic.show).first).style?.color,
        onSurface,
      );

      final primary = ColorScheme.of(videoContext).primary;
      expect(rowSwatchColor(tester, 'Video Stream'), primary);

      double rowY(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(rowY('Video Stream'), lessThan(rowY('Cloud Backup')));

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      expect(rowY('Cloud Backup'), lessThan(rowY('Video Stream')));
      expect(rowSwatchColor(tester, 'Cloud Backup'), primary);
      expect(find.textContaining('Peak 06:00 · 210B'), findsOneWidget);

      final plotRect = tester.getRect(chartPlot());
      final bar6Bottom = Offset(
        plotRect.left + (6.5 / 24) * plotRect.width,
        plotRect.bottom - 14,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bar6Bottom);
      await tester.pumpAndSettle();
      expect(find.text('06:00 · Cloud Backup'), findsOneWidget);
      expect(
        find.textContaining('06:00 · Cloud Backup · 150B'),
        findsOneWidget,
      );

      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('06:00 · Cloud Backup'), findsNothing);
      expect(find.textContaining('06:00 · Cloud Backup · 150B'), findsNothing);

      await tester.tapAt(bar6Bottom);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('06:00 · Cloud Backup · 150B'),
        findsOneWidget,
      );

      final emptySlot = Offset(
        plotRect.left + (0.5 / 24) * plotRect.width,
        plotRect.top + 14,
      );
      await tester.tapAt(emptySlot);
      await tester.pumpAndSettle();
      expect(find.textContaining('06:00 · Cloud Backup · 150B'), findsNothing);

      await tester.tapAt(bar6Bottom);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('06:00 · Cloud Backup · 150B'),
        findsOneWidget,
      );

      final range = find.byType(SegmentedControl<AppTrafficRange>);
      await tester.tap(
        find.descendant(of: range, matching: find.text('Last 7 days')),
      );
      final now = DateTime.now();
      final dayLabel = find.text('${now.month}/${now.day}');
      for (var frame = 0; frame < 20 && !dayLabel.tryEvaluate(); frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(dayLabel, findsOneWidget);
      final overviewFade = find
          .ancestor(
            of: find.textContaining('Upload ').first,
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(
        tester.widget<FadeTransition>(overviewFade).opacity.value,
        lessThan(1.0),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(overviewFade).opacity.value, 1.0);
      expect(find.textContaining('06:00 · Cloud Backup · 150B'), findsNothing);
      expect(
        find.textContaining(
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} · Cloud Backup',
        ),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: range, matching: find.text('All time')),
      );
      await tester.pumpAndSettle();
      expect(find.text('${now.month}/${now.day}'), findsOneWidget);

      final todayLabel = DateTime(now.year, now.month, now.day).show;
      Focus.of(tester.element(chartPlot())).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('$todayLabel · Cloud Backup · 150B'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('$todayLabel · Cloud Backup · 150B'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'supports adaptive All-time buckets, mobile layout, and clearing traffic',
    (tester) async {
      final now = DateTime.now();
      await database.appTrafficDao.addAll([
        AppTrafficDelta(
          day: DateTime(now.year, now.month - 3, 1),
          hour: 10,
          profileId: 1,
          profileLabel: 'Test plan',
          applicationId: 'alpha-dl',
          applicationLabel: 'Video Stream',
          processPath: '',
          proxy: 'Proxy A',
          provider: 'Provider A',
          upload: 50,
          download: 500,
        ),
      ]);
      await pumpView(tester, size: const Size(390, 844));

      final range = find.byType(SegmentedControl<AppTrafficRange>);
      await tester.tap(
        find.descendant(of: range, matching: find.text('All time')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('${now.year}-${now.month.toString().padLeft(2, '0')}'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Clear traffic statistics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('No subscription proxy traffic in this range'),
        findsOneWidget,
      );
      expect(find.byType(SegmentedControl<AppTrafficRange>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
