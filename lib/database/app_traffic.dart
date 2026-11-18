part of 'database.dart';

@DataClassName('AppTrafficRecord')
@TableIndex(name: 'idx_app_traffic_profile_day', columns: {#profileId, #day})
class AppTrafficRecords extends Table {
  @override
  String get tableName => 'app_traffic_records';

  IntColumn get day => integer()();

  IntColumn get profileId => integer()();

  TextColumn get profileLabel => text()();

  TextColumn get applicationId => text()();

  TextColumn get applicationLabel => text()();

  TextColumn get processPath => text()();

  TextColumn get proxy => text()();

  TextColumn get provider => text()();

  IntColumn get upload => integer().withDefault(const Constant(0))();

  IntColumn get download => integer().withDefault(const Constant(0))();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {
    day,
    profileId,
    applicationId,
    proxy,
    provider,
  };
}

class AppTrafficHours extends Table {
  @override
  String get tableName => 'app_traffic_hours_by_app';

  IntColumn get day => integer()();
  IntColumn get profileId => integer()();
  IntColumn get hour => integer()();
  TextColumn get applicationId => text()();
  TextColumn get applicationLabel => text()();
  IntColumn get upload => integer()();
  IntColumn get download => integer()();

  @override
  Set<Column> get primaryKey => {day, profileId, hour, applicationId};
}

@DriftAccessor(tables: [AppTrafficRecords, AppTrafficHours])
class AppTrafficDao extends DatabaseAccessor<Database>
    with _$AppTrafficDaoMixin {
  AppTrafficDao(super.attachedDatabase);

  int? _lastPrunedDay;

  Future<void> addAll(Iterable<AppTrafficDelta> deltas) async {
    final daily = <(int, int, String, String, String), AppTrafficDelta>{};
    final hourly = <(int, int, int, String), AppTrafficDelta>{};
    for (final delta in deltas) {
      if (delta.total <= 0) continue;
      final day = delta.day.millisecondsSinceEpoch;
      final key = (
        day,
        delta.profileId,
        delta.applicationId,
        delta.proxy,
        delta.provider,
      );
      daily.update(key, (old) => old.plus(delta), ifAbsent: () => delta);
      if (delta.hour case final hour?) {
        hourly.update(
          (day, delta.profileId, hour, delta.applicationId),
          (old) => old.plus(delta),
          ifAbsent: () => delta,
        );
      }
    }
    if (daily.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final retention = DateTime(
      now.year,
      now.month,
      now.day - 1,
    ).millisecondsSinceEpoch;
    final prune = _lastPrunedDay != retention;
    await batch((batch) {
      for (final delta in daily.values) {
        batch.customStatement(
          'INSERT INTO app_traffic_records '
          '(day, profile_id, profile_label, application_id, '
          'application_label, process_path, proxy, provider, upload, '
          'download, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(day, profile_id, application_id, proxy, provider) '
          'DO UPDATE SET profile_label = excluded.profile_label, '
          'application_label = excluded.application_label, '
          'process_path = excluded.process_path, '
          'upload = app_traffic_records.upload + excluded.upload, '
          'download = app_traffic_records.download + excluded.download, '
          'updated_at = excluded.updated_at',
          [
            delta.day.millisecondsSinceEpoch,
            delta.profileId,
            delta.profileLabel,
            delta.applicationId,
            delta.applicationLabel,
            delta.processPath,
            delta.proxy,
            delta.provider,
            delta.upload,
            delta.download,
            now.millisecondsSinceEpoch,
          ],
        );
      }
      final hoursTable = appTrafficHours.actualTableName;
      for (final MapEntry(key: (day, profile, hour, app), :value)
          in hourly.entries) {
        batch.customStatement(
          'INSERT INTO $hoursTable (day, profile_id, hour, application_id, '
          'application_label, upload, download) VALUES (?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(day, profile_id, hour, application_id) DO UPDATE SET '
          'application_label = excluded.application_label, '
          'upload = $hoursTable.upload + excluded.upload, '
          'download = $hoursTable.download + excluded.download',
          [
            day,
            profile,
            hour,
            app,
            value.applicationLabel,
            value.upload,
            value.download,
          ],
        );
      }
      if (prune) {
        batch.customStatement('DELETE FROM $hoursTable WHERE day < ?', [
          retention,
        ]);
      }
    });
    _lastPrunedDay = retention;
    attachedDatabase.notifyUpdates({
      TableUpdate.onTable(appTrafficRecords),
      if (hourly.isNotEmpty || prune) TableUpdate.onTable(appTrafficHours),
    });
  }

  (String, List<Variable<Object>>) _scope(
    int? profileId,
    DateTime? since,
    DateTime? until,
  ) {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    if (profileId != null) {
      conditions.add('profile_id = ?');
      variables.add(Variable.withInt(profileId));
    }
    if (since != null) {
      conditions.add('day >= ?');
      variables.add(Variable.withInt(since.millisecondsSinceEpoch));
    }
    if (until != null) {
      conditions.add('day < ?');
      variables.add(Variable.withInt(until.millisecondsSinceEpoch));
    }
    return (
      conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}',
      variables,
    );
  }

  Selectable<AppTrafficUsage> queryUsage({
    int? profileId,
    DateTime? since,
    DateTime? until,
    AppTrafficSort sort = AppTrafficSort.total,
  }) {
    final (where, variables) = _scope(profileId, since, until);
    final order = switch (sort) {
      AppTrafficSort.total => 'SUM(upload + download)',
      AppTrafficSort.upload => 'SUM(upload)',
      AppTrafficSort.download => 'SUM(download)',
    };
    return customSelect(
      'SELECT application_id, MAX(application_label) AS application_label, '
      'MAX(process_path) AS process_path, SUM(upload) AS upload, '
      'SUM(download) AS download, json_group_array(DISTINCT proxy) AS proxies, '
      'json_group_array(DISTINCT provider) AS providers '
      'FROM app_traffic_records $where GROUP BY application_id '
      'ORDER BY $order DESC, application_label ASC, application_id ASC',
      variables: variables,
      readsFrom: {appTrafficRecords},
    ).map((row) {
      List<String> values(String column) {
        return (jsonDecode(row.read<String>(column)) as List)
            .cast<String>()
            .where((value) => value.isNotEmpty)
            .toList();
      }

      return AppTrafficUsage(
        applicationId: row.read<String>('application_id'),
        applicationLabel: row.read<String>('application_label'),
        processPath: row.read<String>('process_path'),
        upload: row.read<int>('upload'),
        download: row.read<int>('download'),
        proxies: values('proxies'),
        providers: values('providers'),
      );
    });
  }

  Selectable<AppTrafficBucket> queryTimeline({
    int? profileId,
    DateTime? since,
    DateTime? until,
    bool hourly = false,
  }) {
    final (where, variables) = _scope(profileId, since, until);
    final bucket = hourly
        ? 'hour'
        : since == null
        ? "CAST(strftime('%Y%m', day / 1000, 'unixepoch', 'localtime') AS INTEGER)"
        : 'day';
    final TableInfo table = hourly ? appTrafficHours : appTrafficRecords;
    const emptyLabel = "''";
    final legacy = hourly
        ? 'UNION ALL SELECT -1, NULL, $emptyLabel, '
              'COALESCE(SUM(upload), 0) - (SELECT COALESCE(SUM(upload), 0) FROM usage), '
              'COALESCE(SUM(download), 0) - (SELECT COALESCE(SUM(download), 0) FROM usage) '
              'FROM app_traffic_records $where '
              'HAVING SUM(upload + download) > (SELECT COALESCE(SUM(upload + download), 0) FROM usage) '
        : '';
    return customSelect(
      'WITH usage AS (SELECT $bucket AS bucket, application_id, '
      'MAX(application_label) AS label, SUM(upload) AS upload, SUM(download) AS download '
      'FROM ${table.actualTableName} $where GROUP BY 1, 2), '
      'top_apps AS (SELECT application_id, MAX(label) AS label FROM usage '
      'GROUP BY 1 ORDER BY SUM(upload + download) DESC, application_id LIMIT 3) '
      'SELECT bucket, top_apps.application_id AS application_id, '
      'COALESCE(top_apps.label, $emptyLabel) AS label, SUM(upload) AS upload, SUM(download) AS download '
      'FROM usage LEFT JOIN top_apps USING (application_id) '
      'GROUP BY bucket, top_apps.application_id $legacy ORDER BY 1, 2',
      variables: hourly ? [...variables, ...variables] : variables,
      readsFrom: {table, if (hourly) appTrafficRecords},
    ).map(
      (row) => (
        index: row.read<int>('bucket'),
        applicationId: row.readNullable<String>('application_id'),
        applicationLabel: row.read<String>('label'),
        upload: row.read<int>('upload'),
        download: row.read<int>('download'),
      ),
    );
  }

  Future<int> clear({int? profileId}) => transaction(() async {
    final stmt = appTrafficRecords.delete();
    final hours = appTrafficHours.delete();
    if (profileId != null) {
      stmt.where((row) => row.profileId.equals(profileId));
      hours.where((row) => row.profileId.equals(profileId));
    }
    await hours.go();
    return stmt.go();
  });
}
