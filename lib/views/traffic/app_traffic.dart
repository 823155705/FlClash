import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

part 'traffic_chart.dart';

enum AppTrafficRange { today, sevenDays, all }

typedef _TrafficTimeline = ({
  int profileId,
  DateTime day,
  AppTrafficRange range,
  List<AppTrafficBucket> buckets,
});

class AppTrafficView extends ConsumerStatefulWidget {
  final AppTrafficDao? trafficDao;

  const AppTrafficView({super.key, this.trafficDao});

  @override
  ConsumerState<AppTrafficView> createState() => _AppTrafficViewState();
}

class _AppTrafficViewState extends ConsumerState<AppTrafficView> {
  static const _allProfiles = -1;
  late int _profileId;
  AppTrafficRange _range = AppTrafficRange.today;
  AppTrafficSort _sort = AppTrafficSort.total;
  late DateTime _today;
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;
  late Stream<List<AppTrafficUsage>> _usage;
  late Stream<_TrafficTimeline> _timeline;

  AppTrafficDao get _dao => widget.trafficDao ?? database.appTrafficDao;
  int? get _selectedProfile => _profileId == _allProfiles ? null : _profileId;
  DateTime get _tomorrow => DateTime(_today.year, _today.month, _today.day + 1);
  DateTime? get _since => switch (_range) {
    AppTrafficRange.today => _today,
    AppTrafficRange.sevenDays => DateTime(
      _today.year,
      _today.month,
      _today.day - 6,
    ),
    AppTrafficRange.all => null,
  };

  @override
  void initState() {
    super.initState();
    _profileId = ref.read(currentProfileIdProvider) ?? _allProfiles;
    _today = _localDay(DateTime.now());
    _subscribeScope();
    _lifecycle = AppLifecycleListener(onResume: _refreshDay);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  static DateTime _localDay(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  void _scheduleMidnight() {
    _midnight?.cancel();
    _midnight = Timer(_tomorrow.difference(DateTime.now()), _refreshDay);
  }

  void _refreshDay() {
    final today = _localDay(DateTime.now());
    if (today != _today) {
      setState(() {
        _today = today;
        _subscribeScope();
      });
    }
    _scheduleMidnight();
  }

  void _subscribeScope() {
    _subscribeUsage();
    final profileId = _profileId;
    final day = _today;
    final range = _range;
    _timeline = _dao
        .queryTimeline(
          profileId: _selectedProfile,
          since: _since,
          until: _tomorrow,
          hourly: range == AppTrafficRange.today,
        )
        .watch()
        .map(
          (buckets) =>
              (profileId: profileId, day: day, range: range, buckets: buckets),
        );
  }

  void _subscribeUsage() {
    _usage = _dao
        .queryUsage(
          profileId: _selectedProfile,
          since: _since,
          until: _tomorrow,
          sort: _sort,
        )
        .watch();
  }

  Future<void> _clear() async {
    final l10n = context.appLocalizations;
    final profile = _selectedProfile;
    final confirmed = await dialogs.showMessage(
      title: l10n.clearTrafficStatistics,
      message: TextSpan(text: l10n.clearTrafficStatisticsConfirm),
    );
    if (confirmed == true && mounted) {
      await _dao.clear(profileId: profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      title: l10n.appTraffic,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.broom,
          tooltip: l10n.clearTrafficStatistics,
          onPressed: _clear,
        ),
      ],
      body: StreamBuilder<_TrafficTimeline>(
        stream: _timeline,
        builder: (context, trend) {
          final timeline = trend.data;
          final swatches = _trafficSwatches(
            context,
            timeline?.buckets ?? const [],
          );
          return StreamBuilder<List<AppTrafficUsage>>(
            stream: _usage,
            builder: (context, snapshot) {
              final usages = snapshot.data ?? const <AppTrafficUsage>[];
              var maximum = 0;
              for (final usage in usages) {
                final amount = _sort.amountOf(usage);
                if (amount > maximum) maximum = amount;
              }
              final header = Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    ListItem<int>.options(
                      title: Text(l10n.profiles),
                      leading: const GlyphIcon(AppGlyphs.profiles),
                      options: [
                        _allProfiles,
                        ...profiles.map((profile) => profile.id),
                      ],
                      value: _profileId,
                      textBuilder: (id) =>
                          profiles
                              .where((profile) => profile.id == id)
                              .firstOrNull
                              ?.label ??
                          l10n.allSubscriptions,
                      onChanged: (id) => setState(() {
                        _profileId = id;
                        _subscribeScope();
                      }),
                    ),
                    SegmentedControl<AppTrafficRange>(
                      segments: [
                        (AppTrafficRange.today, l10n.today),
                        (AppTrafficRange.sevenDays, l10n.lastSevenDays),
                        (AppTrafficRange.all, l10n.allTime),
                      ],
                      value: _range,
                      onChanged: (range) => setState(() {
                        _range = range;
                        _subscribeScope();
                      }),
                    ),
                    if (timeline != null)
                      FadeThroughBox(
                        alignment: Alignment.topCenter,
                        child: _TrafficOverview(
                          key: ValueKey((
                            timeline.profileId,
                            timeline.day,
                            timeline.range,
                          )),
                          data: timeline,
                          swatches: swatches,
                        ),
                      ),
                    Text(
                      l10n.appTrafficScope,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Semantics(
                      label: l10n.sort,
                      child: SegmentedControl<AppTrafficSort>(
                        segments: [
                          (AppTrafficSort.total, l10n.totalTraffic),
                          (AppTrafficSort.upload, l10n.upload),
                          (AppTrafficSort.download, l10n.download),
                        ],
                        value: _sort,
                        onChanged: (sort) => setState(() {
                          _sort = sort;
                          _subscribeUsage();
                        }),
                      ),
                    ),
                  ],
                ),
              );
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                    ),
                    sliver: SliverToBoxAdapter(child: header),
                  ),
                  if (snapshot.hasError)
                    SliverToBoxAdapter(child: Text(snapshot.error.toString()))
                  else if (!snapshot.hasData &&
                      snapshot.connectionState == ConnectionState.waiting)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: LinearProgressIndicator(),
                      ),
                    )
                  else if (usages.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 240,
                        child: NullStatus(
                          label: l10n.noAppTraffic,
                          illustration: NullStatusIllustration.apps,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverPrismList(
                        itemCount: usages.length,
                        estimatedItemExtent: 96,
                        gap: 8,
                        itemBuilder: (_, index) => _AppTrafficItem(
                          usage: usages[index],
                          sort: _sort,
                          maxTraffic: maximum,
                          color:
                              swatches[usages[index].applicationId] ??
                              swatches[null]!,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: context.bottomInset + 32),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

extension on AppTrafficSort {
  int amountOf(AppTrafficUsage usage) => switch (this) {
    AppTrafficSort.total => usage.total,
    AppTrafficSort.upload => usage.upload,
    AppTrafficSort.download => usage.download,
  };
}

class _TrafficOverview extends StatelessWidget {
  final _TrafficTimeline data;
  final Map<String?, Color> swatches;

  const _TrafficOverview({
    super.key,
    required this.data,
    required this.swatches,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    final timeline = data.buckets;
    var upload = 0;
    var download = 0;
    for (final bucket in timeline) {
      upload += bucket.upload;
      download += bucket.download;
    }
    final legacy = timeline.firstOrNull?.index == -1 ? timeline.first : null;
    final slices = legacy == null ? timeline : timeline.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Card(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Text(
                l10n.totalTraffic,
                style: AppTextStyle.subheadline.of(context),
              ),
              Text(
                (upload + download).traffic.show,
                style: AppTextStyle.largeTitle.of(context),
              ),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text(
                    '${l10n.upload} ${upload.traffic.show}',
                    style: AppTextStyle.footnote.of(context),
                  ),
                  Text(
                    '${l10n.download} ${download.traffic.show}',
                    style: AppTextStyle.footnote.of(context),
                  ),
                ],
              ),
              if (legacy != null)
                Text(
                  '${l10n.appTrafficUnbucketed} · ${(legacy.upload + legacy.download).traffic.show}',
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
            ],
          ),
        ),
        if (slices.isNotEmpty)
          Card(
            padding: const EdgeInsets.all(16),
            child: _TrafficChart(
              bars: _trafficBars(data.range, data.day, slices),
              swatches: swatches,
            ),
          ),
      ],
    );
  }
}

class _AppTrafficItem extends StatelessWidget {
  final AppTrafficUsage usage;
  final AppTrafficSort sort;
  final int maxTraffic;
  final Color color;

  const _AppTrafficItem({
    required this.usage,
    required this.sort,
    required this.maxTraffic,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final label = usage.applicationLabel.isEmpty
        ? l10n.unknownApplication
        : usage.applicationLabel;
    final amount = sort.amountOf(usage);
    final routes = {...usage.providers, ...usage.proxies}.take(4).join(' · ');
    final theme = Theme.of(context);
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 8,
            children: [
              _TrafficSwatch(color: color),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context),
                ),
              ),
              Text(
                amount.traffic.show,
                style: AppTextStyle.headline.of(context),
              ),
            ],
          ),
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(primary: color),
            ),
            child: LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              value: maxTraffic == 0 ? 0 : amount / maxTraffic,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${l10n.upload} ${usage.upload.traffic.show}',
                style: AppTextStyle.footnote.of(context),
              ),
              Text(
                '${l10n.download} ${usage.download.traffic.show}',
                style: AppTextStyle.footnote.of(context),
              ),
            ],
          ),
          if (routes.isNotEmpty)
            Text(
              routes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
