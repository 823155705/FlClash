#include "tray_panel_model.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <utility>
#include <variant>

namespace tray {

namespace {

const flutter::EncodableValue* ValueAt(const flutter::EncodableMap& map,
                                       const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &(it->second);
}

const std::string* StringAt(const flutter::EncodableMap& map, const char* key) {
  return std::get_if<std::string>(ValueAt(map, key));
}

bool BoolAt(const flutter::EncodableMap& map, const char* key, bool fallback) {
  const auto* value = std::get_if<bool>(ValueAt(map, key));
  return value == nullptr ? fallback : *value;
}

std::optional<int64_t> Int64At(const flutter::EncodableMap& map,
                               const char* key) {
  const auto* value = ValueAt(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* v32 = std::get_if<int32_t>(value)) {
    return static_cast<int64_t>(*v32);
  }
  if (const auto* v64 = std::get_if<int64_t>(value)) {
    return *v64;
  }
  return std::nullopt;
}

int IntAt(const flutter::EncodableMap& map, const char* key, int fallback) {
  const auto value = Int64At(map, key);
  return value.has_value() ? static_cast<int>(*value) : fallback;
}

uint32_t Uint32At(const flutter::EncodableMap& map,
                  const char* key,
                  uint32_t fallback) {
  const auto value = Int64At(map, key);
  return value.has_value() ? static_cast<uint32_t>(*value) : fallback;
}

const flutter::EncodableMap* MapAt(const flutter::EncodableMap& map,
                                   const char* key) {
  return std::get_if<flutter::EncodableMap>(ValueAt(map, key));
}

const flutter::EncodableList* ListAt(const flutter::EncodableMap& map,
                                     const char* key) {
  return std::get_if<flutter::EncodableList>(ValueAt(map, key));
}

void AssignWide(const flutter::EncodableMap& map,
                const char* key,
                std::wstring* target) {
  if (const auto* text = StringAt(map, key)) {
    *target = Utf16FromUtf8(*text);
  }
}

void DecodeTheme(const flutter::EncodableMap& map, TrayPanelTheme* out) {
  out->is_dark = BoolAt(map, "isDark", out->is_dark);
  out->pure_black = BoolAt(map, "pureBlack", out->pure_black);
  out->glass_tint = Uint32At(map, "glassTint", out->glass_tint);
  out->card_bg = Uint32At(map, "cardBg", out->card_bg);
  out->block_bg = Uint32At(map, "blockBg", out->block_bg);
  out->inset_bg = Uint32At(map, "insetBg", out->inset_bg);
  out->hairline = Uint32At(map, "hairline", out->hairline);
  out->primary = Uint32At(map, "primary", out->primary);
  out->on_primary = Uint32At(map, "onPrimary", out->on_primary);
  out->on_surface = Uint32At(map, "onSurface", out->on_surface);
  out->on_surface_variant =
      Uint32At(map, "onSurfaceVariant", out->on_surface_variant);
  out->success = Uint32At(map, "success", out->success);
  out->warning = Uint32At(map, "warning", out->warning);
  out->error = Uint32At(map, "error", out->error);
  out->on_error = Uint32At(map, "onError", out->on_error);
}

void DecodeLabels(const flutter::EncodableMap& map, TrayPanelLabels* out) {
  AssignWide(map, "appName", &out->app_name);
  AssignWide(map, "showWindow", &out->show_window);
  AssignWide(map, "start", &out->start);
  AssignWide(map, "stop", &out->stop);
  AssignWide(map, "modeRule", &out->mode_rule);
  AssignWide(map, "modeGlobal", &out->mode_global);
  AssignWide(map, "modeDirect", &out->mode_direct);
  AssignWide(map, "tun", &out->tun);
  AssignWide(map, "systemProxy", &out->system_proxy);
  AssignWide(map, "speedStatistics", &out->speed_statistics);
  AssignWide(map, "monochromeIcon", &out->monochrome_icon);
  AssignWide(map, "autoLaunch", &out->auto_launch);
  AssignWide(map, "proxies", &out->proxies);
  AssignWide(map, "search", &out->search);
  AssignWide(map, "testAllDelays", &out->test_all_delays);
  AssignWide(map, "delayTest", &out->delay_test);
  AssignWide(map, "timeout", &out->timeout);
  AssignWide(map, "delayFailed", &out->delay_failed);
  AssignWide(map, "copyEnvVar", &out->copy_env_var);
  AssignWide(map, "exit", &out->exit);
  AssignWide(map, "noProxies", &out->no_proxies);
  AssignWide(map, "safeMode", &out->safe_mode);
}

void DecodeShortcuts(const flutter::EncodableMap& map,
                     TrayPanelShortcuts* out) {
  AssignWide(map, "showWindow", &out->show_window);
  AssignWide(map, "toggleRunning", &out->toggle_running);
  AssignWide(map, "modeRule", &out->mode_rule);
  AssignWide(map, "modeGlobal", &out->mode_global);
  AssignWide(map, "modeDirect", &out->mode_direct);
  AssignWide(map, "testAllDelays", &out->test_all_delays);
  AssignWide(map, "tun", &out->tun);
  AssignWide(map, "systemProxy", &out->system_proxy);
  AssignWide(map, "copyEnv", &out->copy_env);
  AssignWide(map, "exit", &out->exit);
}

TrayPanelProxy DecodeProxy(const flutter::EncodableMap& map) {
  TrayPanelProxy proxy;
  if (const auto* name = StringAt(map, "name")) {
    proxy.name_utf8 = *name;
    proxy.name = Utf16FromUtf8(*name);
    proxy.name_lower = LowercaseWide(proxy.name);
  }
  if (const auto* type = StringAt(map, "type")) {
    proxy.type = Utf16FromUtf8(*type);
    proxy.type_lower = LowercaseWide(proxy.type);
  }
  if (const auto delay = Int64At(map, "delay")) {
    proxy.delay = static_cast<int>(*delay);
  }
  proxy.testing = BoolAt(map, "testing", false);
  proxy.selected = BoolAt(map, "selected", false);
  return proxy;
}

TrayPanelGroup DecodeGroup(const flutter::EncodableMap& map) {
  TrayPanelGroup group;
  if (const auto* name = StringAt(map, "name")) {
    group.name_utf8 = *name;
    group.name = Utf16FromUtf8(*name);
    group.name_lower = LowercaseWide(group.name);
  }
  AssignWide(map, "type", &group.type);
  AssignWide(map, "selectedProxyName", &group.selected_proxy_name);
  if (const auto delay = Int64At(map, "selectedDelay")) {
    group.selected_delay = static_cast<int>(*delay);
  }
  group.testing = BoolAt(map, "testing", false);
  if (const auto* proxies = ListAt(map, "proxies")) {
    group.proxies.reserve(proxies->size());
    for (const auto& item : *proxies) {
      if (const auto* entry = std::get_if<flutter::EncodableMap>(&item)) {
        group.proxies.push_back(DecodeProxy(*entry));
      }
    }
  }
  return group;
}

}  // namespace

std::wstring Utf16FromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::wstring LowercaseWide(const std::wstring& value) {
  if (value.empty()) {
    return std::wstring();
  }
  std::wstring lowered = value;
  ::CharLowerBuffW(lowered.data(), static_cast<DWORD>(lowered.size()));
  return lowered;
}

bool DecodePanelState(const flutter::EncodableMap& map, TrayPanelState* out) {
  if (out == nullptr) {
    return false;
  }
  TrayPanelState next;
  next.is_start = BoolAt(map, "isStart", false);
  next.suspended = BoolAt(map, "suspended", false);
  next.safe_mode = BoolAt(map, "safeMode", false);
  if (const auto* mode = StringAt(map, "mode")) {
    next.mode = *mode;
  }
  next.tun_enable = BoolAt(map, "tunEnable", false);
  next.system_proxy = BoolAt(map, "systemProxy", false);
  next.show_tray_title = BoolAt(map, "showTrayTitle", false);
  next.monochrome_tray_icon = BoolAt(map, "monochromeTrayIcon", false);
  next.auto_launch = BoolAt(map, "autoLaunch", false);
  next.show_macos_toggles = BoolAt(map, "showMacOSToggles", false);
  next.port = IntAt(map, "port", 7890);
  next.testing_all = BoolAt(map, "testingAll", false);
  if (const auto* theme = MapAt(map, "theme")) {
    DecodeTheme(*theme, &next.theme);
  }
  if (const auto* labels = MapAt(map, "labels")) {
    DecodeLabels(*labels, &next.labels);
  }
  if (const auto* shortcuts = MapAt(map, "shortcuts")) {
    DecodeShortcuts(*shortcuts, &next.shortcuts);
  }
  if (const auto* groups = ListAt(map, "groups")) {
    next.groups.reserve(groups->size());
    for (const auto& item : *groups) {
      if (const auto* entry = std::get_if<flutter::EncodableMap>(&item)) {
        next.groups.push_back(DecodeGroup(*entry));
      }
    }
  }
  *out = std::move(next);
  return true;
}

bool DecodePanelTraffic(const flutter::EncodableMap& map,
                        TrayPanelTraffic* out) {
  if (out == nullptr) {
    return false;
  }
  TrayPanelTraffic next;
  AssignWide(map, "up", &next.up);
  AssignWide(map, "down", &next.down);
  *out = std::move(next);
  return true;
}

}  // namespace tray
