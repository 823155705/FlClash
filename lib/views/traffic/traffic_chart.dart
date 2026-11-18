part of 'app_traffic.dart';

typedef _TrafficPeriod = ({int index, String label, String title});

class _TrafficBar {
  final _TrafficPeriod period;
  final Map<String?, AppTrafficBucket> apps = {};
  int upload = 0;
  int download = 0;

  _TrafficBar(this.period);

  int amount(AppTrafficSort sort) =>
      sort.amount(upload: upload, download: download);

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
  applicationLabel: a.applicationLabel.isNotEmpty
      ? a.applicationLabel
      : b.applicationLabel,
  upload: a.upload + b.upload,
  download: a.download + b.download,
);

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int _utcDayDiff(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

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
      slot = (hour) => hour.clamp(0, bars.length - 1);
    case AppTrafficRange.sevenDays:
      final first = DateTime(today.year, today.month, today.day - 6);
      bars = List.generate(7, (index) {
        final day = DateTime(first.year, first.month, first.day + index);
        return _TrafficBar((
          index: index,
          label: '${day.month}/${day.day}',
          title: day.show,
        ));
      });
      slot = (epoch) {
        final day = _dateOnly(DateTime.fromMillisecondsSinceEpoch(epoch));
        return _utcDayDiff(first, day).clamp(0, bars.length - 1);
      };
    case AppTrafficRange.all:
      if (slices.isEmpty) {
        return const [];
      }
      var minDay = _dateOnly(
        DateTime.fromMillisecondsSinceEpoch(slices.first.index),
      );
      var maxDay = minDay;
      for (final slice in slices.skip(1)) {
        final day = _dateOnly(DateTime.fromMillisecondsSinceEpoch(slice.index));
        if (day.isBefore(minDay)) minDay = day;
        if (day.isAfter(maxDay)) maxDay = day;
      }
      final endDay = maxDay.isAfter(today) ? maxDay : today;
      final daySpan = _utcDayDiff(minDay, endDay) + 1;
      if (daySpan <= 31) {
        final count = math.max(7, daySpan);
        final first = DateTime(
          endDay.year,
          endDay.month,
          endDay.day - count + 1,
        );
        bars = List.generate(count, (index) {
          final day = DateTime(first.year, first.month, first.day + index);
          return _TrafficBar((
            index: index,
            label: '${day.month}/${day.day}',
            title: day.show,
          ));
        });
        slot = (epoch) {
          final day = _dateOnly(DateTime.fromMillisecondsSinceEpoch(epoch));
          return _utcDayDiff(first, day).clamp(0, bars.length - 1);
        };
      } else {
        int monthIndex(DateTime d) => d.year * 12 + d.month - 1;
        String monthLabel(int month) =>
            '${month ~/ 12}-${getDateStringLast2(month % 12 + 1)}';
        final firstMonth = monthIndex(minDay);
        final lastMonth = monthIndex(endDay);
        final monthSpan = lastMonth - firstMonth + 1;
        if (monthSpan <= 18) {
          bars = List.generate(monthSpan, (index) {
            final month = firstMonth + index;
            final label = monthLabel(month);
            return _TrafficBar((index: month, label: label, title: label));
          });
          slot = (epoch) {
            final day = DateTime.fromMillisecondsSinceEpoch(epoch);
            return (monthIndex(day) - firstMonth).clamp(0, bars.length - 1);
          };
        } else if (monthSpan <= 48) {
          final firstQuarter = firstMonth ~/ 3;
          final lastQuarter = lastMonth ~/ 3;
          bars = List.generate(lastQuarter - firstQuarter + 1, (index) {
            final quarter = firstQuarter + index;
            final label = '${quarter ~/ 4} Q${quarter % 4 + 1}';
            return _TrafficBar((index: quarter, label: label, title: label));
          });
          slot = (epoch) {
            final day = DateTime.fromMillisecondsSinceEpoch(epoch);
            return (monthIndex(day) ~/ 3 - firstQuarter).clamp(
              0,
              bars.length - 1,
            );
          };
        } else {
          final firstYear = minDay.year;
          final lastYear = endDay.year;
          bars = List.generate(lastYear - firstYear + 1, (index) {
            final year = firstYear + index;
            final label = '$year';
            return _TrafficBar((index: year, label: label, title: label));
          });
          slot = (epoch) {
            final day = DateTime.fromMillisecondsSinceEpoch(epoch);
            return (day.year - firstYear).clamp(0, bars.length - 1);
          };
        }
      }
  }
  for (final slice in slices) {
    bars[slot(slice.index)].add(slice);
  }
  return bars;
}

Map<String?, Color> _trafficSwatches(
  BuildContext context,
  List<AppTrafficBucket> timeline,
  AppTrafficSort sort,
) {
  final colors = context.colorScheme;
  final primaryHct = Hct.fromInt(colors.primary.toARGB32());
  final dark = colors.brightness == Brightness.dark;
  final totals = <String, ({int amount, String label})>{};
  for (final slice in timeline) {
    if (slice.index == -1) continue;
    final id = slice.applicationId;
    if (id == null) continue;
    final amount = sort.amount(upload: slice.upload, download: slice.download);
    if (amount <= 0) continue;
    totals.update(
      id,
      (prev) => (
        amount: prev.amount + amount,
        label: prev.label.isNotEmpty ? prev.label : slice.applicationLabel,
      ),
      ifAbsent: () => (amount: amount, label: slice.applicationLabel),
    );
  }
  final ids = totals.keys.toList()
    ..sort((a, b) {
      final aEntry = totals[a]!;
      final bEntry = totals[b]!;
      final byAmount = bEntry.amount.compareTo(aEntry.amount);
      if (byAmount != 0) return byAmount;
      final byLabel = aEntry.label.compareTo(bEntry.label);
      if (byLabel != 0) return byLabel;
      return a.compareTo(b);
    });
  final palette = primaryHct.chroma < 8
      ? [
          colors.primary,
          Color(Hct.from(0, 0, dark ? 64 : 44).toInt()),
          Color(Hct.from(0, 0, dark ? 48 : 62).toInt()),
        ]
      : [
          colors.primary,
          Color(
            Hct.from(
              (primaryHct.hue + 145) % 360,
              math.max(38.0, math.min(primaryHct.chroma, 54.0)),
              dark ? 72.0 : 46.0,
            ).toInt(),
          ),
          Color(
            Hct.from(
              (primaryHct.hue + 250) % 360,
              math.max(36.0, math.min(primaryHct.chroma, 52.0)),
              dark ? 74.0 : 48.0,
            ).toInt(),
          ),
        ];
  return {
    for (final (index, id) in ids.take(3).indexed) id: palette[index],
    null: Color(Hct.from(primaryHct.hue, 4, dark ? 34 : 76).toInt()),
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

typedef _SegmentBox = ({
  int barIndex,
  int periodIndex,
  String? appId,
  Rect rect,
  Color color,
});

typedef _BarBox = ({
  int barIndex,
  int periodIndex,
  Rect barRect,
  List<_SegmentBox> segments,
});

class _TrafficChart extends StatefulWidget {
  final Object scopeKey;
  final AppTrafficSort sort;
  final List<_TrafficBar> bars;
  final Map<String?, Color> swatches;

  const _TrafficChart({
    required this.scopeKey,
    required this.sort,
    required this.bars,
    required this.swatches,
  });

  @override
  State<_TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<_TrafficChart> {
  static const _plotPad = 7.0;
  static const _plotHeight = 120.0;
  static const _areaHeight = _plotHeight + _plotPad * 2;
  static const _minBarHeight = 6.0;
  static const _minSegmentHeight = 3.0;

  late final _focusNode = FocusNode();
  _TrafficSegment? _hover;
  _TrafficSegment? _selection;
  _TrafficSegment? _focused;
  ({String? appId})? _legendFilter;
  bool _hasFocus = false;

  @override
  void didUpdateWidget(_TrafficChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scopeKey != oldWidget.scopeKey) {
      _hover = null;
      _selection = null;
      _focused = null;
      _legendFilter = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int _barAmount(_TrafficBar bar) => bar.amount(widget.sort);

  int _sliceAmount(AppTrafficBucket slice) =>
      widget.sort.amount(upload: slice.upload, download: slice.download);

  List<_BarBox> _layoutBars(double plotWidth, int peak) {
    final bars = widget.bars;
    if (bars.isEmpty || peak <= 0 || plotWidth <= 0) {
      return const [];
    }
    final slotWidth = plotWidth / bars.length;
    final barWidth = math.max(
      math.min(slotWidth * 0.85, 6.0),
      math.min(40.0, slotWidth * 0.68),
    );
    const baselineY = _plotPad + _plotHeight;
    final boxes = <_BarBox>[];
    for (final (barIndex, bar) in bars.indexed) {
      final barAmount = _barAmount(bar);
      if (barAmount <= 0) {
        continue;
      }
      final barHeight = math.max(_minBarHeight, _plotHeight * barAmount / peak);
      final left = barIndex * slotWidth + (slotWidth - barWidth) / 2;
      final top = baselineY - barHeight;
      final barRect = Rect.fromLTWH(left, top, barWidth, barHeight);
      final activeSlices = <(String?, AppTrafficBucket, Color, int)>[];
      for (final MapEntry(:key, :value) in widget.swatches.entries) {
        final slice = bar.apps[key];
        if (slice == null) continue;
        final amount = _sliceAmount(slice);
        if (amount <= 0) continue;
        activeSlices.add((key, slice, value, amount));
      }
      if (activeSlices.isEmpty) {
        continue;
      }
      final minTotal = math.min(
        barHeight,
        activeSlices.length * _minSegmentHeight,
      );
      final perMin = minTotal / activeSlices.length;
      final extraHeight = math.max(0.0, barHeight - minTotal);
      final sliceSum = activeSlices.fold<int>(0, (sum, item) => sum + item.$4);
      final segments = <_SegmentBox>[];
      var cursorY = baselineY;
      for (var i = 0; i < activeSlices.length; i++) {
        final (appId, _, color, amount) = activeSlices[i];
        final isLast = i == activeSlices.length - 1;
        final segHeight = isLast
            ? cursorY - top
            : perMin + extraHeight * (amount / sliceSum);
        final segTop = isLast ? top : cursorY - segHeight;
        segments.add((
          barIndex: barIndex,
          periodIndex: bar.period.index,
          appId: appId,
          rect: Rect.fromLTWH(
            left,
            segTop,
            barWidth,
            math.max(0, cursorY - segTop),
          ),
          color: color,
        ));
        cursorY = segTop;
      }
      boxes.add((
        barIndex: barIndex,
        periodIndex: bar.period.index,
        barRect: barRect,
        segments: segments,
      ));
    }
    return boxes;
  }

  _TrafficSegment? _hitTest(
    Offset position,
    double plotWidth,
    List<_BarBox> boxes,
  ) {
    if (widget.bars.isEmpty || plotWidth <= 0) {
      return null;
    }
    final slotWidth = plotWidth / widget.bars.length;
    final barIndex = (position.dx / slotWidth).floor().clamp(
      0,
      widget.bars.length - 1,
    );
    final box = boxes.where((b) => b.barIndex == barIndex).firstOrNull;
    if (box == null) {
      return null;
    }
    for (final seg in box.segments) {
      if (position.dy >= seg.rect.top && position.dy <= seg.rect.bottom) {
        return (seg.periodIndex, seg.appId);
      }
    }
    if (position.dy >= box.barRect.top - 12 && position.dy < box.barRect.top) {
      final topSeg = box.segments.last;
      return (topSeg.periodIndex, topSeg.appId);
    }
    if (position.dy > box.barRect.bottom &&
        position.dy <= _plotPad + _plotHeight) {
      final bottomSeg = box.segments.first;
      return (bottomSeg.periodIndex, bottomSeg.appId);
    }
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final nonEmpty = [
      for (final bar in widget.bars)
        if (_barAmount(bar) > 0) bar,
    ];
    if (nonEmpty.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selection != null || _focused != null || _legendFilter != null) {
        setState(() {
          _selection = null;
          _focused = null;
          _legendFilter = null;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    List<String?> orderedApps(_TrafficBar bar) => [
      for (final appId in widget.swatches.keys)
        if (bar.apps[appId] case final slice? when _sliceAmount(slice) > 0)
          appId,
    ];
    final current = _focused ?? _selection;
    var barIdx = current == null
        ? 0
        : nonEmpty.indexWhere((b) => b.period.index == current.$1);
    if (barIdx < 0) barIdx = 0;
    final barApps = orderedApps(nonEmpty[barIdx]);
    var segIdx = current == null ? 0 : barApps.indexOf(current.$2);
    if (segIdx < 0) segIdx = 0;

    if (key == LogicalKeyboardKey.arrowRight) {
      barIdx = (barIdx + 1) % nonEmpty.length;
      final apps = orderedApps(nonEmpty[barIdx]);
      if (apps.isNotEmpty) {
        setState(() {
          _focused = (nonEmpty[barIdx].period.index, apps.first);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      barIdx = (barIdx - 1 + nonEmpty.length) % nonEmpty.length;
      final apps = orderedApps(nonEmpty[barIdx]);
      if (apps.isNotEmpty) {
        setState(() {
          _focused = (nonEmpty[barIdx].period.index, apps.first);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && barApps.isNotEmpty) {
      segIdx = (segIdx + 1) % barApps.length;
      setState(() {
        _focused = (nonEmpty[barIdx].period.index, barApps[segIdx]);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && barApps.isNotEmpty) {
      segIdx = (segIdx - 1 + barApps.length) % barApps.length;
      setState(() {
        _focused = (nonEmpty[barIdx].period.index, barApps[segIdx]);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      final target = _focused ?? (nonEmpty[barIdx].period.index, barApps.first);
      setState(() {
        _legendFilter = null;
        _selection = _selection == target ? null : target;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final bars = widget.bars;
    final totals = <String?, AppTrafficBucket>{};
    var peak = 0;
    _TrafficBar? peakBar;
    var overall = 0;
    for (final bar in bars) {
      final total = _barAmount(bar);
      if (total > peak) {
        peak = total;
        peakBar = bar;
      }
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
    final muted = Color(Hct.from(0, 0, dark ? 24 : 86).toInt());
    final axisStyle = AppTextStyle.caption2
        .of(context)
        .toTabular
        .copyWith(color: colors.onSurfaceVariant);
    final percentage = NumberFormat.decimalPercentPattern(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    );

    _TrafficBar? barFor(_TrafficSegment? segment) => segment == null
        ? null
        : bars.where((bar) => bar.period.index == segment.$1).firstOrNull;

    bool hasValidSegment(_TrafficSegment? segment) {
      final slice = barFor(segment)?.apps[segment?.$2];
      return slice != null && _sliceAmount(slice) > 0;
    }

    final activeSegment = hasValidSegment(_hover)
        ? _hover
        : (_hasFocus && hasValidSegment(_focused))
        ? _focused
        : hasValidSegment(_selection)
        ? _selection
        : null;
    final activeBar = barFor(activeSegment);
    final activeSlice = activeBar?.apps[activeSegment?.$2];
    final activeLegendApp = activeSegment == null ? _legendFilter : null;

    String label(AppTrafficBucket slice) => slice.applicationId == null
        ? l10n.other
        : slice.applicationLabel.isEmpty
        ? l10n.unknownApplication
        : slice.applicationLabel;

    String amountAndShare(AppTrafficBucket slice, int total) {
      final amount = _sliceAmount(slice);
      final share = total > 0 ? percentage.format(amount / total) : '0%';
      return '${amount.traffic.show} · $share';
    }

    final showFocusRing =
        _hasFocus &&
        (RemoteFocusAdapter.isEnabledOf(context) ||
            FocusMovedByKey.instance.value);
    final focusRingSegment = showFocusRing ? (_focused ?? _selection) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        _ChartReadout(
          activeBar: activeBar,
          activeSlice: activeSlice,
          activeColor: activeSlice == null
              ? null
              : swatches[activeSlice.applicationId],
          isPinned: _selection != null && _hover == null,
          onClearPin: () => setState(() => _selection = null),
          peakBar: peakBar,
          peak: peak,
          barAmount: activeBar == null ? 0 : _barAmount(activeBar),
          labelOf: label,
          amountAndShare: amountAndShare,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final plotWidth = constraints.maxWidth;
                  final boxes = _layoutBars(plotWidth, peak);
                  final activeBox = activeSegment == null
                      ? null
                      : boxes
                            .where((b) => b.periodIndex == activeSegment.$1)
                            .firstOrNull
                            ?.segments
                            .where((s) => s.appId == activeSegment.$2)
                            .firstOrNull;
                  return Column(
                    spacing: 6,
                    children: [
                      SizedBox(
                        height: _areaHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Positioned(
                              left: 0,
                              right: 0,
                              top: _plotPad,
                              bottom: _plotPad,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Divider(height: 1),
                                  Divider(height: 1),
                                  Divider(height: 1),
                                ],
                              ),
                            ),
                            Positioned.fill(
                              child: Focus(
                                focusNode: _focusNode,
                                onFocusChange: (focused) =>
                                    setState(() => _hasFocus = focused),
                                onKeyEvent: _handleKeyEvent,
                                child: MouseRegion(
                                  cursor: boxes.isNotEmpty
                                      ? SystemMouseCursors.click
                                      : MouseCursor.defer,
                                  onHover: (event) {
                                    final hit = _hitTest(
                                      event.localPosition,
                                      plotWidth,
                                      boxes,
                                    );
                                    if (hit != _hover) {
                                      setState(() => _hover = hit);
                                    }
                                  },
                                  onExit: (_) {
                                    if (_hover != null) {
                                      setState(() => _hover = null);
                                    }
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      final hit = _hitTest(
                                        details.localPosition,
                                        plotWidth,
                                        boxes,
                                      );
                                      setState(() {
                                        _legendFilter = null;
                                        if (hit == null) {
                                          _selection = null;
                                        } else {
                                          _selection = _selection == hit
                                              ? null
                                              : hit;
                                        }
                                      });
                                    },
                                    child: CustomPaint(
                                      painter: _BarsPainter(
                                        boxes: boxes,
                                        activeSegment: activeSegment,
                                        activeLegendApp: activeLegendApp,
                                        focusRingSegment: focusRingSegment,
                                        mutedColor: muted,
                                        focusRingColor: colors.primary,
                                        selectionRingColor: colors.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_hover != null &&
                                activeBox != null &&
                                activeBar != null &&
                                activeSlice != null)
                              _FloatingChartCallout(
                                plotWidth: plotWidth,
                                anchorRect: activeBox.rect,
                                title:
                                    '${activeBar.period.title} · ${label(activeSlice)}',
                                detail: amountAndShare(
                                  activeSlice,
                                  _barAmount(activeBar),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _XAxisLabels(
                        bars: bars,
                        plotWidth: plotWidth,
                        style: axisStyle,
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              height: _areaHeight,
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
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final MapEntry(:key, :value) in swatches.entries)
              if (totals[key] case final slice? when _sliceAmount(slice) > 0)
                _LegendItem(
                  color: value,
                  label: '${label(slice)} · ${amountAndShare(slice, overall)}',
                  selected:
                      activeLegendApp != null && activeLegendApp.appId == key,
                  dimmed:
                      activeLegendApp != null && activeLegendApp.appId != key,
                  onTap: () => setState(() {
                    _selection = null;
                    _legendFilter =
                        activeLegendApp?.appId == key && activeLegendApp != null
                        ? null
                        : (appId: key);
                  }),
                ),
          ],
        ),
      ],
    );
  }
}

class _ChartReadout extends StatelessWidget {
  final _TrafficBar? activeBar;
  final AppTrafficBucket? activeSlice;
  final Color? activeColor;
  final bool isPinned;
  final VoidCallback onClearPin;
  final _TrafficBar? peakBar;
  final int peak;
  final int barAmount;
  final String Function(AppTrafficBucket) labelOf;
  final String Function(AppTrafficBucket, int) amountAndShare;

  const _ChartReadout({
    required this.activeBar,
    required this.activeSlice,
    required this.activeColor,
    required this.isPinned,
    required this.onClearPin,
    required this.peakBar,
    required this.peak,
    required this.barAmount,
    required this.labelOf,
    required this.amountAndShare,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = context.colorScheme;
    if (activeBar != null && activeSlice != null && activeColor != null) {
      return Row(
        spacing: 6,
        children: [
          _TrafficSwatch(color: activeColor!),
          Expanded(
            child: Text(
              '${activeBar!.period.title} · ${labelOf(activeSlice!)} · ${amountAndShare(activeSlice!, barAmount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .toTabular
                  .copyWith(color: colors.onSurface),
            ),
          ),
          Text(
            '↑${activeSlice!.upload.traffic.show} ↓${activeSlice!.download.traffic.show}',
            style: AppTextStyle.caption1
                .of(context)
                .toTabular
                .copyWith(color: colors.onSurfaceVariant),
          ),
          if (isPinned)
            PressSurface(
              fill: const Color(0x00000000),
              shape: AppShape.circle,
              padding: const EdgeInsets.all(2),
              onPressed: onClearPin,
              child: GlyphIcon(
                AppGlyphs.close,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      );
    }
    if (peakBar == null) {
      return const SizedBox.shrink();
    }
    return Text(
      l10n.trafficPeak('${peakBar!.period.title} · ${peak.traffic.show}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.footnote
          .of(context)
          .toTabular
          .copyWith(color: colors.onSurfaceVariant),
    );
  }
}

class _FloatingChartCallout extends StatelessWidget {
  final double plotWidth;
  final Rect anchorRect;
  final String title;
  final String detail;

  const _FloatingChartCallout({
    required this.plotWidth,
    required this.anchorRect,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final surface = SurfaceLevel.floatingOf(colors).colorOf(colors);
    const maxCalloutWidth = 200.0;
    final estWidth = math.min(
      maxCalloutWidth,
      math.max(96.0, math.max(title.length, detail.length) * 7.2 + 20),
    );
    final nearTop = anchorRect.top < 46;
    final double left;
    final double top;
    if (nearTop) {
      final canPlaceRight = anchorRect.right + 8 + estWidth <= plotWidth;
      left = canPlaceRight
          ? anchorRect.right + 8
          : math.max(0.0, anchorRect.left - 8 - estWidth);
      top = math.max(0.0, anchorRect.top);
    } else {
      left = (anchorRect.center.dx - estWidth / 2).clamp(
        0.0,
        math.max(0.0, plotWidth - estWidth),
      );
      top = anchorRect.top - 46;
    }
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxCalloutWidth),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: surface,
              shape: AppShape.sm.copyWith(
                side: BorderSide(color: Divider.colorOf(context)),
              ),
              shadows: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption2
                        .of(context, emphasized: true)
                        .toTabular
                        .copyWith(color: colors.onSurface),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption2
                        .of(context)
                        .toTabular
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  final List<_TrafficBar> bars;
  final double plotWidth;
  final TextStyle style;

  const _XAxisLabels({
    required this.bars,
    required this.plotWidth,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || plotWidth <= 0) {
      return const SizedBox.shrink();
    }
    final maxLen = bars.fold<int>(
      0,
      (prev, bar) => math.max(prev, bar.period.label.length),
    );
    final labelWidth = MediaQuery.textScalerOf(context).scale(maxLen * 7.0 + 8);
    if (bars.length <= 7 && labelWidth * bars.length <= plotWidth) {
      return Row(
        children: [
          for (final bar in bars)
            Expanded(
              child: Center(
                child: Text(
                  bar.period.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: style,
                ),
              ),
            ),
        ],
      );
    }
    final maxTicks = math.max(2, (plotWidth / labelWidth).floor());
    final stride = ((bars.length - 1) / (maxTicks - 1)).ceil().clamp(
      1,
      bars.length,
    );
    final ticks = <int>[];
    for (var i = 0; i < bars.length; i += stride) {
      ticks.add(i);
    }
    final last = bars.length - 1;
    if (ticks.last != last) {
      if (last - ticks.last < stride / 2 && ticks.length > 1) {
        ticks.removeLast();
      }
      ticks.add(last);
    }
    final slotWidth = plotWidth / bars.length;
    final boxWidth = math.max(labelWidth, slotWidth);
    return SizedBox(
      height: MediaQuery.textScalerOf(
        context,
      ).scale(AppTextStyle.caption2.leading),
      width: plotWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final index in ticks)
            Positioned(
              left: ((index + 0.5) * slotWidth - boxWidth / 2).clamp(
                0.0,
                math.max(0.0, plotWidth - boxWidth),
              ),
              width: math.min(boxWidth, plotWidth),
              child: Text(
                bars[index].period.label,
                maxLines: 1,
                textAlign: index == 0
                    ? TextAlign.start
                    : index == last
                    ? TextAlign.end
                    : TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return PressSurface(
      fill: selected
          ? SurfaceLevel.block.colorOf(colors)
          : const Color(0x00000000),
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          _TrafficSwatch(color: dimmed ? colors.outlineVariant : color),
          Flexible(
            child: Text(
              label,
              style: AppTextStyle.footnote
                  .of(context, emphasized: selected)
                  .toTabular
                  .copyWith(
                    color: dimmed ? colors.onSurfaceVariant : colors.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<_BarBox> boxes;
  final _TrafficSegment? activeSegment;
  final ({String? appId})? activeLegendApp;
  final _TrafficSegment? focusRingSegment;
  final Color mutedColor;
  final Color focusRingColor;
  final Color selectionRingColor;

  _BarsPainter({
    required this.boxes,
    required this.activeSegment,
    required this.activeLegendApp,
    required this.focusRingSegment,
    required this.mutedColor,
    required this.focusRingColor,
    required this.selectionRingColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final box in boxes) {
      final barShape = AppRadius.top(AppCorner.xs).toRSuperellipse(box.barRect);
      canvas.save();
      canvas.clipRSuperellipse(barShape);
      for (final seg in box.segments) {
        final id = (seg.periodIndex, seg.appId);
        final lit = activeSegment != null
            ? activeSegment == id
            : activeLegendApp == null || activeLegendApp!.appId == seg.appId;
        paint.color = lit ? seg.color : mutedColor;
        canvas.drawRect(seg.rect, paint);
      }
      canvas.restore();
    }
    if (activeSegment case final target?) {
      for (final box in boxes) {
        if (box.periodIndex != target.$1) continue;
        for (final seg in box.segments) {
          if (seg.appId == target.$2) {
            canvas.drawRSuperellipse(
              RSuperellipse.fromRectAndRadius(
                seg.rect,
                const Radius.circular(AppCorner.xs),
              ),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = selectionRingColor.withValues(alpha: 0.7),
            );
          }
        }
      }
    }
    if (focusRingSegment case final target?) {
      for (final box in boxes) {
        if (box.periodIndex != target.$1) continue;
        for (final seg in box.segments) {
          if (seg.appId == target.$2) {
            canvas.drawRSuperellipse(
              RSuperellipse.fromRectAndRadius(
                seg.rect.inflate(2),
                const Radius.circular(AppCorner.xs),
              ),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = focusRingColor,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.boxes != boxes ||
      oldDelegate.activeSegment != activeSegment ||
      oldDelegate.activeLegendApp != activeLegendApp ||
      oldDelegate.focusRingSegment != focusRingSegment ||
      oldDelegate.mutedColor != mutedColor ||
      oldDelegate.focusRingColor != focusRingColor ||
      oldDelegate.selectionRingColor != selectionRingColor;
}
