import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/tray.dart';
import 'package:tray_panel/tray_panel.dart';

class TrayManager extends ConsumerStatefulWidget {
  final Widget child;
  final AppTray? tray;

  const TrayManager({
    super.key,
    required this.child,
    @visibleForTesting this.tray,
  });

  @override
  ConsumerState<TrayManager> createState() => _TrayManagerState();
}

class _TrayManagerState extends ConsumerState<TrayManager> {
  StreamSubscription<TrayEvent>? _subscription;
  StreamSubscription<TrayPanelEvent>? _panelSubscription;
  final List<ProviderSubscription<Object?>> _panelSubscriptions = [];
  Timer? _panelDelaySyncTimer;
  bool _isUpdating = false;
  bool _hasPendingUpdate = false;
  bool _isPanelVisible = false;

  AppTray? get _tray => widget.tray ?? appTray;

  @override
  void initState() {
    super.initState();
    _subscription = Tray.instance.events.listen(_handleTrayEvent);
    _panelSubscription = TrayPanel.instance.events.listen(
      _handleTrayPanelEvent,
    );
    ref.listenManual(trayStateProvider, (prev, next) {
      if (prev != next) {
        _requestUpdate();
      }
    });
    ref.listenManual(loadedLocaleProvider, (prev, next) {
      if (prev != null && prev != next) {
        _requestUpdate();
      }
    });
    if (_tray?.isMacOS ?? system.isMacOS) {
      ref.listenManual(trayTitleStateProvider, (prev, next) {
        if (prev != next) {
          _reportFailure(
            _tray?.updateTitle(
              showTrayTitle: next.showTrayTitle,
              traffic: next.traffic,
            ),
          );
        }
      });
    }
  }

  void _requestUpdate() {
    if (_isUpdating) {
      _hasPendingUpdate = true;
      return;
    }
    _isUpdating = true;
    _reportFailure(_drainUpdates());
  }

  Future<void> _drainUpdates() async {
    try {
      do {
        _hasPendingUpdate = false;
        await ref.read(systemActionProvider.notifier).updateTray();
      } while (_hasPendingUpdate && mounted);
    } finally {
      _isUpdating = false;
      if (_hasPendingUpdate && mounted) {
        _requestUpdate();
      }
    }
  }

  void _handlePanelVisibilityChanged(bool visible) {
    if (_isPanelVisible == visible) {
      return;
    }
    _isPanelVisible = visible;
    ref.read(trayPanelVisibleProvider.notifier).setVisible(visible);
    if (visible) {
      _attachPanelSubscriptions();
      _syncPanel();
      _syncPanelTraffic();
    } else {
      _detachPanelSubscriptions();
    }
  }

  void _attachPanelSubscriptions() {
    if (_panelSubscriptions.isNotEmpty) {
      return;
    }
    _panelSubscriptions.addAll([
      ref.listenManual<Map<String, Map<String, int>>>(trayDelaysProvider, (
        prev,
        next,
      ) {
        if (!const DeepCollectionEquality().equals(prev, next)) {
          _schedulePanelSync();
        }
      }),
      ref.listenManual<Map<String, DelayTestPhase>>(pendingDelayTestsProvider, (
        prev,
        next,
      ) {
        if (!const MapEquality<String, DelayTestPhase>().equals(prev, next)) {
          _schedulePanelSync();
        }
      }),
      ref.listenManual<ThemeProps>(themeSettingProvider, (prev, next) {
        if (prev != next) {
          _syncPanel();
        }
      }),
      ref.listenManual<Brightness>(currentBrightnessProvider, (prev, next) {
        if (prev != next) {
          _syncPanel();
        }
      }),
      ref.listenManual<Traffic>(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
        (prev, next) {
          if (prev != next) {
            _syncPanelTraffic(next);
          }
        },
      ),
    ]);
  }

  void _detachPanelSubscriptions() {
    _panelDelaySyncTimer?.cancel();
    _panelDelaySyncTimer = null;
    for (final subscription in _panelSubscriptions) {
      subscription.close();
    }
    _panelSubscriptions.clear();
  }

  void _schedulePanelSync() {
    _panelDelaySyncTimer ??= Timer(const Duration(milliseconds: 50), () {
      _panelDelaySyncTimer = null;
      if (mounted && _isPanelVisible) {
        _syncPanel();
      }
    });
  }

  void _syncPanel() {
    if (!mounted) {
      return;
    }
    _reportFailure(
      _tray?.updatePanel(
        trayState: ref.read(trayStateProvider),
        read: ref.read,
      ),
    );
  }

  void _syncPanelTraffic([Traffic? traffic]) {
    if (!mounted) {
      return;
    }
    final current =
        traffic ?? ref.read(trafficsProvider).list.safeLast(const Traffic());
    _reportFailure(_tray?.updatePanelTraffic(current));
  }

  void _reportFailure(Future<void>? operation) {
    if (operation == null) {
      return;
    }
    unawaited(
      operation.onError<Object>((error, stackTrace) {
        commonPrint.log(
          'Tray operation failed: ${compactError(error)}',
          logLevel: LogLevel.error,
        );
      }),
    );
  }

  void _handleTrayEvent(TrayEvent event) {
    final panelCapabilities = TrayPanel.instance.capabilities;
    switch (event) {
      case TrayIconActivated():
        if (panelCapabilities.supported && panelCapabilities.openOnActivate) {
          _reportFailure(TrayPanel.instance.toggle());
          return;
        }
        if (panelCapabilities.supported && _isPanelVisible) {
          _reportFailure(TrayPanel.instance.close());
        }
        window?.show();
      case TrayMenuRequested():
        if (panelCapabilities.supported && !panelCapabilities.openOnActivate) {
          _reportFailure(TrayPanel.instance.toggle());
        } else {
          if (panelCapabilities.supported && _isPanelVisible) {
            _reportFailure(TrayPanel.instance.close());
          }
          _reportFailure(Tray.instance.openMenu());
        }
      case TrayMenuItemSelected():
        break;
    }
  }

  void _handleTrayPanelEvent(TrayPanelEvent event) {
    switch (event) {
      case TrayPanelVisibilityChanged(:final visible):
        _handlePanelVisibilityChanged(visible);
      case TrayPanelAction():
        _tray?.handlePanelAction(event, read: ref.read);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    _detachPanelSubscriptions();
    _panelSubscription?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
