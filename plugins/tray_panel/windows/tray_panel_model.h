#ifndef FLUTTER_PLUGIN_TRAY_PANEL_MODEL_H_
#define FLUTTER_PLUGIN_TRAY_PANEL_MODEL_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace tray {

struct TrayPanelTheme {
  bool is_dark = true;
  bool pure_black = false;
  uint32_t glass_tint = 0x9E2B2929;
  uint32_t card_bg = 0xFF201F1F;
  uint32_t block_bg = 0xFF2B2929;
  uint32_t inset_bg = 0xFF1C1B1B;
  uint32_t hairline = 0x24E6E1E1;
  uint32_t primary = 0xFF007AFF;
  uint32_t on_primary = 0xFFFFFFFF;
  uint32_t on_surface = 0xFFE6E1E1;
  uint32_t on_surface_variant = 0xFFD0C4C5;
  uint32_t success = 0xFF4CAF50;
  uint32_t warning = 0xFFC57F0A;
  uint32_t error = 0xFFFFB4AB;
  uint32_t on_error = 0xFF690005;
};

struct TrayPanelLabels {
  std::wstring app_name = L"FlClash";
  std::wstring show_window = L"Show";
  std::wstring start = L"Start";
  std::wstring stop = L"Stop";
  std::wstring mode_rule = L"Rule";
  std::wstring mode_global = L"Global";
  std::wstring mode_direct = L"Direct";
  std::wstring tun = L"TUN";
  std::wstring system_proxy = L"System Proxy";
  std::wstring speed_statistics = L"Speed";
  std::wstring monochrome_icon = L"Monochrome Icon";
  std::wstring auto_launch = L"Auto Launch";
  std::wstring proxies = L"Proxies";
  std::wstring search = L"Search";
  std::wstring test_all_delays = L"Test all delays";
  std::wstring delay_test = L"Delay test";
  std::wstring timeout = L"Timeout";
  std::wstring delay_failed = L"Failed";
  std::wstring copy_env_var = L"Copy env var";
  std::wstring exit = L"Exit";
  std::wstring no_proxies = L"No proxies";
  std::wstring safe_mode = L"Safe Mode";
};

struct TrayPanelShortcuts {
  std::wstring show_window;
  std::wstring toggle_running;
  std::wstring mode_rule;
  std::wstring mode_global;
  std::wstring mode_direct;
  std::wstring test_all_delays;
  std::wstring tun;
  std::wstring system_proxy;
  std::wstring copy_env;
  std::wstring exit;
};

struct TrayPanelProxy {
  std::string name_utf8;
  std::wstring name;
  std::wstring name_lower;
  std::wstring type;
  std::wstring type_lower;
  std::optional<int> delay;
  bool testing = false;
  bool selected = false;
};

struct TrayPanelGroup {
  std::string name_utf8;
  std::wstring name;
  std::wstring name_lower;
  std::wstring type;
  std::wstring selected_proxy_name;
  std::optional<int> selected_delay;
  bool testing = false;
  std::vector<TrayPanelProxy> proxies;
};

struct TrayPanelState {
  bool is_start = false;
  bool suspended = false;
  bool safe_mode = false;
  std::string mode = "rule";
  bool tun_enable = false;
  bool system_proxy = false;
  bool show_tray_title = false;
  bool monochrome_tray_icon = false;
  bool auto_launch = false;
  bool show_macos_toggles = false;
  int port = 7890;
  bool testing_all = false;
  TrayPanelTheme theme;
  TrayPanelLabels labels;
  TrayPanelShortcuts shortcuts;
  std::vector<TrayPanelGroup> groups;
};

struct TrayPanelTraffic {
  std::wstring up = L"0 B/s";
  std::wstring down = L"0 B/s";
};

std::wstring Utf16FromUtf8(const std::string& value);
std::wstring LowercaseWide(const std::wstring& value);

bool DecodePanelState(const flutter::EncodableMap& map, TrayPanelState* out);
bool DecodePanelTraffic(const flutter::EncodableMap& map,
                        TrayPanelTraffic* out);

}  // namespace tray

#endif  // FLUTTER_PLUGIN_TRAY_PANEL_MODEL_H_
