part of 'app_traffic.dart';

typedef _TrafficPeriod = ({int index, String label, String title});

class _TrafficBar {
  final _TrafficPeriod period;
  final Map<String?, AppTrafficBucket> apps = {};
  int upload = 0;
  int download = 0;

  _TrafficBar(this.period);

  int get total => upload + download;

  void add(AppTrafficBucket slice) {
    upload += slice.upload;
    download += slice.download;
    apps.update(
      slice.applicationId,
      (previous) => _sumSlices(previous, slice),
      ifAbsent: () => slice,
    );
  }
}

AppTrafficBucket _sumSlices(AppTrafficBucket a, AppTrafficBucket b) => (
  index: a.index,
  applicationId: a.applicationId,
  applicationLabel: a.applicationLabel,
  upload: a.upload + b.upload,
  download: a.download + b.download,
);

List<_TrafficBar> _trafficBars(
  AppTrafficRange range,
  DateTime today,
  List<AppTrafficBucket> slices,
) {
  final List<_TrafficBar> bars;
  final int Function(int) slot;
  switch (range) {
    case AppTrafficRange.today:
      bars = List.generate(24, (hour) {
        final label = '${getDateStringLast2(hour)}:00';
        return _TrafficBar((index: hour, label: label, title: label));
      });
      slot = (hour) => hour;
    case AppTrafficRange.sevenDays:
      final first = DateTime.utc(today.year, today.month, today.day - 6);
      bars = List.generate(7, (index) {
        final day = DateTime(today.year, today.month, today.day - 6 + index);
        return _TrafficBar((
          index: index,
          label: '${day.month}/${day.day}',
          title: day.show,
        ));
      });
      slot = (epoch) {
        final day = DateTime.fromMillisecondsSinceEpoch(epoch);
        return DateTime.utc(
          day.year,
          day.month,
          day.day,
        ).difference(first).inDays;
      };
    case AppTrafficRange.all:
      int monthOf(int value) => (value ~/ 100) * 12 + value % 100 - 1;
      String labelOf(int month) =>
          '${month ~/ 12}-${getDateStringLast2(month % 12 + 1)}';
      final first = monthOf(slices.first.index);
      final last = today.year * 12 + today.month - 1;
      final span = last - first + 1;
      final step = span <= 12
          ? 1
          : span <= 36
          ? 3
          : 12 * (span / 144).ceil();
      bars = List.generate((span / step).ceil(), (index) {
        final start = first + index * step;
        final end = math.min(start + step - 1, last);
        final label = labelOf(start);
        return _TrafficBar((
          index: start,
          label: step >= 12 ? '${start ~/ 12}' : label,
          title: start == end ? label : '$label – ${labelOf(end)}',
        ));
      });
      slot = (month) => (monthOf(month) - first) ~/ step;
  }
  for (final slice in slices) {
    bars[slot(slice.index)].add(slice);
  }
  return bars;
}

class _TrafficChart extends StatefulWidget {
  final List<_TrafficBar> bars;

  const _TrafficChart({required this.bars});

  @override
  State<_TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<_TrafficChart> {
  static const _height = 132.0;
  int? _selection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    final bars = widget.bars;
    final totals = <String?, AppTrafficBucket>{};
    var peak = 0;
    var overall = 0;
    for (final bar in bars) {
      final total = bar.total;
      peak = math.max(peak, total);
      overall += total;
      for (final slice in bar.apps.values) {
        totals.update(
          slice.applicationId,
          (previous) => _sumSlices(previous, slice),
          ifAbsent: () => slice,
        );
      }
    }
    final palette = [colors.primary, colors.tertiary, colors.success];
    final ids = totals.keys.nonNulls.toList()..sort();
    final swatches = {
      for (final (index, id) in ids.indexed) id: palette[index],
      if (totals.containsKey(null))
        null: colors.onSurfaceVariant.withValues(alpha: 0.55),
    };
    final axisStyle = AppTextStyle.caption2
        .of(context)
        .copyWith(color: colors.onSurfaceVariant);
    final percentage = NumberFormat.decimalPercentPattern(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    final active = bars
        .where((bar) => bar.period.index == _selection)
        .firstOrNull;

    String label(AppTrafficBucket slice) => slice.applicationId == null
        ? l10n.other
        : slice.applicationLabel.isEmpty
        ? l10n.unknownApplication
        : slice.applicationLabel;
    String share(AppTrafficBucket slice, int total) {
      final amount = slice.upload + slice.download;
      return '${label(slice)} · ${amount.traffic.show} (${percentage.format(amount / total)})';
    }

    String directions(_TrafficBar bar) =>
        '${l10n.upload} ${bar.upload.traffic.show} · ${l10n.download} ${bar.download.traffic.show}';
    final displayedApps = active?.apps ?? totals;
    final displayedTotal = active?.total ?? overall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labelLength = bars.fold(
                    0,
                    (n, bar) => math.max(n, bar.period.label.length),
                  );
                  final labelWidth = MediaQuery.textScalerOf(
                    context,
                  ).scale(labelLength * 7.0 + 8);
                  final labelCount = math.max(
                    1,
                    constraints.maxWidth ~/ labelWidth,
                  );
                  final stride = (bars.length / labelCount).ceil();
                  final barWidth = math.min(
                    44.0,
                    constraints.maxWidth * 0.68 / bars.length,
                  );
                  return Column(
                    spacing: 6,
                    children: [
                      SizedBox(
                        height: _height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Divider(height: 1),
                                Divider(height: 1),
                                Divider(height: 1),
                              ],
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final bar in bars)
                                  Expanded(
                                    child: bar.total == 0
                                        ? const SizedBox.shrink()
                                        : Tooltip(
                                            message: [
                                              bar.period.title,
                                              '${l10n.totalTraffic} ${bar.total.traffic.show}',
                                              directions(bar),
                                              for (final id in swatches.keys)
                                                if (bar.apps[id]
                                                    case final slice?)
                                                  share(slice, bar.total),
                                            ].join('\n'),
                                            preferBelow: false,
                                            child: PressSurface(
                                              key: ValueKey(bar.period.index),
                                              fill: identical(active, bar)
                                                  ? colors.primary.withValues(
                                                      alpha: 0.10,
                                                    )
                                                  : Colors.transparent,
                                              shape: AppShape.xs,
                                              selected: identical(active, bar),
                                              childFills: true,
                                              onPressed: () => setState(() {
                                                _selection =
                                                    identical(active, bar)
                                                    ? null
                                                    : bar.period.index;
                                              }),
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: SizedBox(
                                                  width: barWidth,
                                                  height:
                                                      _height *
                                                      bar.total /
                                                      peak,
                                                  child: ClipRSuperellipse(
                                                    borderRadius: AppRadius.top(
                                                      AppCorner.xs,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        for (final MapEntry(
                                                              :key,
                                                              :value,
                                                            )
                                                            in swatches.entries)
                                                          if (bar.apps[key]
                                                              case final slice?)
                                                            Expanded(
                                                              flex:
                                                                  slice.upload +
                                                                  slice
                                                                      .download,
                                                              child: ColoredBox(
                                                                color: value,
                                                              ),
                                                            ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          for (
                            var index = 0;
                            index < bars.length;
                            index += stride
                          )
                            Expanded(
                              flex: math.min(stride, bars.length - index),
                              child: Text(
                                bars[index].period.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: axisStyle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              height: _height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(peak.traffic.show, style: axisStyle),
                  if (peak > 1)
                    Text((peak ~/ 2).traffic.show, style: axisStyle),
                  Text(0.traffic.show, style: axisStyle),
                ],
              ),
            ),
          ],
        ),
        if (active != null) ...[
          Text(
            '${active.period.title} · ${active.total.traffic.show}',
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
          Text(directions(active), style: AppTextStyle.footnote.of(context)),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final id in swatches.keys)
              if (displayedApps[id] case final slice?)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: swatches[id],
                        shape: AppShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 8),
                    ),
                    Flexible(
                      child: Text(
                        share(slice, displayedTotal),
                        style: AppTextStyle.footnote.of(context),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}
