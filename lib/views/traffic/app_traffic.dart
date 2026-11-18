import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:prism_ui/hct/hct.dart';

part 'traffic_chart.dart';

enum AppTrafficRange { today, sevenDays, all }

typedef _TrafficScope = ({
  int profileId,
  DateTime day,
  AppTrafficRange range,
  AppTrafficSort sort,
});

typedef _TrafficSnapshot = ({
  _TrafficScope scope,
  List<AppTrafficBucket> buckets,
  List<AppTrafficUsage> usages,
});

class AppTrafficView extends ConsumerStatefulWidget {
  final AppTrafficDao? trafficDao;

  const AppTrafficView({super.key, this.trafficDao});

  @override
  ConsumerState<AppTrafficView> createState() => _AppTrafficViewState();
}

class _AppTrafficViewState extends ConsumerState<AppTrafficView>
    with SingleTickerProviderStateMixin<AppTrafficView> {
  static const _allProfiles = -1;
  static const _wideBreakpoint = 880.0;
  static const _maxContentWidth = 1120.0;
  static const _maxSingleColumnWidth = 720.0;

  late int _profileId;
  AppTrafficRange _range = AppTrafficRange.today;
  AppTrafficSort _sort = AppTrafficSort.total;
  late DateTime _today;
  late final AppLifecycleListener _lifecycle;
  late final _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1.0,
  );
  late final _fadeOpacity = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeOutCubic,
  );
  Timer? _midnight;
  StreamSubscription<List<AppTrafficBucket>>? _timelineSub;
  StreamSubscription<List<AppTrafficUsage>>? _usageSub;
  _TrafficSnapshot? _snapshot;
  Object? _error;

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
    _lifecycle = AppLifecycleListener(
      onResume: _refreshDay,
      onShow: _refreshDay,
    );
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _timelineSub?.cancel();
    _usageSub?.cancel();
    _fadeOpacity.dispose();
    _fadeController.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  static DateTime _localDay(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  void _scheduleMidnight() {
    _midnight?.cancel();
    final delay = _tomorrow.difference(DateTime.now());
    _midnight = Timer(
      delay < const Duration(seconds: 1) ? const Duration(seconds: 1) : delay,
      _refreshDay,
    );
  }

  void _refreshDay() {
    final today = _localDay(DateTime.now());
    if (today != _today && mounted) {
      setState(() {
        _today = today;
        _subscribeScope();
      });
    }
    _scheduleMidnight();
  }

  void _subscribeScope() {
    _timelineSub?.cancel();
    _usageSub?.cancel();
    final scope = (
      profileId: _profileId,
      day: _today,
      range: _range,
      sort: _sort,
    );
    List<AppTrafficBucket>? buckets;
    List<AppTrafficUsage>? usages;

    void publish() {
      if (!mounted || buckets == null || usages == null) {
        return;
      }
      if (_localDay(DateTime.now()) != _today) {
        _refreshDay();
        return;
      }
      final scopeChanged = _snapshot != null && _snapshot!.scope != scope;
      setState(() {
        _error = null;
        _snapshot = (scope: scope, buckets: buckets!, usages: usages!);
      });
      if (scopeChanged) {
        if (context.disableAnimations) {
          _fadeController.value = 1.0;
        } else {
          _fadeController.forward(from: 0.0);
        }
      }
    }

    void fail(Object error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    }

    _timelineSub = _dao
        .queryTimeline(
          profileId: _selectedProfile,
          since: _since,
          until: _tomorrow,
          hourly: _range == AppTrafficRange.today,
          sort: _sort,
        )
        .watch()
        .listen((value) {
          buckets = value;
          publish();
        }, onError: fail);
    _usageSub = _dao
        .queryUsage(
          profileId: _selectedProfile,
          since: _since,
          until: _tomorrow,
          sort: _sort,
        )
        .watch()
        .listen((value) {
          usages = value;
          publish();
        }, onError: fail);
  }

  Future<void> _clear() async {
    final l10n = context.appLocalizations;
    final profile = _selectedProfile;
    final confirmed = await dialogs.showMessage(
      title: l10n.clearTrafficStatistics,
      message: TextSpan(text: l10n.clearTrafficStatisticsConfirm),
      destructive: true,
    );
    if (confirmed == true && mounted) {
      await _dao.clear(profileId: profile);
    }
  }

  void _selectProfile(int id) {
    if (id == _profileId) {
      return;
    }
    setState(() {
      _profileId = id;
      _subscribeScope();
    });
  }

  void _selectRange(AppTrafficRange range) {
    if (range == _range) {
      return;
    }
    setState(() {
      _range = range;
      _subscribeScope();
    });
  }

  void _selectSort(AppTrafficSort sort) {
    if (sort == _sort) {
      return;
    }
    setState(() {
      _sort = sort;
      _subscribeScope();
    });
  }

  String _profileLabel(List<Profile> profiles, int id) {
    if (id == _allProfiles) {
      return context.appLocalizations.allSubscriptions;
    }
    return profiles.where((profile) => profile.id == id).firstOrNull?.label ??
        context.appLocalizations.allSubscriptions;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final profiles = ref.watch(profilesProvider);
    final profileOptions = [_allProfiles, ...profiles.map((p) => p.id)];
    final selectedLabel = _profileLabel(profiles, _profileId);
    return Scaffold(
      title: l10n.appTraffic,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.broom,
          tooltip: l10n.clearTrafficStatistics,
          onPressed: _clear,
        ),
      ],
      body: Builder(
        builder: (context) {
          final snapshot = _snapshot;
          final error = _error;
          if (error != null && snapshot == null) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                context.contentTopPadding,
                16,
                context.bottomInset + 24,
              ),
              child: Text(error.toString()),
            );
          }
          if (snapshot == null) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                context.contentTopPadding + 16,
                24,
                context.bottomInset + 24,
              ),
              child: const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(),
              ),
            );
          }
          final swatches = _trafficSwatches(
            context,
            snapshot.buckets,
            snapshot.scope.sort,
          );
          final usages = snapshot.usages;
          final sort = snapshot.scope.sort;
          var maximum = 0;
          var overall = 0;
          for (final usage in usages) {
            final amount = sort.amount(
              upload: usage.upload,
              download: usage.download,
            );
            if (amount > maximum) {
              maximum = amount;
            }
            overall += amount;
          }
          final rangeControl = SegmentedControl<AppTrafficRange>(
            segments: [
              (AppTrafficRange.today, l10n.today),
              (AppTrafficRange.sevenDays, l10n.lastSevenDays),
              (AppTrafficRange.all, l10n.allTime),
            ],
            value: _range,
            onChanged: _selectRange,
          );
          final subscriptionMenu = _SubscriptionMenu(
            label: selectedLabel,
            options: profileOptions,
            selectedId: _profileId,
            labelOf: (id) => _profileLabel(profiles, id),
            onSelected: _selectProfile,
          );
          final overview = FadeTransition(
            opacity: _fadeOpacity,
            child: _TrafficOverview(
              scope: snapshot.scope,
              buckets: snapshot.buckets,
              swatches: swatches,
            ),
          );
          final sortHeader = _SortHeader(sort: _sort, onChanged: _selectSort);
          final topPadding = context.contentTopPadding;
          final bottomInset = context.bottomInset;
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideBreakpoint) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 20,
                        children: [
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(
                              padding: EdgeInsets.only(
                                top: topPadding,
                                bottom: bottomInset + 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 12,
                                children: [
                                  subscriptionMenu,
                                  rangeControl,
                                  overview,
                                  ListFooter(text: l10n.appTrafficScope),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 6,
                            child: CustomScrollView(
                              slivers: [
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    top: topPadding,
                                    bottom: 12,
                                  ),
                                  sliver: SliverToBoxAdapter(child: sortHeader),
                                ),
                                SliverFadeTransition(
                                  opacity: _fadeOpacity,
                                  sliver: _buildUsageSliver(
                                    l10n: l10n,
                                    usages: usages,
                                    sort: sort,
                                    maximum: maximum,
                                    overall: overall,
                                    swatches: swatches,
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: SizedBox(height: bottomInset + 24),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final compactControls = constraints.maxWidth >= 600
                  ? Row(
                      spacing: 12,
                      children: [
                        Expanded(child: rangeControl),
                        subscriptionMenu,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [subscriptionMenu, rangeControl],
                    );
              final horizontalInset =
                  constraints.maxWidth > _maxSingleColumnWidth
                  ? (constraints.maxWidth - _maxSingleColumnWidth) / 2 + 16
                  : 16.0;
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      topPadding,
                      horizontalInset,
                      12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [compactControls, overview, sortHeader],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                    sliver: SliverFadeTransition(
                      opacity: _fadeOpacity,
                      sliver: _buildUsageSliver(
                        l10n: l10n,
                        usages: usages,
                        sort: sort,
                        maximum: maximum,
                        overall: overall,
                        swatches: swatches,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      8,
                      horizontalInset,
                      bottomInset + 24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: ListFooter(text: l10n.appTrafficScope),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildUsageSliver({
    required AppLocalizations l10n,
    required List<AppTrafficUsage> usages,
    required AppTrafficSort sort,
    required int maximum,
    required int overall,
    required Map<String?, Color> swatches,
  }) {
    if (usages.isEmpty) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: NullStatus(
            label: l10n.noAppTraffic,
            illustration: NullStatusIllustration.apps,
          ),
        ),
      );
    }
    return SliverPrismList(
      itemCount: usages.length,
      estimatedItemExtent: 96,
      gap: 8,
      itemBuilder: (_, index) {
        final usage = usages[index];
        final swatch = swatches[usage.applicationId];
        return _AppTrafficItem(
          usage: usage,
          sort: sort,
          maxTraffic: maximum,
          overall: overall,
          swatchColor: swatch,
        );
      },
    );
  }
}

class _SubscriptionMenu extends StatelessWidget {
  final String label;
  final List<int> options;
  final int selectedId;
  final String Function(int id) labelOf;
  final ValueChanged<int> onSelected;

  const _SubscriptionMenu({
    required this.label,
    required this.options,
    required this.selectedId,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return PopupAnchor(
      placement: PopupPlacement.overAnchorEnd,
      targetBuilder: (open) => Card(
        shape: AppShape.full,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onPressed: open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            GlyphIcon(
              AppGlyphs.profiles,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(color: colors.onSurface),
              ),
            ),
            GlyphIcon(
              AppGlyphs.picker,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
      popupBuilder: (_) => PopupMenu(
        items: [
          for (final id in options)
            PopupMenuItem(
              label: labelOf(id),
              checked: id == selectedId,
              onPressed: () => onSelected(id),
            ),
        ],
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  final AppTrafficSort sort;
  final ValueChanged<AppTrafficSort> onChanged;

  const _SortHeader({required this.sort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    final items = [
      (AppTrafficSort.total, l10n.totalTraffic),
      (AppTrafficSort.upload, l10n.upload),
      (AppTrafficSort.download, l10n.download),
    ];
    return Semantics(
      label: l10n.sort,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (option, label) in items)
            Card(
              shape: AppShape.full,
              isSelected: option == sort,
              fillsSelection: true,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onPressed: () => onChanged(option),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context, emphasized: option == sort)
                    .copyWith(
                      color: option == sort
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrafficOverview extends StatelessWidget {
  final _TrafficScope scope;
  final List<AppTrafficBucket> buckets;
  final Map<String?, Color> swatches;

  const _TrafficOverview({
    required this.scope,
    required this.buckets,
    required this.swatches,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    var upload = 0;
    var download = 0;
    for (final bucket in buckets) {
      upload += bucket.upload;
      download += bucket.download;
    }
    final legacy = buckets.firstOrNull?.index == -1 ? buckets.first : null;
    final slices = legacy == null ? buckets : buckets.skip(1).toList();
    final sort = scope.sort;
    final heroLabel = switch (sort) {
      AppTrafficSort.total => l10n.totalTraffic,
      AppTrafficSort.upload => l10n.upload,
      AppTrafficSort.download => l10n.download,
    };
    final heroAmount = sort.amount(upload: upload, download: download);
    final legacyAmount = legacy == null
        ? 0
        : sort.amount(upload: legacy.upload, download: legacy.download);
    final bars = slices.isEmpty
        ? const <_TrafficBar>[]
        : _trafficBars(scope.range, scope.day, slices);
    final hasChartData = bars.any(
      (bar) => sort.amount(upload: bar.upload, download: bar.download) > 0,
    );
    return Card(
      inert: true,
      shape: AppShape.xl,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Text(
                heroLabel,
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: colors.onSurfaceVariant),
              ),
              Text(
                heroAmount.traffic.show,
                style: AppTextStyle.title1
                    .of(context, emphasized: true)
                    .toTabular
                    .copyWith(color: colors.onSurface),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _MetricChip(
                    glyph: AppGlyphs.arrowUp,
                    glyphColor: sort == AppTrafficSort.upload
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    label: '${l10n.upload} ${upload.traffic.show}',
                    emphasized: sort == AppTrafficSort.upload,
                  ),
                  _MetricChip(
                    glyph: AppGlyphs.arrowDown,
                    glyphColor: sort == AppTrafficSort.download
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    label: '${l10n.download} ${download.traffic.show}',
                    emphasized: sort == AppTrafficSort.download,
                  ),
                  if (sort != AppTrafficSort.total)
                    Text(
                      '${l10n.totalTraffic} ${(upload + download).traffic.show}',
                      style: AppTextStyle.footnote
                          .of(context)
                          .toTabular
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
              if (legacyAmount > 0)
                Text(
                  '${l10n.appTrafficUnbucketed} · ${legacyAmount.traffic.show}',
                  style: AppTextStyle.caption1
                      .of(context)
                      .toTabular
                      .copyWith(color: colors.onSurfaceVariant),
                ),
            ],
          ),
          if (hasChartData) ...[
            const Divider(height: 1),
            _TrafficChart(
              scopeKey: (scope.profileId, scope.day, scope.range, scope.sort),
              sort: sort,
              bars: bars,
              swatches: swatches,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final Glyph glyph;
  final Color glyphColor;
  final String label;
  final bool emphasized;

  const _MetricChip({
    required this.glyph,
    required this.glyphColor,
    required this.label,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        GlyphIcon(glyph, size: 14, color: glyphColor),
        Text(
          label,
          style: AppTextStyle.footnote
              .of(context, emphasized: emphasized)
              .toTabular
              .copyWith(
                color: emphasized ? colors.onSurface : colors.onSurfaceVariant,
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
  final int overall;
  final Color? swatchColor;

  const _AppTrafficItem({
    required this.usage,
    required this.sort,
    required this.maxTraffic,
    required this.overall,
    required this.swatchColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    final label = usage.applicationLabel.isEmpty
        ? l10n.unknownApplication
        : usage.applicationLabel;
    final amount = sort.amount(upload: usage.upload, download: usage.download);
    final routes = {...usage.providers, ...usage.proxies}.take(4).join(' · ');
    final percentage = NumberFormat.decimalPercentPattern(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    final barColor =
        swatchColor ??
        Color.alphaBlend(
          colors.primary.withValues(alpha: 0.45),
          SurfaceLevel.card.colorOf(colors),
        );
    final shareText = overall > 0 ? percentage.format(amount / overall) : null;
    return Card(
      inert: true,
      shape: AppShape.xl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              _TrafficSwatch(color: swatchColor ?? colors.outlineVariant),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline
                      .of(context)
                      .copyWith(color: colors.onSurface),
                ),
              ),
              if (shareText != null)
                Text(
                  shareText,
                  style: AppTextStyle.footnote
                      .of(context)
                      .toTabular
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              Text(
                amount.traffic.show,
                style: AppTextStyle.headline
                    .of(context)
                    .toTabular
                    .copyWith(color: colors.onSurface),
              ),
            ],
          ),
          _UsageProgressBar(
            ratio: maxTraffic == 0 ? 0 : amount / maxTraffic,
            color: barColor,
          ),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _MetricChip(
                  glyph: AppGlyphs.arrowUp,
                  glyphColor: sort == AppTrafficSort.upload
                      ? colors.primary
                      : colors.onSurfaceVariant,
                  label: '${l10n.upload} ${usage.upload.traffic.show}',
                  emphasized: sort == AppTrafficSort.upload,
                ),
                _MetricChip(
                  glyph: AppGlyphs.arrowDown,
                  glyphColor: sort == AppTrafficSort.download
                      ? colors.primary
                      : colors.onSurfaceVariant,
                  label: '${l10n.download} ${usage.download.traffic.show}',
                  emphasized: sort == AppTrafficSort.download,
                ),
              ],
            ),
          ),
          if (routes.isNotEmpty)
            Text(
              routes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _UsageProgressBar extends StatelessWidget {
  final double ratio;
  final Color color;

  const _UsageProgressBar({required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    final clamped = ratio.clamp(0.0, 1.0);
    return SizedBox(
      height: 6,
      width: double.infinity,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.colorScheme.surfaceContainerHighest,
          shape: AppShape.full,
        ),
        child: clamped == 0
            ? null
            : ClipRSuperellipse(
                borderRadius: AppRadius.full,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: clamped,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: color,
                        shape: AppShape.full,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
