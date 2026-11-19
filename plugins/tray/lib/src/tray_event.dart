import 'tray_menu.dart';

sealed class TrayEvent {
  const TrayEvent();
}

final class TrayIconActivated extends TrayEvent {
  const TrayIconActivated();
}

final class TrayMenuRequested extends TrayEvent {
  const TrayMenuRequested();
}

final class TrayMenuItemSelected extends TrayEvent {
  const TrayMenuItemSelected(this.item);

  final TrayMenuItem item;
}

final class TrayPanelVisibilityChanged extends TrayEvent {
  const TrayPanelVisibilityChanged(this.visible);

  final bool visible;
}

final class TrayPanelAction extends TrayEvent {
  const TrayPanelAction(
    this.action, [
    this.payload = const <String, Object?>{},
  ]);

  final String action;
  final Map<String, Object?> payload;
}
