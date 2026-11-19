#ifndef FLUTTER_PLUGIN_TRAY_PANEL_PLUGIN_INTERNAL_H_
#define FLUTTER_PLUGIN_TRAY_PANEL_PLUGIN_INTERNAL_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "tray_panel_model.h"
#include "tray_panel_window.h"

namespace tray {

class TrayPanelPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  TrayPanelPlugin(
      flutter::PluginRegistrarWindows* registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

  ~TrayPanelPlugin() override;

  TrayPanelPlugin(const TrayPanelPlugin&) = delete;
  TrayPanelPlugin& operator=(const TrayPanelPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SyncTrayOwner();
  void SendEvent(const char* name, const flutter::EncodableValue& arguments);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<TrayPanelWindow> panel_;
};

}  // namespace tray

#endif  // FLUTTER_PLUGIN_TRAY_PANEL_PLUGIN_INTERNAL_H_
