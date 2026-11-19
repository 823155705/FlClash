#include "include/tray_panel/tray_panel_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "tray_panel_plugin.h"

void TrayPanelPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  tray::TrayPanelPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
