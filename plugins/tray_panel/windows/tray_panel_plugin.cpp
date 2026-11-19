#include "tray_panel_plugin.h"

#include <variant>

namespace tray {

namespace {

constexpr wchar_t kRustTrayWindowClass[] = L"FlClashTray";
constexpr UINT kRustTrayIconId = 1;

HWND FindRustTrayOwnerWindow() {
  const DWORD current_pid = ::GetCurrentProcessId();
  HWND candidate = ::FindWindowExW(nullptr, nullptr, kRustTrayWindowClass, nullptr);
  while (candidate != nullptr) {
    DWORD pid = 0;
    ::GetWindowThreadProcessId(candidate, &pid);
    if (pid == current_pid) {
      return candidate;
    }
    candidate = ::FindWindowExW(nullptr, candidate, kRustTrayWindowClass, nullptr);
  }
  return nullptr;
}

}  // namespace

void TrayPanelPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "tray_panel",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TrayPanelPlugin>(registrar, std::move(channel));
  registrar->AddPlugin(std::move(plugin));
}

TrayPanelPlugin::TrayPanelPlugin(
    flutter::PluginRegistrarWindows* registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : registrar_(registrar), channel_(std::move(channel)) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  panel_ = std::make_unique<TrayPanelWindow>(
      [this](bool visible) {
        flutter::EncodableMap arguments;
        arguments[flutter::EncodableValue("visible")] =
            flutter::EncodableValue(visible);
        SendEvent("onPanelVisibilityChanged",
                  flutter::EncodableValue(arguments));
      },
      [this](const std::string& action, const flutter::EncodableMap& payload) {
        flutter::EncodableMap arguments;
        arguments[flutter::EncodableValue("action")] =
            flutter::EncodableValue(action);
        arguments[flutter::EncodableValue("payload")] =
            flutter::EncodableValue(payload);
        SendEvent("onPanelAction", flutter::EncodableValue(arguments));
      });
}

TrayPanelPlugin::~TrayPanelPlugin() {
  if (panel_ != nullptr) {
    panel_->Destroy();
  }
}

void TrayPanelPlugin::SyncTrayOwner() {
  if (panel_ == nullptr) {
    return;
  }
  HWND owner = FindRustTrayOwnerWindow();
  if (owner == nullptr && registrar_->GetView() != nullptr) {
    owner = ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
  }
  panel_->SetOwner(owner, kRustTrayIconId);
}

void TrayPanelPlugin::SendEvent(const char* name,
                                const flutter::EncodableValue& arguments) {
  channel_->InvokeMethod(name,
                         std::make_unique<flutter::EncodableValue>(arguments));
}

void TrayPanelPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "setPanelState") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    TrayPanelState state;
    const bool decoded =
        arguments != nullptr && DecodePanelState(*arguments, &state);
    if (decoded && panel_ != nullptr) {
      SyncTrayOwner();
      result->Success(flutter::EncodableValue(panel_->SetState(state)));
    } else {
      result->Success(flutter::EncodableValue(false));
    }
    return;
  }

  if (method == "setPanelTraffic") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    TrayPanelTraffic traffic;
    if (arguments != nullptr && DecodePanelTraffic(*arguments, &traffic) &&
        panel_ != nullptr) {
      panel_->SetTraffic(traffic);
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Success(flutter::EncodableValue(false));
    }
    return;
  }

  if (method == "openPanel") {
    if (panel_ != nullptr) {
      SyncTrayOwner();
      result->Success(flutter::EncodableValue(panel_->Open()));
    } else {
      result->Success(flutter::EncodableValue(false));
    }
    return;
  }

  if (method == "closePanel") {
    result->Success(
        flutter::EncodableValue(panel_ != nullptr && panel_->Close()));
    return;
  }

  if (method == "togglePanel") {
    if (panel_ != nullptr) {
      SyncTrayOwner();
      result->Success(flutter::EncodableValue(panel_->Toggle()));
    } else {
      result->Success(flutter::EncodableValue(false));
    }
    return;
  }

  result->NotImplemented();
}

}  // namespace tray
