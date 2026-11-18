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

Map<String?, Color> _trafficSwatches(
  BuildContext context,
  List<AppTrafficBucket> timeline,
) {
  final colors = context.colorScheme;
  final seed = HSLColor.fromColor(colors.primary);
  final hue = seed.saturation < 0.1 ? 216.0 : seed.hue;
  final lightness = colors.brightness == Brightness.dark ? 0.68 : 0.45;
  final ids = {for (final slice in timeline) ?slice.applicationId}.toList()
    ..sort();
  const hueOffsets = [0.0, -60.0, 65.0];
  return {
    for (final (index, id) in ids.indexed)
      id: HSLColor.fromAHSL(
        1,
        (hue + hueOffsets[index]) % 360,
        0.6,
        lightness,
      ).toColor(),
    null: HSLColor.fromColor(colors.outline).withSaturation(0).toColor(),
  };
}

class _TrafficSwatch extends StatelessWidget {
  final Color color;

  const _TrafficSwatch({required this.color});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: color, shape: AppShape.circle),
    child: const SizedBox.square(dimension: 8),
  );
}

typedef _TrafficSegment = (int, String?);

class _TrafficChart extends StatefulWidget {
  final List<_TrafficBar> bars;
  final Map<String?, Color> swatches;

  const _TrafficChart({required this.bars, required this.swatches});

  @override
  State<_TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<_TrafficChart> {
  static const _height = 144.0;
  _TrafficSegment? _hover;
  _TrafficSegment? _selection;

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
    final swatches = widget.swatches;
    final muted = HSLColor.fromColor(
      colors.outlineVariant,
    ).withSaturation(0).toColor();
    final axisStyle = AppTextStyle.caption2
        .of(context)
        .copyWith(color: colors.onSurfaceVariant);
    final percentage = NumberFormat.decimalPercentPattern(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );
    _TrafficBar? barFor(_TrafficSegment? segment) =>
        bars.where((bar) => bar.period.index == segment?.$1).firstOrNull;
    final selectedBar = barFor(_selection);
    final selectedSlice = selectedBar?.apps[_selection?.$2];
    final hover = _hover;
    final active = barFor(hover)?.apps[hover?.$2] != null
        ? hover
        : selectedSlice == null
        ? null
        : _selection;

    String label(AppTrafficBucket slice) => slice.applicationId == null
        ? l10n.other
        : slice.applicationLabel.isEmpty
        ? l10n.unknownApplication
        : slice.applicationLabel;
    String amountAndShare(AppTrafficBucket slice, int total) {
      final amount = slice.upload + slice.download;
      return '${amount.traffic.show} · ${percentage.format(amount / total)}';
    }

    Widget segment(_TrafficBar bar, AppTrafficBucket slice, Color color) {
      final id = (bar.period.index, slice.applicationId);
      return Expanded(
        key: ValueKey(id),
        flex: slice.upload + slice.download,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = id),
          onExit: (_) {
            if (_hover == id) setState(() => _hover = null);
          },
          child: Tooltip(
            message: '${label(slice)}\n${amountAndShare(slice, bar.total)}',
            preferBelow: false,
            child: PressSurface(
              fill: Colors.transparent,
              shape: AppShape.xs,
              look: PressLook.none,
              showsHover: false,
              selected: _selection == id,
              childFills: true,
              onPressed: () => setState(() {
                _selection = _selection == id ? null : id;
              }),
              child: ColoredBox(
                color: active == null || active == id ? color : muted,
              ),
            ),
          ),
        ),
      );
    }

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
                                        : Align(
                                            alignment: Alignment.bottomCenter,
                                            child: SizedBox(
                                              width: barWidth,
                                              height:
                                                  _height * bar.total / peak,
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
                                                        segment(
                                                          bar,
                                                          slice,
                                                          value,
                                                        ),
                                                  ],
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
        if (selectedBar != null && selectedSlice != null)
          Text(
            '${selectedBar.period.title} · ${label(selectedSlice)} · ${amountAndShare(selectedSlice, selectedBar.total)}',
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final MapEntry(:key, :value) in swatches.entries)
              if (totals[key] case final slice?)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    _TrafficSwatch(color: value),
                    Flexible(
                      child: Text(
                        '${label(slice)} · ${amountAndShare(slice, overall)}',
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
