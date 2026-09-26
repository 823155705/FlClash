import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/iterable.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WidgetManager extends ConsumerStatefulWidget {
  final Widget child;

  const WidgetManager({super.key, required this.child});

  @override
  ConsumerState<WidgetManager> createState() => _WidgetManagerState();
}

class _WidgetManagerState extends ConsumerState<WidgetManager>
    with WidgetListener {
  String _lastMode = 'rule';
  String _lastNodeName = '';
  String _lastGroupName = '';
  num _lastUpSpeed = 0;
  num _lastDownSpeed = 0;
  DateTime _lastChartTime = DateTime(2000);

  static const _chartWidth = 120;
  static const _chartHeight = 30;

  @override
  Widget build(BuildContext context) {
    ref.listen(isStartProvider, (prev, next) {
      _updateWidget();
    });
    ref.listen(patchClashConfigProvider, (prev, next) {
      final newMode = next.mode.name;
      if (newMode != _lastMode) {
        _lastMode = newMode;
        _updateWidget();
      }
    });
    ref.listen(groupsProvider, (prev, next) {
      _updateNodeInfo(next);
    });
    ref.listen(trafficsProvider, (prev, next) {
      final traffic = next.list.safeLast(const Traffic());
      if (traffic.up != _lastUpSpeed || traffic.down != _lastDownSpeed) {
        _lastUpSpeed = traffic.up;
        _lastDownSpeed = traffic.down;
        _updateWidget();
      }
    });
    return widget.child;
  }

  String _findNodeName(List<Group> groups) {
    if (groups.isEmpty) return '';
    const ignored = {'DIRECT', 'REJECT', 'GLOBAL', 'PASS', 'COMPATIBLE'};
    final target = groups.cast<Group?>().firstWhere(
      (g) =>
          g!.now != null &&
          g.now!.isNotEmpty &&
          !ignored.contains(g.now!.toUpperCase()),
      orElse: () => null,
    );
    return target?.now ?? groups.first.now ?? '';
  }

  String _findGroupName(List<Group> groups) {
    if (groups.isEmpty) return '';
    const ignored = {'DIRECT', 'REJECT', 'GLOBAL', 'PASS', 'COMPATIBLE'};
    final target = groups.cast<Group?>().firstWhere(
      (g) =>
          g!.now != null &&
          g.now!.isNotEmpty &&
          !ignored.contains(g.now!.toUpperCase()),
      orElse: () => null,
    );
    return target?.name ?? groups.first.name;
  }

  void _updateNodeInfo(List<Group> groups) {
    final nodeName = _findNodeName(groups);
    final groupName = _findGroupName(groups);
    if (nodeName != _lastNodeName || groupName != _lastGroupName) {
      _lastNodeName = nodeName;
      _lastGroupName = groupName;
      _updateWidget();
    }
  }

  String _encodeProxyNames(String groupName) {
    final dynamicGroup = ref.read(groupsProvider).getGroup(groupName);
    if (dynamicGroup == null) return '';
    return jsonEncode(dynamicGroup.all.map((p) => p.name).toList());
  }

  void _updateWidget() {
    final isStart = ref.read(isStartProvider);
    final mode = ref.read(
      patchClashConfigProvider.select((state) => state.mode.name),
    );
    final groups = ref.read(groupsProvider);
    final traffic = ref.read(trafficsProvider).list.safeLast(const Traffic());
    final nodeName = _findNodeName(groups);
    final groupName = _findGroupName(groups);

    widgetChannel?.updateWidget(
      isStart: isStart,
      mode: mode,
      nodeName: nodeName,
      groupName: groupName,
      upSpeed: traffic.up,
      downSpeed: traffic.down,
      proxyNames: _encodeProxyNames(groupName),
    );
    _updateChart();
  }

  Future<void> _updateChart() async {
    final isStart = ref.read(isStartProvider);
    if (!isStart) return;
    final now = DateTime.now();
    if (now.difference(_lastChartTime) < const Duration(seconds: 3)) return;
    _lastChartTime = now;
    final trafficList = ref.read(trafficsProvider).list.toList();
    final chartBytes = await _generateChart(trafficList);
    if (!mounted || chartBytes == null) return;
    await widgetChannel?.updateWidget(
      isStart: ref.read(isStartProvider),
      mode: ref.read(patchClashConfigProvider.select((s) => s.mode.name)),
      nodeName: _lastNodeName,
      groupName: _lastGroupName,
      upSpeed: ref.read(trafficsProvider).list.safeLast(const Traffic()).up,
      downSpeed: ref.read(trafficsProvider).list.safeLast(const Traffic()).down,
      proxyNames: _encodeProxyNames(_lastGroupName),
      chartBytes: chartBytes,
    );
  }

  @override
  void onCycleMode() {
    ref.read(commonActionProvider.notifier).updateMode();
    unawaited(app?.tip(currentAppLocalizations.toggle));
    super.onCycleMode();
  }

  @override
  void onCycleNode() {
    final groups = ref.read(groupsProvider);
    final groupName = _lastGroupName;
    if (groupName.isEmpty) return;

    final group = groups.getGroup(groupName);
    if (group == null || group.all.isEmpty) return;

    final current = _lastNodeName.isNotEmpty ? _lastNodeName : group.now;
    final currentIndex = group.all.indexWhere((p) => p.name == current);
    final nextIndex = (currentIndex + 1) % group.all.length;
    final nextProxy = group.all[nextIndex];
    if (nextProxy.name == current) return;

    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, nextProxy.name);
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(groupName, nextProxy.name);
    app?.tip(nextProxy.name);
    super.onCycleNode();
  }

  @override
  void onSelectProxy(String proxyName) {
    final groupName = _lastGroupName;
    if (groupName.isEmpty) return;

    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(groupName, proxyName);
    app?.tip(proxyName);
    super.onSelectProxy(proxyName);
  }

  Future<Uint8List?> _generateChart(List<Traffic> trafficList) async {
    if (trafficList.length < 2) return null;
    final maxVal = trafficList.fold<num>(
      1,
      (max, t) => max > t.up + t.down ? max : t.up + t.down,
    );
    if (maxVal <= 0) return null;
    final maxD = maxVal.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0x08000000);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _chartWidth.toDouble(), _chartHeight.toDouble()),
      bgPaint,
    );

    final upPaint = Paint()
      ..color = const Color(0xFF6666FB)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final downPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final n = trafficList.length;
    final stepX = (_chartWidth - 4) / max(1, n - 1);

    Path buildPath(num Function(Traffic) getValue) {
      final path = Path();
      for (int i = 0; i < n; i++) {
        final x = 2.0 + i * stepX;
        final y =
            (_chartHeight - 2) -
            (getValue(trafficList[i]).toDouble() / maxD) * (_chartHeight - 4);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      return path;
    }

    canvas.drawPath(buildPath((t) => t.down), downPaint);
    canvas.drawPath(buildPath((t) => t.up), upPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(_chartWidth, _chartHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  void initState() {
    super.initState();
    widgetChannel?.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWidget();
    });
  }

  @override
  void dispose() {
    widgetChannel?.removeListener(this);
    super.dispose();
  }
}
