import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/widget.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WidgetManager extends ConsumerStatefulWidget {
  final WidgetChannel? channel;
  final Widget child;

  const WidgetManager({super.key, this.channel, required this.child});

  @override
  ConsumerState<WidgetManager> createState() => _WidgetManagerState();
}

class _WidgetManagerState extends ConsumerState<WidgetManager>
    with WidgetListener {
  static const _mapEquality = DeepCollectionEquality();

  bool _isListening = false;
  bool _hasActiveWidgets = false;
  Map<String, Object?>? _lastSnapshot;
  PendingWidgetAction? _pendingAction;

  WidgetChannel? get _channel => widget.channel ?? widgetChannel;

  @override
  void initState() {
    super.initState();
    if (ref.read(safeModeProvider)) {
      return;
    }
    final channel = _channel;
    if (channel == null) {
      return;
    }
    _isListening = true;
    channel.addListener(this);
    _attachSubscriptions();
    unawaited(_initializeWidgetBridge(channel));
  }

  void _attachSubscriptions() {
    ref.listenManual(currentProfileProvider, (_, _) => _syncSnapshot());
    ref.listenManual(
      patchClashConfigProvider.select(
        (state) => (mode: state.mode, tunEnable: state.tun.enable),
      ),
      (_, _) => _syncSnapshot(),
    );
    ref.listenManual(groupsProvider, (_, _) {
      _syncSnapshot();
      _flushPendingAction();
    });
    ref.listenManual(currentGroupsStateProvider, (_, _) => _syncSnapshot());
    ref.listenManual(selectedMapProvider, (_, _) => _syncSnapshot());
    ref.listenManual(suspendProvider, (_, _) => _syncSnapshot());
    ref.listenManual(
      themeSettingProvider.select(
        (state) => (
          primaryColor: state.primaryColor,
          colorStyle: state.colorStyle,
          pureBlack: state.pureBlack,
        ),
      ),
      (_, _) => _syncSnapshot(),
    );
    ref.listenManual(dynamicColorProvider, (_, _) => _syncSnapshot());
    ref.listenManual(loadedLocaleProvider, (_, _) => _syncSnapshot());
    ref.listenManual(initProvider, (_, next) {
      if (next) {
        _flushPendingAction();
      }
    });
  }

  Future<void> _initializeWidgetBridge(WidgetChannel channel) async {
    final active = await channel.hasActiveWidgets();
    if (!mounted) {
      return;
    }
    _hasActiveWidgets = active;
    if (active) {
      _syncSnapshot(force: true);
    }
    final pending = await channel.consumePendingAction();
    if (!mounted || pending == null) {
      return;
    }
    _pendingAction = pending;
    _flushPendingAction();
  }

  void _flushPendingAction() {
    final pending = _pendingAction;
    if (pending == null || !ref.read(initProvider)) {
      return;
    }
    if (pending is PendingWidgetSelectProxy &&
        ref.read(groupsProvider).isEmpty) {
      return;
    }
    _pendingAction = null;
    switch (pending) {
      case PendingWidgetCycleMode():
        onCycleMode();
      case PendingWidgetSelectProxy(:final groupName, :final proxyName):
        onSelectProxy(groupName, proxyName);
    }
  }

  Group? _resolveActiveGroup({
    required Mode mode,
    required List<Group> groups,
    required String? currentGroupName,
  }) {
    if (groups.isEmpty || mode == Mode.direct) {
      return null;
    }
    if (mode == Mode.global) {
      return groups.getGroup(GroupName.GLOBAL.name) ??
          groups.firstWhereOrNull((group) => group.all.isNotEmpty) ??
          groups.first;
    }
    final visibleGroups = groups
        .where(
          (group) =>
              group.hidden != true && group.name != GroupName.GLOBAL.name,
        )
        .toList();
    final candidates = visibleGroups.isNotEmpty
        ? visibleGroups
        : groups.where((group) => group.hidden != true).toList();
    if (candidates.isEmpty) {
      return null;
    }
    if (currentGroupName != null && currentGroupName.isNotEmpty) {
      final current = candidates.firstWhereOrNull(
        (group) => group.name == currentGroupName && group.all.isNotEmpty,
      );
      if (current != null) {
        return current;
      }
    }
    return candidates.firstWhereOrNull(
          (group) => group.type == GroupType.Selector && group.all.isNotEmpty,
        ) ??
        candidates.firstWhereOrNull((group) => group.all.isNotEmpty) ??
        candidates.first;
  }

  Map<String, Object?> _buildSnapshot() {
    final profile = ref.read(currentProfileProvider);
    final hasProfile = profile != null;
    final profileName = profile?.realLabel ?? '';
    final clashConfig = ref.read(patchClashConfigProvider);
    final mode = clashConfig.mode;
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(selectedMapProvider);
    final activeGroup = hasProfile
        ? _resolveActiveGroup(
            mode: mode,
            groups: groups,
            currentGroupName: profile.currentGroupName,
          )
        : null;
    final groupName = activeGroup?.name ?? '';
    final nodeName = activeGroup == null
        ? ''
        : activeGroup.getCurrentSelectedName(selectedMap[groupName] ?? '');
    final canSelectProxy =
        activeGroup != null &&
        activeGroup.all.isNotEmpty &&
        activeGroup.type == GroupType.Selector;
    final proxyNames = canSelectProxy
        ? [for (final proxy in activeGroup.all) proxy.name]
        : const <String>[];
    final pureBlack = ref.read(
      themeSettingProvider.select((state) => state.pureBlack),
    );
    final primaryColorLight = ref
        .read(genColorSchemeProvider(Brightness.light))
        .primary
        .toARGB32();
    final primaryColorDark = ref
        .read(genColorSchemeProvider(Brightness.dark))
        .primary
        .toARGB32();
    final appLocalizations = currentAppLocalizations;

    return <String, Object?>{
      'hasProfile': hasProfile,
      'profileName': profileName,
      'mode': mode.name,
      'groupName': groupName,
      'nodeName': nodeName,
      'canSelectProxy': canSelectProxy,
      'proxyNames': proxyNames,
      'suspended': ref.read(suspendProvider),
      'tunEnabled': clashConfig.tun.enable,
      'pureBlack': pureBlack,
      'primaryColorLight': primaryColorLight,
      'primaryColorDark': primaryColorDark,
      'labels': <String, String>{
        'running': appLocalizations.running,
        'notRunning': appLocalizations.notRunning,
        'connecting': appLocalizations.connecting,
        'stopping': appLocalizations.stopping,
        'suspended': appLocalizations.suspended,
        'noProfile': appLocalizations.noProfile,
        'tapToStart': appLocalizations.tapToStart,
        'modeRule': appLocalizations.rule,
        'modeGlobal': appLocalizations.global,
        'modeDirect': appLocalizations.direct,
        'direct': appLocalizations.direct,
        'selectNodeTitle': appLocalizations.selectNode,
        'noNodesAvailable': appLocalizations.noNodesAvailable,
        'openApp': appLocalizations.openApp,
      },
    };
  }

  void _syncSnapshot({bool force = false}) {
    if (!mounted || !_hasActiveWidgets || ref.read(safeModeProvider)) {
      return;
    }
    final channel = _channel;
    if (channel == null) {
      return;
    }
    final snapshot = _buildSnapshot();
    if (!force && _mapEquality.equals(_lastSnapshot, snapshot)) {
      return;
    }
    _lastSnapshot = snapshot;
    unawaited(channel.updateSnapshot(snapshot));
  }

  @override
  void onWidgetsActiveChanged(bool active) {
    _hasActiveWidgets = active;
    if (active) {
      _syncSnapshot(force: true);
    } else {
      _lastSnapshot = null;
    }
  }

  @override
  void onCycleMode() {
    if (ref.read(safeModeProvider)) {
      return;
    }
    final current = ref.read(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final nextIndex = (Mode.values.indexOf(current) + 1) % Mode.values.length;
    final nextMode = Mode.values[nextIndex];
    ref.read(setupActionProvider.notifier).changeMode(nextMode);
    unawaited(app?.tip(nextMode.label));
    super.onCycleMode();
  }

  @override
  void onSelectProxy(String groupName, String proxyName) {
    if (ref.read(safeModeProvider)) {
      return;
    }
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null ||
        group.type != GroupType.Selector ||
        !group.all.any((proxy) => proxy.name == proxyName)) {
      return;
    }
    unawaited(
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: groupName, proxyName: proxyName),
    );
    unawaited(app?.tip(proxyName));
    super.onSelectProxy(groupName, proxyName);
  }

  @override
  void dispose() {
    if (_isListening) {
      _channel?.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
