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
import 'package:tray/tray.dart';

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
      if (!Tray.instance.capabilities.panel) {
        ref.listenManual(trayDelaysProvider, (prev, next) {
          if (!const DeepCollectionEquality().equals(prev, next)) {
            _requestUpdate();
          }
        });
      }
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

  /// A delay test changes the menu per proxy, so updates in flight coalesce.
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
    switch (event) {
      case TrayIconActivated():
        if (Tray.instance.capabilities.panel && _isPanelVisible) {
          _reportFailure(Tray.instance.closePanel());
        }
        window?.show();
      case TrayMenuRequested():
        if (Tray.instance.capabilities.panel) {
          _reportFailure(Tray.instance.togglePanel());
        } else {
          _reportFailure(Tray.instance.openMenu());
        }
      case TrayMenuItemSelected():
        break;
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
    _subscription?.cancel();
    super.dispose();
  }
}
