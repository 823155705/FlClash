import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Database database;

  setUp(() {
    database = Database(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  AppTrafficDelta delta({
    required DateTime day,
    required int profileId,
    required String applicationId,
    required int upload,
    required int download,
    String applicationLabel = 'Browser',
    String proxy = 'Proxy A',
    String provider = 'Provider A',
    int? hour,
  }) {
    return AppTrafficDelta(
      day: day,
      hour: hour,
      profileId: profileId,
      profileLabel: 'Plan $profileId',
      applicationId: applicationId,
      applicationLabel: applicationLabel,
      processPath: '/Applications/$applicationLabel.app/',
      proxy: proxy,
      provider: provider,
      upload: upload,
      download: download,
    );
  }

  test('upserts deltas and aggregates by application', () async {
    final today = DateTime(2026, 8, 27);
    await database.appTrafficDao.addAll([
      delta(
        day: today,
        profileId: 1,
        applicationId: 'browser',
        upload: 10,
        download: 20,
      ),
      delta(
        day: today,
        profileId: 1,
        applicationId: 'browser',
        upload: 3,
        download: 4,
      ),
      delta(
        day: today,
        profileId: 1,
        applicationId: 'browser',
        upload: 1,
        download: 2,
        proxy: 'Proxy B',
        provider: 'Provider B',
      ),
    ]);

    final usage = await database.appTrafficDao
        .queryUsage(profileId: 1, since: today)
        .getSingle();

    expect(usage.upload, 14);
    expect(usage.download, 26);
    expect(usage.proxies, containsAll(['Proxy A', 'Proxy B']));
    expect(usage.providers, containsAll(['Provider A', 'Provider B']));
    expect(await database.appTrafficRecords.count.getSingle(), 2);
  });

  test('live queries refresh after traffic is persisted', () async {
    final iterator = StreamIterator(
      database.appTrafficDao.queryUsage().watch(),
    );
    addTearDown(iterator.cancel);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, isEmpty);

    await database.appTrafficDao.addAll([
      delta(
        day: DateTime(2026, 11, 4),
        profileId: 1,
        applicationId: 'browser',
        upload: 12,
        download: 34,
      ),
    ]);

    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 3)),
      isTrue,
    );
    expect(iterator.current.single.total, 46);
  });

  test('keeps hourly and legacy traffic separate and clears both', () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dao = database.appTrafficDao;
    await dao.addAll([
      delta(
        day: day,
        profileId: 1,
        applicationId: 'browser',
        upload: 10,
        download: 1,
        proxy: 'A, B',
      ),
      delta(
        day: day,
        profileId: 1,
        applicationId: 'browser',
        upload: 8,
        download: 2,
        hour: 6,
        proxy: 'A, B',
      ),
      delta(
        day: day,
        profileId: 1,
        applicationId: 'sync',
        upload: 1,
        download: 30,
        hour: 6,
      ),
      delta(
        day: tomorrow,
        profileId: 1,
        applicationId: 'future',
        upload: 80,
        download: 80,
        hour: 6,
      ),
      delta(
        day: day,
        profileId: 2,
        applicationId: 'other',
        upload: 100,
        download: 100,
        hour: 6,
      ),
    ]);

    expect(
      await dao
          .queryTimeline(
            profileId: 1,
            since: day,
            until: tomorrow,
            hourly: true,
          )
          .get(),
      [
        (
          index: -1,
          applicationId: null,
          applicationLabel: '',
          upload: 10,
          download: 1,
        ),
        (
          index: 6,
          applicationId: 'browser',
          applicationLabel: 'Browser',
          upload: 8,
          download: 2,
        ),
        (
          index: 6,
          applicationId: 'sync',
          applicationLabel: 'Browser',
          upload: 1,
          download: 30,
        ),
      ],
    );
    final daily = await dao
        .queryTimeline(profileId: 1, since: day, until: tomorrow)
        .get();
    expect(
      daily.map((slice) => slice.index),
      everyElement(day.millisecondsSinceEpoch),
    );
    expect(
      daily.map((slice) => (slice.applicationId, slice.upload, slice.download)),
      [('browser', 18, 3), ('sync', 1, 30)],
    );
    final allRange = await dao
        .queryTimeline(profileId: 1, until: tomorrow)
        .get();
    expect(
      allRange.map((slice) => slice.index),
      everyElement(day.millisecondsSinceEpoch),
    );
    expect(
      allRange.map(
        (slice) => (slice.applicationId, slice.upload, slice.download),
      ),
      [('browser', 18, 3), ('sync', 1, 30)],
    );
    final byUpload = await dao
        .queryUsage(
          profileId: 1,
          since: day,
          until: tomorrow,
          sort: AppTrafficSort.upload,
        )
        .get();
    expect(byUpload.map((row) => row.applicationId), ['browser', 'sync']);
    expect(byUpload.first.proxies, ['A, B']);
    final byDownload = await dao
        .queryUsage(
          profileId: 1,
          since: day,
          until: tomorrow,
          sort: AppTrafficSort.download,
        )
        .get();
    expect(byDownload.map((row) => row.applicationId), ['sync', 'browser']);
    await dao.clear(profileId: 1);
    expect(await dao.queryUsage(profileId: 1).get(), isEmpty);
    expect(await database.appTrafficHours.count.getSingle(), 1);
  });

  test(
    'keeps the top applications across periods and adds the rest to Other',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final dao = database.appTrafficDao;
      await dao.addAll([
        for (var i = 1; i <= 5; i++)
          for (final hour in [6, 18])
            delta(
              day: day,
              profileId: 1,
              applicationId: 'app$i',
              upload: i * hour,
              download: 0,
              hour: hour,
            ),
      ]);
      final slices = await dao
          .queryTimeline(profileId: 1, since: day, hourly: true)
          .get();
      expect(slices, hasLength(8));
      expect(
        slices.take(4).map((slice) => (slice.applicationId, slice.upload)),
        [(null, 18), ('app3', 18), ('app4', 24), ('app5', 30)],
      );
      expect(slices.fold(0, (sum, slice) => sum + slice.upload), 360);
    },
  );

  test(
    'filters by subscription and date and clears only selected scope',
    () async {
      final today = DateTime(2026, 8, 27);
      await database.appTrafficDao.addAll([
        delta(
          day: today.subtract(const Duration(days: 10)),
          profileId: 1,
          applicationId: 'old',
          upload: 100,
          download: 100,
        ),
        delta(
          day: today,
          profileId: 1,
          applicationId: 'current',
          upload: 10,
          download: 20,
        ),
        delta(
          day: today,
          profileId: 2,
          applicationId: 'other-plan',
          upload: 30,
          download: 40,
        ),
      ]);

      final recent = await database.appTrafficDao
          .queryUsage(
            profileId: 1,
            since: today.subtract(const Duration(days: 6)),
          )
          .get();
      expect(recent.map((usage) => usage.applicationId), ['current']);

      expect(await database.appTrafficDao.clear(profileId: 1), 2);
      final remaining = await database.appTrafficDao.queryUsage().get();
      expect(remaining.single.applicationId, 'other-plan');
    },
  );

  test(
    'queryTimeline ranks top 3 by the requested sort metric and excludes zeros',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dao = database.appTrafficDao;
      await dao.addAll([
        delta(
          day: today,
          profileId: 1,
          applicationId: 'downloader',
          applicationLabel: 'Downloader',
          upload: 0,
          download: 1000,
          hour: 9,
        ),
        delta(
          day: today,
          profileId: 1,
          applicationId: 'up1',
          applicationLabel: 'Uploader 1',
          upload: 300,
          download: 10,
          hour: 9,
        ),
        delta(
          day: today,
          profileId: 1,
          applicationId: 'up2',
          applicationLabel: 'Uploader 2',
          upload: 200,
          download: 10,
          hour: 9,
        ),
        delta(
          day: today,
          profileId: 1,
          applicationId: 'up3',
          applicationLabel: 'Uploader 3',
          upload: 100,
          download: 10,
          hour: 9,
        ),
        delta(
          day: today,
          profileId: 1,
          applicationId: 'up4',
          applicationLabel: 'Uploader 4',
          upload: 50,
          download: 10,
          hour: 9,
        ),
      ]);

      final byUpload = await dao
          .queryTimeline(
            profileId: 1,
            since: today,
            hourly: true,
            sort: AppTrafficSort.upload,
          )
          .get();
      expect(
        byUpload.map(
          (slice) => (slice.applicationId, slice.upload, slice.download),
        ),
        [
          (null, 50, 1010),
          ('up1', 300, 10),
          ('up2', 200, 10),
          ('up3', 100, 10),
        ],
      );

      final byDownload = await dao
          .queryTimeline(
            profileId: 1,
            since: today,
            sort: AppTrafficSort.download,
          )
          .get();
      expect(byDownload.map((slice) => slice.applicationId).toSet(), {
        'downloader',
        'up1',
        'up2',
        null,
      });
    },
  );

  test(
    'clamps asymmetric legacy differences and ensures profile-day index exists',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final dayMs = day.millisecondsSinceEpoch;
      await database.customStatement(
        'INSERT INTO app_traffic_records '
        '(day, profile_id, profile_label, application_id, application_label, '
        'process_path, proxy, provider, upload, download, updated_at) '
        "VALUES (?, 1, 'P1', 'app', 'App', '', 'Proxy', '', 10, 0, 0)",
        [dayMs],
      );
      await database.customStatement(
        'INSERT INTO app_traffic_hours_by_app '
        '(day, profile_id, hour, application_id, application_label, upload, download) '
        "VALUES (?, 1, 8, 'app', 'App', 4, 5)",
        [dayMs],
      );

      final slices = await database.appTrafficDao
          .queryTimeline(profileId: 1, since: day, hourly: true)
          .get();
      expect(slices.first, (
        index: -1,
        applicationId: null,
        applicationLabel: '',
        upload: 6,
        download: 0,
      ));

      final indexes = await database
          .customSelect("PRAGMA index_list('app_traffic_records')")
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        contains('idx_app_traffic_profile_day'),
      );

      final clearedProfiles = <int?>[];
      void listener(int? profileId) => clearedProfiles.add(profileId);
      database.appTrafficDao.addClearListener(listener);
      await database.appTrafficDao.clear(profileId: 1);
      database.appTrafficDao.removeClearListener(listener);
      await database.appTrafficDao.clear();
      expect(clearedProfiles, [1]);
    },
  );
}
