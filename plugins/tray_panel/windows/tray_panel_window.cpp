#include "tray_panel_window.h"

#include <dwmapi.h>
#include <strsafe.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <utility>

namespace tray {

namespace {

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1
#define DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1 19
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

constexpr int kDwmCornerRound = 2;
constexpr int kDwmBackdropNone = 1;
constexpr int kDwmBackdropTransient = 3;
constexpr int kAccentAcrylicBlurBehind = 4;

constexpr wchar_t kPanelClassName[] = L"FLCLASH_TRAY_PANEL_WINDOW";
constexpr float kPanelWidthDip = 348.0f;
constexpr float kOuterPadDip = 14.0f;
constexpr float kInnerWidthDip = kPanelWidthDip - 2.0f * kOuterPadDip;
constexpr float kSectionGapDip = 10.0f;
constexpr float kMaxPanelHeightDip = 600.0f;
constexpr float kWorkMarginDip = 8.0f;
constexpr float kAnchorGapDip = 8.0f;
constexpr float kFooterOffsetFromBottomDip = 42.0f;
constexpr float kDividerOffsetFromBottomDip = 53.0f;

constexpr UINT_PTR kSpinnerTimerId = 1;
constexpr UINT_PTR kCopyFeedbackTimerId = 2;
constexpr UINT_PTR kCaretTimerId = 3;
constexpr UINT_PTR kAnimTimerId = 4;
constexpr UINT kSpinnerIntervalMs = 33;
constexpr UINT kCopyFeedbackDurationMs = 1500;
constexpr UINT kCaretBlinkMs = 530;
constexpr UINT kAnimIntervalMs = 15;
constexpr ULONGLONG kModeAnimDurationMs = 175;
constexpr ULONGLONG kLayoutAnimDurationMs = 175;
constexpr ULONGLONG kToggleGuardMs = 400;
constexpr float kPi = 3.14159265f;

struct AccentPolicy {
  int accent_state;
  int accent_flags;
  int gradient_color;
  int animation_id;
};

struct WindowCompositionAttributeData {
  int attribute;
  PVOID data;
  SIZE_T size_in_bytes;
};

using SetWindowCompositionAttributeFn =
    BOOL(WINAPI*)(HWND, WindowCompositionAttributeData*);
using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);

int QueryWindowsBuild() {
  static const int build = []() {
    const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    if (ntdll == nullptr) {
      return 0;
    }
    const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
        ::GetProcAddress(ntdll, "RtlGetVersion"));
    if (rtl_get_version == nullptr) {
      return 0;
    }
    OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    if (rtl_get_version(&info) != 0) {
      return 0;
    }
    return static_cast<int>(info.dwBuildNumber);
  }();
  return build;
}

SetWindowCompositionAttributeFn GetSetWindowCompositionAttribute() {
  static const auto fn = []() -> SetWindowCompositionAttributeFn {
    const HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
    return user32 == nullptr
               ? nullptr
               : reinterpret_cast<SetWindowCompositionAttributeFn>(
                     ::GetProcAddress(user32,
                                      "SetWindowCompositionAttribute"));
  }();
  return fn;
}

UINT QueryMonitorDpi(HMONITOR monitor, HWND fallback_hwnd) {
  static const auto get_dpi_for_monitor = []() -> GetDpiForMonitorFn {
    const HMODULE shcore = ::LoadLibraryExW(L"Shcore.dll", nullptr,
                                            LOAD_LIBRARY_SEARCH_SYSTEM32);
    return shcore == nullptr
               ? nullptr
               : reinterpret_cast<GetDpiForMonitorFn>(
                     ::GetProcAddress(shcore, "GetDpiForMonitor"));
  }();
  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (monitor != nullptr && get_dpi_for_monitor != nullptr &&
      SUCCEEDED(get_dpi_for_monitor(monitor, 0, &dpi_x, &dpi_y)) &&
      dpi_x > 0) {
    return dpi_x;
  }
  if (fallback_hwnd != nullptr) {
    const UINT win_dpi = ::GetDpiForWindow(fallback_hwnd);
    if (win_dpi > 0) {
      return win_dpi;
    }
  }
  return USER_DEFAULT_SCREEN_DPI;
}

uint32_t ToAbgr(uint32_t argb) {
  const uint32_t a = (argb >> 24) & 0xFFU;
  const uint32_t r = (argb >> 16) & 0xFFU;
  const uint32_t g = (argb >> 8) & 0xFFU;
  const uint32_t b = argb & 0xFFU;
  return (a << 24) | (b << 16) | (g << 8) | r;
}

uint32_t WithAlpha(uint32_t argb, float alpha) {
  const float clamped = (std::max)(0.0f, (std::min)(1.0f, alpha));
  const uint32_t a = static_cast<uint32_t>(std::lround(clamped * 255.0f));
  return (argb & 0x00FFFFFFU) | (a << 24);
}

uint32_t CompositeOver(uint32_t fg_argb, uint32_t bg_argb) {
  const float a = static_cast<float>((fg_argb >> 24) & 0xFFU) / 255.0f;
  const auto blend = [a](uint32_t fg, uint32_t bg) -> uint32_t {
    const float out = static_cast<float>(fg) * a +
                      static_cast<float>(bg) * (1.0f - a);
    return static_cast<uint32_t>(
        (std::max)(0L, (std::min)(255L, std::lround(out))));
  };
  const uint32_t r = blend((fg_argb >> 16) & 0xFFU, (bg_argb >> 16) & 0xFFU);
  const uint32_t g = blend((fg_argb >> 8) & 0xFFU, (bg_argb >> 8) & 0xFFU);
  const uint32_t b = blend(fg_argb & 0xFFU, bg_argb & 0xFFU);
  return 0xFF000000U | (r << 16) | (g << 8) | b;
}

uint64_t MakeHitKey(int kind, size_t group_index = 0, size_t proxy_index = 0) {
  return (static_cast<uint64_t>(kind) << 48) |
         ((static_cast<uint64_t>(group_index) & 0xFFFFFFULL) << 24) |
         (static_cast<uint64_t>(proxy_index) & 0xFFFFFFULL);
}

bool PointInRectF(const D2D1_RECT_F& rect, float x, float y) {
  return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
}

D2D1_RECT_F OffsetRectF(const D2D1_RECT_F& rect, float dy) {
  return D2D1::RectF(rect.left, rect.top + dy, rect.right, rect.bottom + dy);
}

float Clamp01(float t) {
  return (std::max)(0.0f, (std::min)(1.0f, t));
}

float EaseOutCubic(float t) {
  const float u = 1.0f - Clamp01(t);
  return 1.0f - u * u * u;
}

uint32_t LerpArgb(uint32_t from_argb, uint32_t to_argb, float t) {
  const float s = Clamp01(t);
  const auto lerp_ch = [s](uint32_t a, uint32_t b) -> uint32_t {
    const float v = static_cast<float>(a) +
                    (static_cast<float>(b) - static_cast<float>(a)) * s;
    return static_cast<uint32_t>(
        (std::max)(0L, (std::min)(255L, std::lround(v))));
  };
  const uint32_t a = lerp_ch((from_argb >> 24) & 0xFFU, (to_argb >> 24) & 0xFFU);
  const uint32_t r = lerp_ch((from_argb >> 16) & 0xFFU, (to_argb >> 16) & 0xFFU);
  const uint32_t g = lerp_ch((from_argb >> 8) & 0xFFU, (to_argb >> 8) & 0xFFU);
  const uint32_t b = lerp_ch(from_argb & 0xFFU, to_argb & 0xFFU);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

D2D1_RECT_F LerpRectF(const D2D1_RECT_F& a, const D2D1_RECT_F& b, float t) {
  const float s = Clamp01(t);
  return D2D1::RectF(a.left + (b.left - a.left) * s,
                     a.top + (b.top - a.top) * s,
                     a.right + (b.right - a.right) * s,
                     a.bottom + (b.bottom - a.bottom) * s);
}

float RectHorizontalOverlapRatio(const D2D1_RECT_F& pill,
                                 const D2D1_RECT_F& seg) {
  const float seg_w = seg.right - seg.left;
  if (seg_w <= 0.0f) {
    return 0.0f;
  }
  const float overlap =
      (std::max)(0.0f, (std::min)(pill.right, seg.right) -
                           (std::max)(pill.left, seg.left));
  return Clamp01(overlap / seg_w);
}

int ModeIndexFromString(const std::string& mode) {
  if (mode == "global") {
    return 1;
  }
  if (mode == "direct") {
    return 2;
  }
  return 0;
}

std::wstring FormatDelayText(int delay,
                             const TrayPanelLabels& labels,
                             bool include_unit) {
  if (delay == -1) {
    return labels.timeout;
  }
  if (delay < -1) {
    return labels.delay_failed;
  }
  wchar_t buf[32]{};
  if (include_unit) {
    ::StringCchPrintfW(buf, ARRAYSIZE(buf), L"%d ms", delay);
  } else {
    ::StringCchPrintfW(buf, ARRAYSIZE(buf), L"%d", delay);
  }
  return std::wstring(buf);
}

uint32_t DelayColor(int delay, const TrayPanelTheme& theme) {
  if (delay < 0) {
    return theme.error;
  }
  if (delay < 600) {
    return theme.success;
  }
  return theme.warning;
}

bool IsWindowTrayShell(HWND hwnd) {
  if (hwnd == nullptr) {
    return false;
  }
  wchar_t cls[64]{};
  const int len = ::GetClassNameW(hwnd, cls, ARRAYSIZE(cls));
  if (len <= 0) {
    return false;
  }
  return ::lstrcmpW(cls, L"Shell_TrayWnd") == 0 ||
         ::lstrcmpW(cls, L"Shell_SecondaryTrayWnd") == 0 ||
         ::lstrcmpW(cls, L"NotifyIconOverflowWindow") == 0 ||
         ::lstrcmpW(cls, L"TopLevelWindowForOverflowXamlIsland") == 0;
}

}  // namespace

TrayPanelWindow::TrayPanelWindow(VisibilityCallback on_visibility_changed,
                                 ActionCallback on_action)
    : on_visibility_changed_(std::move(on_visibility_changed)),
      on_action_(std::move(on_action)) {}

TrayPanelWindow::~TrayPanelWindow() { Destroy(); }

void TrayPanelWindow::SetOwner(HWND owner_hwnd, UINT tray_icon_id) {
  owner_hwnd_ = owner_hwnd;
  tray_icon_id_ = tray_icon_id;
}

bool TrayPanelWindow::SetState(const TrayPanelState& state) {
  const bool was_ready = has_state_ && is_visible_;
  const std::string prev_mode = state_.mode;
  const float prev_height_dip = layout_.panel_height_dip;
  const bool prev_groups_empty = state_.groups.empty();
  const ULONGLONG now = ::GetTickCount64();

  if (was_ready) {
    StepAnimationsAt(now);
    const bool mode_changed = state.mode != prev_mode;
    const bool groups_toggled = state.groups.empty() != prev_groups_empty;
    if ((mode_changed || groups_toggled) && !prev_groups_empty) {
      outgoing_proxies_.valid = true;
      outgoing_proxies_.search_visible = search_visible_;
      outgoing_proxies_.testing_all = state_.testing_all;
      outgoing_proxies_.search_query = search_query_;
      outgoing_proxies_.groups = std::move(state_.groups);
      outgoing_proxies_.filtered_groups = std::move(filtered_groups_);
      outgoing_proxies_.layout = layout_;
      outgoing_proxies_.scroll_offset_dip = scroll_offset_dip_;
    } else if (mode_changed || groups_toggled) {
      outgoing_proxies_.Reset();
    }
  }

  state_ = state;
  has_state_ = true;

  std::set<std::string> valid_groups;
  for (const auto& group : state_.groups) {
    valid_groups.insert(group.name_utf8);
  }
  for (auto it = expanded_groups_.begin(); it != expanded_groups_.end();) {
    if (valid_groups.find(*it) == valid_groups.end()) {
      it = expanded_groups_.erase(it);
    } else {
      ++it;
    }
  }

  RebuildFilteredGroups();
  RebuildLayout();
  ClampScroll();

  if (!was_ready) {
    SnapAnimationsToCurrentState();
  } else {
    const D2D1_RECT_F target_pill = ModeSegmentRect(state_.mode);
    if (state_.mode != prev_mode) {
      if (last_mode_.empty()) {
        pill_current_rect_ = target_pill;
        mode_anim_active_ = false;
      } else {
        mode_anim_from_rect_ = pill_current_rect_;
        mode_anim_to_rect_ = target_pill;
        mode_anim_start_tick_ = now;
        mode_anim_active_ = true;
      }
      last_mode_ = state_.mode;
    } else if (mode_anim_active_) {
      mode_anim_to_rect_ = target_pill;
    } else {
      pill_current_rect_ = target_pill;
    }

    StartHeightAnimationIfNeeded(prev_height_dip);

    if ((state_.mode != prev_mode ||
         state_.groups.empty() != prev_groups_empty) &&
        (!prev_groups_empty || !state_.groups.empty())) {
      proxies_anim_start_tick_ = now;
      proxies_anim_progress_ = 0.0f;
      proxies_anim_active_ = true;
    }
  }

  UpdateWindowSizeIfVisible();
  SyncTimers();
  if (is_visible_ && hwnd_ != nullptr) {
    ApplyBackdropAndTheme();
    ::InvalidateRect(hwnd_, nullptr, FALSE);
  }
  return true;
}

void TrayPanelWindow::SetTraffic(const TrayPanelTraffic& traffic) {
  traffic_ = traffic;
  if (is_visible_ && hwnd_ != nullptr) {
    ::InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void TrayPanelWindow::NoteTrayIconPointerDown() {
  if (is_visible_ ||
      (deactivated_on_tray_icon_ &&
       (::GetTickCount64() - last_deactivate_tick_ <= kToggleGuardMs))) {
    suppress_toggle_until_tick_ = ::GetTickCount64() + kToggleGuardMs;
  }
}

bool TrayPanelWindow::Open() {
  if (!has_state_) {
    return false;
  }
  if (!EnsureWindowCreated() || !EnsureFactories()) {
    return false;
  }

  suppress_toggle_until_tick_ = 0;
  deactivated_on_tray_icon_ = false;

  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
  ComputeWindowBounds(true, &x, &y, &w, &h);
  RebuildLayout();
  ClampScroll();
  SnapAnimationsToCurrentState();
  ComputeWindowBounds(true, &x, &y, &w, &h);
  ApplyBackdropAndTheme();

  ::SetWindowPos(hwnd_, HWND_TOPMOST, x, y, w, h,
                 SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
  ::SetForegroundWindow(hwnd_);
  ::SetFocus(hwnd_);

  const bool was_visible = is_visible_;
  is_visible_ = true;
  SyncTimers();
  ::InvalidateRect(hwnd_, nullptr, FALSE);
  if (!was_visible && on_visibility_changed_) {
    on_visibility_changed_(true);
  }
  return true;
}

bool TrayPanelWindow::Close() {
  HideInternal(true, false);
  return true;
}

bool TrayPanelWindow::Toggle() {
  if (is_visible_) {
    HideInternal(true, false);
    return true;
  }
  const ULONGLONG now = ::GetTickCount64();
  if (suppress_toggle_until_tick_ >= now ||
      (deactivated_on_tray_icon_ &&
       now - last_deactivate_tick_ <= kToggleGuardMs)) {
    suppress_toggle_until_tick_ = 0;
    deactivated_on_tray_icon_ = false;
    return true;
  }
  return Open();
}

void TrayPanelWindow::Destroy() {
  HideInternal(false, false);
  DiscardRenderResources();
  if (hwnd_ != nullptr) {
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (class_registered_) {
    ::UnregisterClassW(kPanelClassName, ::GetModuleHandleW(nullptr));
    class_registered_ = false;
  }
  expanded_groups_.clear();
  search_visible_ = false;
  search_query_.clear();
  scroll_offset_dip_ = 0.0f;
  has_state_ = false;
  last_mode_.clear();
  CancelAnimations();
}

bool TrayPanelWindow::EnsureWindowCreated() {
  if (hwnd_ != nullptr && ::IsWindow(hwnd_)) {
    return true;
  }
  const HINSTANCE instance = ::GetModuleHandleW(nullptr);
  if (!class_registered_) {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(WNDCLASSEXW);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = TrayPanelWindow::WindowProc;
    wc.hInstance = instance;
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kPanelClassName;
    if (::RegisterClassExW(&wc) == 0 &&
        ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return false;
    }
    class_registered_ = true;
  }

  hwnd_ = ::CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kPanelClassName, L"",
      WS_POPUP | WS_CLIPCHILDREN, 0, 0, PxFromDip(kPanelWidthDip),
      PxFromDip(layout_.panel_height_dip), nullptr, nullptr, instance, this);
  if (hwnd_ == nullptr) {
    return false;
  }
  dpi_ = QueryMonitorDpi(nullptr, hwnd_);
  return true;
}

bool TrayPanelWindow::EnsureFactories() {
  if (!d2d_factory_) {
    if (FAILED(::D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), nullptr,
            reinterpret_cast<void**>(d2d_factory_.GetAddressOf())))) {
      return false;
    }
  }
  if (!dwrite_factory_) {
    if (FAILED(::DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown**>(dwrite_factory_.GetAddressOf())))) {
      return false;
    }
  }
  if (!fmt_title_) {
    std::wstring family = L"Segoe UI";
    ComPtr<IDWriteFontCollection> collection;
    if (SUCCEEDED(dwrite_factory_->GetSystemFontCollection(
            collection.GetAddressOf()))) {
      UINT32 index = 0;
      BOOL exists = FALSE;
      if (SUCCEEDED(collection->FindFamilyName(L"Segoe UI Variable Text",
                                               &index, &exists)) &&
          exists) {
        family = L"Segoe UI Variable Text";
      }
    }

    const auto make_fmt = [&](float size,
                              DWRITE_FONT_WEIGHT weight,
                              DWRITE_TEXT_ALIGNMENT h_align,
                              ComPtr<IDWriteTextFormat>* out) -> bool {
      if (FAILED(dwrite_factory_->CreateTextFormat(
              family.c_str(), nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
              DWRITE_FONT_STRETCH_NORMAL, size, L"", out->GetAddressOf()))) {
        return false;
      }
      (*out)->SetTextAlignment(h_align);
      (*out)->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
      (*out)->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
      if (ellipsis_trimming_) {
        DWRITE_TRIMMING trimming{DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
        (*out)->SetTrimming(&trimming, ellipsis_trimming_.Get());
      }
      return true;
    };

    ComPtr<IDWriteTextFormat> base_fmt;
    if (SUCCEEDED(dwrite_factory_->CreateTextFormat(
            family.c_str(), nullptr, DWRITE_FONT_WEIGHT_NORMAL,
            DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, 12.0f, L"",
            base_fmt.GetAddressOf()))) {
      dwrite_factory_->CreateEllipsisTrimmingSign(
          base_fmt.Get(), ellipsis_trimming_.GetAddressOf());
    }

    if (!make_fmt(14.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_title_) ||
        !make_fmt(12.5f, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_group_) ||
        !make_fmt(11.5f, DWRITE_FONT_WEIGHT_NORMAL,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_body_) ||
        !make_fmt(11.5f, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_body_semibold_) ||
        !make_fmt(10.5f, DWRITE_FONT_WEIGHT_NORMAL,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_small_) ||
        !make_fmt(10.5f, DWRITE_FONT_WEIGHT_MEDIUM,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_small_medium_) ||
        !make_fmt(9.5f, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                  DWRITE_TEXT_ALIGNMENT_LEADING, &fmt_badge_) ||
        !make_fmt(10.5f, DWRITE_FONT_WEIGHT_SEMI_BOLD,
                  DWRITE_TEXT_ALIGNMENT_CENTER, &fmt_badge_center_)) {
      return false;
    }
  }
  return true;
}

bool TrayPanelWindow::EnsureRenderTarget() {
  if (!EnsureFactories() || hwnd_ == nullptr) {
    return false;
  }
  RECT client{};
  ::GetClientRect(hwnd_, &client);
  const UINT width =
      static_cast<UINT>((std::max)(1L, client.right - client.left));
  const UINT height =
      static_cast<UINT>((std::max)(1L, client.bottom - client.top));

  if (!render_target_) {
    const D2D1_RENDER_TARGET_PROPERTIES rt_props =
        D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                              D2D1_ALPHA_MODE_PREMULTIPLIED),
            static_cast<float>(dpi_), static_cast<float>(dpi_));
    const D2D1_HWND_RENDER_TARGET_PROPERTIES hwnd_props =
        D2D1::HwndRenderTargetProperties(hwnd_, D2D1::SizeU(width, height));
    if (FAILED(d2d_factory_->CreateHwndRenderTarget(
            rt_props, hwnd_props, render_target_.GetAddressOf()))) {
      return false;
    }
    render_target_->SetDpi(static_cast<float>(dpi_), static_cast<float>(dpi_));
    if (FAILED(render_target_->CreateSolidColorBrush(
            D2D1::ColorF(0, 0, 0, 1), brush_.GetAddressOf()))) {
      render_target_.Reset();
      return false;
    }
  } else {
    const D2D1_SIZE_U current = render_target_->GetPixelSize();
    if (current.width != width || current.height != height) {
      render_target_->Resize(D2D1::SizeU(width, height));
    }
  }
  return true;
}

void TrayPanelWindow::DiscardRenderResources() {
  brush_.Reset();
  render_target_.Reset();
}

void TrayPanelWindow::ApplyBackdropAndTheme() {
  if (hwnd_ == nullptr) {
    return;
  }
  const int build = QueryWindowsBuild();
  const MARGINS margins{-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(hwnd_, &margins);

  if (build >= 17763) {
    const BOOL dark = state_.theme.is_dark ? TRUE : FALSE;
    const DWORD attr = build >= 18985
                           ? DWMWA_USE_IMMERSIVE_DARK_MODE
                           : DWMWA_USE_IMMERSIVE_DARK_MODE_BEFORE_20H1;
    ::DwmSetWindowAttribute(hwnd_, attr, &dark, sizeof(dark));
  }

  if (build >= 22000) {
    const int corner = kDwmCornerRound;
    ::DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                            sizeof(corner));
  }

  if (build >= 22621) {
    const int backdrop =
        state_.theme.pure_black ? kDwmBackdropNone : kDwmBackdropTransient;
    ::DwmSetWindowAttribute(hwnd_, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop,
                            sizeof(backdrop));
  } else if (build >= 17134) {
    if (const auto set_attr = GetSetWindowCompositionAttribute();
        set_attr != nullptr) {
      AccentPolicy policy{
          state_.theme.pure_black ? 0 : kAccentAcrylicBlurBehind, 2,
          static_cast<int>(ToAbgr(state_.theme.glass_tint)), 0};
      WindowCompositionAttributeData data{19, &policy, sizeof(policy)};
      set_attr(hwnd_, &data);
    }
  }
}

void TrayPanelWindow::UpdateDpiForRect(const RECT& anchor_rect) {
  const HMONITOR monitor =
      ::MonitorFromRect(&anchor_rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(MONITORINFO);
  ::GetMonitorInfoW(monitor, &mi);
  const UINT next_dpi = QueryMonitorDpi(monitor, owner_hwnd_);
  if (next_dpi > 0) {
    dpi_ = next_dpi;
  }
  if (render_target_) {
    render_target_->SetDpi(static_cast<float>(dpi_), static_cast<float>(dpi_));
  }
  const float work_px_h = static_cast<float>(mi.rcWork.bottom - mi.rcWork.top);
  work_height_dip_ = work_px_h * 96.0f / static_cast<float>(dpi_);
}

void TrayPanelWindow::ComputeWindowBounds(bool reposition,
                                          int* out_x,
                                          int* out_y,
                                          int* out_w,
                                          int* out_h) {
  RECT icon_rect{};
  if (reposition) {
    NOTIFYICONIDENTIFIER nii{};
    nii.cbSize = sizeof(NOTIFYICONIDENTIFIER);
    nii.hWnd = owner_hwnd_;
    nii.uID = tray_icon_id_;
    if (SUCCEEDED(::Shell_NotifyIconGetRect(&nii, &icon_rect))) {
      last_icon_rect_ = icon_rect;
      has_last_icon_rect_ = true;
    } else {
      POINT cursor{};
      ::GetCursorPos(&cursor);
      icon_rect = {cursor.x, cursor.y, cursor.x + 1, cursor.y + 1};
    }
  } else if (has_last_icon_rect_) {
    icon_rect = last_icon_rect_;
  } else {
    RECT current{};
    ::GetWindowRect(hwnd_, &current);
    icon_rect = current;
  }

  UpdateDpiForRect(icon_rect);
  const HMONITOR monitor =
      ::MonitorFromRect(&icon_rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(MONITORINFO);
  ::GetMonitorInfoW(monitor, &mi);

  const int width = PxFromDip(kPanelWidthDip);
  const int height = PxFromDip(CurrentPanelHeightDip());
  const int gap = PxFromDip(kAnchorGapDip);
  const int margin = PxFromDip(kWorkMarginDip);

  int x = 0;
  int y = 0;
  if (!reposition && hwnd_ != nullptr && ::IsWindowVisible(hwnd_)) {
    RECT cur{};
    ::GetWindowRect(hwnd_, &cur);
    x = cur.left;
    y = anchor_bottom_ ? (cur.bottom - height) : cur.top;
  } else if (icon_rect.top >= mi.rcWork.bottom) {
    x = (icon_rect.left + icon_rect.right - width) / 2;
    y = (std::min)(icon_rect.top, mi.rcWork.bottom) - gap - height;
    anchor_bottom_ = true;
  } else if (icon_rect.bottom <= mi.rcWork.top) {
    x = (icon_rect.left + icon_rect.right - width) / 2;
    y = (std::max)(icon_rect.bottom, mi.rcWork.top) + gap;
    anchor_bottom_ = false;
  } else if (icon_rect.right <= mi.rcWork.left) {
    x = (std::max)(icon_rect.right, mi.rcWork.left) + gap;
    y = (icon_rect.top + icon_rect.bottom - height) / 2;
    anchor_bottom_ =
        (icon_rect.top + icon_rect.bottom) > (mi.rcWork.top + mi.rcWork.bottom);
  } else if (icon_rect.left >= mi.rcWork.right) {
    x = (std::min)(icon_rect.left, mi.rcWork.right) - gap - width;
    y = (icon_rect.top + icon_rect.bottom - height) / 2;
    anchor_bottom_ =
        (icon_rect.top + icon_rect.bottom) > (mi.rcWork.top + mi.rcWork.bottom);
  } else {
    x = icon_rect.left - width / 2;
    y = icon_rect.top - gap - height;
    anchor_bottom_ = true;
    if (y < mi.rcWork.top + margin) {
      y = icon_rect.bottom + gap;
      anchor_bottom_ = false;
    }
  }

  const int min_x = mi.rcWork.left + margin;
  const int max_x =
      (std::max)(min_x, static_cast<int>(mi.rcWork.right) - margin - width);
  const int min_y = mi.rcWork.top + margin;
  const int max_y =
      (std::max)(min_y, static_cast<int>(mi.rcWork.bottom) - margin - height);
  x = (std::max)(min_x, (std::min)(max_x, x));
  y = (std::max)(min_y, (std::min)(max_y, y));

  *out_x = x;
  *out_y = y;
  *out_w = width;
  *out_h = height;
}

void TrayPanelWindow::UpdateWindowSizeIfVisible() {
  if (!is_visible_ || hwnd_ == nullptr) {
    return;
  }
  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
  ComputeWindowBounds(false, &x, &y, &w, &h);
  RECT cur{};
  if (::GetWindowRect(hwnd_, &cur)) {
    if (cur.left == x && cur.top == y && (cur.right - cur.left) == w &&
        (cur.bottom - cur.top) == h) {
      return;
    }
  }
  ::SetWindowPos(hwnd_, nullptr, x, y, w, h,
                 SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE);
}

void TrayPanelWindow::HideInternal(bool notify, bool from_deactivate) {
  const bool was_visible = is_visible_;
  if (from_deactivate && was_visible) {
    last_deactivate_tick_ = ::GetTickCount64();
    POINT cursor{};
    ::GetCursorPos(&cursor);
    bool on_icon = false;
    if (has_last_icon_rect_) {
      const int pad = PxFromDip(6.0f);
      RECT padded = last_icon_rect_;
      ::InflateRect(&padded, pad, pad);
      on_icon = ::PtInRect(&padded, cursor) != FALSE;
    }
    deactivated_on_tray_icon_ =
        on_icon || IsWindowTrayShell(::GetForegroundWindow());
  }
  is_visible_ = false;
  hovered_key_ = 0;
  pressed_key_ = 0;
  tracking_mouse_ = false;
  copied_feedback_ = false;
  CancelAnimations();
  if (hwnd_ != nullptr && ::IsWindow(hwnd_)) {
    ::KillTimer(hwnd_, kSpinnerTimerId);
    ::KillTimer(hwnd_, kCopyFeedbackTimerId);
    ::KillTimer(hwnd_, kCaretTimerId);
    ::KillTimer(hwnd_, kAnimTimerId);
    ::ShowWindow(hwnd_, SW_HIDE);
  }
  anim_timer_running_ = false;
  if (was_visible && notify && on_visibility_changed_) {
    on_visibility_changed_(false);
  }
}

void TrayPanelWindow::SyncTimers() {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  if (!is_visible_) {
    ::KillTimer(hwnd_, kSpinnerTimerId);
    ::KillTimer(hwnd_, kCaretTimerId);
    ::KillTimer(hwnd_, kAnimTimerId);
    anim_timer_running_ = false;
    return;
  }

  bool any_testing = state_.testing_all;
  if (!any_testing) {
    for (const auto& group : state_.groups) {
      if (group.testing) {
        any_testing = true;
        break;
      }
      for (const auto& proxy : group.proxies) {
        if (proxy.testing) {
          any_testing = true;
          break;
        }
      }
      if (any_testing) {
        break;
      }
    }
  }
  if (any_testing) {
    ::SetTimer(hwnd_, kSpinnerTimerId, kSpinnerIntervalMs, nullptr);
  } else {
    ::KillTimer(hwnd_, kSpinnerTimerId);
  }

  if (search_visible_) {
    ::SetTimer(hwnd_, kCaretTimerId, kCaretBlinkMs, nullptr);
  } else {
    ::KillTimer(hwnd_, kCaretTimerId);
  }

  const bool need_anim = HasActiveAnimations();
  if (need_anim && !anim_timer_running_) {
    if (::SetTimer(hwnd_, kAnimTimerId, kAnimIntervalMs, nullptr) != 0) {
      anim_timer_running_ = true;
    }
  } else if (!need_anim && anim_timer_running_) {
    ::KillTimer(hwnd_, kAnimTimerId);
    anim_timer_running_ = false;
  }
}

void TrayPanelWindow::ApplyLocalLayoutChange(bool sync_timers) {
  const float prev_height_dip = layout_.panel_height_dip;
  RebuildFilteredGroups();
  RebuildLayout();
  ClampScroll();
  if (is_visible_) {
    StartHeightAnimationIfNeeded(prev_height_dip);
  } else {
    SnapAnimationsToCurrentState();
  }
  UpdateWindowSizeIfVisible();
  if (sync_timers || HasActiveAnimations()) {
    SyncTimers();
  }
  if (hwnd_ != nullptr) {
    ::InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void TrayPanelWindow::StartHeightAnimationIfNeeded(float prev_height_dip) {
  const ULONGLONG now = ::GetTickCount64();
  StepAnimationsAt(now);
  const float current_dip =
      height_anim_active_ ? anim_current_height_dip_ : prev_height_dip;
  if (std::fabs(layout_.panel_height_dip - current_dip) < 0.5f) {
    height_anim_active_ = false;
    anim_start_height_dip_ = layout_.panel_height_dip;
    anim_target_height_dip_ = layout_.panel_height_dip;
    anim_current_height_dip_ = layout_.panel_height_dip;
    return;
  }
  anim_start_height_dip_ = current_dip;
  anim_target_height_dip_ = layout_.panel_height_dip;
  anim_current_height_dip_ = current_dip;
  height_anim_start_tick_ = now;
  height_anim_active_ = true;
}

void TrayPanelWindow::SnapAnimationsToCurrentState() {
  mode_anim_active_ = false;
  last_mode_ = state_.mode;
  const D2D1_RECT_F seg_rect = ModeSegmentRect(state_.mode);
  mode_anim_from_rect_ = seg_rect;
  mode_anim_to_rect_ = seg_rect;
  pill_current_rect_ = seg_rect;

  height_anim_active_ = false;
  anim_start_height_dip_ = layout_.panel_height_dip;
  anim_target_height_dip_ = layout_.panel_height_dip;
  anim_current_height_dip_ = layout_.panel_height_dip;

  proxies_anim_active_ = false;
  proxies_anim_progress_ = 1.0f;
  outgoing_proxies_.Reset();
}

void TrayPanelWindow::CancelAnimations() {
  SnapAnimationsToCurrentState();
}

void TrayPanelWindow::StepAnimationsAt(ULONGLONG now) {
  if (mode_anim_active_) {
    const ULONGLONG elapsed =
        now > mode_anim_start_tick_ ? now - mode_anim_start_tick_ : 0;
    if (elapsed >= kModeAnimDurationMs) {
      pill_current_rect_ = mode_anim_to_rect_;
      mode_anim_active_ = false;
    } else {
      const float linear = static_cast<float>(elapsed) /
                           static_cast<float>(kModeAnimDurationMs);
      pill_current_rect_ = LerpRectF(mode_anim_from_rect_, mode_anim_to_rect_,
                                     EaseOutCubic(linear));
    }
  }

  if (height_anim_active_) {
    const ULONGLONG elapsed =
        now > height_anim_start_tick_ ? now - height_anim_start_tick_ : 0;
    if (elapsed >= kLayoutAnimDurationMs) {
      anim_current_height_dip_ = anim_target_height_dip_;
      height_anim_active_ = false;
    } else {
      const float linear = static_cast<float>(elapsed) /
                           static_cast<float>(kLayoutAnimDurationMs);
      const float eased = EaseOutCubic(linear);
      anim_current_height_dip_ =
          anim_start_height_dip_ +
          (anim_target_height_dip_ - anim_start_height_dip_) * eased;
    }
  }

  if (proxies_anim_active_) {
    const ULONGLONG elapsed =
        now > proxies_anim_start_tick_ ? now - proxies_anim_start_tick_ : 0;
    if (elapsed >= kLayoutAnimDurationMs) {
      proxies_anim_progress_ = 1.0f;
      proxies_anim_active_ = false;
      outgoing_proxies_.Reset();
    } else {
      proxies_anim_progress_ = static_cast<float>(elapsed) /
                               static_cast<float>(kLayoutAnimDurationMs);
    }
  }
}

bool TrayPanelWindow::HasActiveAnimations() const {
  return mode_anim_active_ || height_anim_active_ || proxies_anim_active_;
}

float TrayPanelWindow::CurrentPanelHeightDip() const {
  return height_anim_active_ ? anim_current_height_dip_
                             : layout_.panel_height_dip;
}

D2D1_RECT_F TrayPanelWindow::ModeSegmentRect(const std::string& mode) const {
  return layout_.mode_segment_rects[ModeIndexFromString(mode)];
}

void TrayPanelWindow::RebuildFilteredGroups() {
  filtered_groups_.clear();
  std::wstring trimmed = search_query_;
  while (!trimmed.empty() && trimmed.front() == L' ') {
    trimmed.erase(trimmed.begin());
  }
  while (!trimmed.empty() && trimmed.back() == L' ') {
    trimmed.pop_back();
  }
  const std::wstring query = LowercaseWide(trimmed);

  for (size_t gi = 0; gi < state_.groups.size(); ++gi) {
    const auto& group = state_.groups[gi];
    if (query.empty()) {
      FilteredGroup entry;
      entry.group_index = gi;
      entry.expanded = expanded_groups_.count(group.name_utf8) > 0;
      entry.proxy_indices.reserve(group.proxies.size());
      for (size_t pi = 0; pi < group.proxies.size(); ++pi) {
        entry.proxy_indices.push_back(pi);
      }
      filtered_groups_.push_back(std::move(entry));
      continue;
    }

    std::vector<size_t> matched_proxies;
    for (size_t pi = 0; pi < group.proxies.size(); ++pi) {
      const auto& proxy = group.proxies[pi];
      if (proxy.name_lower.find(query) != std::wstring::npos ||
          proxy.type_lower.find(query) != std::wstring::npos) {
        matched_proxies.push_back(pi);
      }
    }
    if (!matched_proxies.empty()) {
      FilteredGroup entry;
      entry.group_index = gi;
      entry.expanded = true;
      entry.proxy_indices = std::move(matched_proxies);
      filtered_groups_.push_back(std::move(entry));
    } else if (group.name_lower.find(query) != std::wstring::npos) {
      FilteredGroup entry;
      entry.group_index = gi;
      entry.expanded = expanded_groups_.count(group.name_utf8) > 0;
      entry.proxy_indices.reserve(group.proxies.size());
      for (size_t pi = 0; pi < group.proxies.size(); ++pi) {
        entry.proxy_indices.push_back(pi);
      }
      filtered_groups_.push_back(std::move(entry));
    }
  }
}

void TrayPanelWindow::RebuildLayout() {
  layout_.hits.clear();
  layout_.group_cards.clear();
  layout_.max_panel_height_dip =
      (std::max)(220.0f, (std::min)(kMaxPanelHeightDip,
                                    work_height_dip_ - 24.0f));

  const float x0 = kOuterPadDip;
  const float x1 = kPanelWidthDip - kOuterPadDip;
  float y = kOuterPadDip;

  // Header (36 DIP)
  constexpr float kIconBtn = 28.0f;
  constexpr float kIconGap = 6.0f;
  const float btn_y = y + 4.0f;
  const float quit_x = x1 - kIconBtn;
  const float show_x = quit_x - kIconGap - kIconBtn;
  const float run_x = show_x - kIconGap - kIconBtn;
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kToggleRunning)),
       HitKind::kToggleRunning,
       D2D1::RectF(run_x, btn_y, run_x + kIconBtn, btn_y + kIconBtn), true,
       false, 0, 0});
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kShowWindow), 0),
       HitKind::kShowWindow,
       D2D1::RectF(show_x, btn_y, show_x + kIconBtn, btn_y + kIconBtn), true,
       false, 0, 0});
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kQuit)), HitKind::kQuit,
       D2D1::RectF(quit_x, btn_y, quit_x + kIconBtn, btn_y + kIconBtn), true,
       false, 0, 0});
  y += 36.0f + kSectionGapDip;

  // Outbound Mode (34 DIP)
  constexpr float kModeH = 34.0f;
  const float seg_w = (kInnerWidthDip - 6.0f - 8.0f) / 3.0f;
  const float seg_y0 = y + 3.0f;
  const float seg_y1 = y + kModeH - 3.0f;
  const HitKind mode_kinds[3] = {HitKind::kModeRule, HitKind::kModeGlobal,
                                 HitKind::kModeDirect};
  for (int i = 0; i < 3; ++i) {
    const float sx = x0 + 3.0f + static_cast<float>(i) * (seg_w + 4.0f);
    layout_.mode_segment_rects[i] =
        D2D1::RectF(sx, seg_y0, sx + seg_w, seg_y1);
    layout_.hits.push_back(
        {MakeHitKey(static_cast<int>(mode_kinds[i])), mode_kinds[i],
         layout_.mode_segment_rects[i], true, false, 0, 0});
  }
  y += kModeH + kSectionGapDip;

  // Quick Toggles Row 1 (38 DIP)
  constexpr float kToggleCardH = 38.0f;
  const float half_w = (kInnerWidthDip - 8.0f) / 2.0f;
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kToggleTun)), HitKind::kToggleTun,
       D2D1::RectF(x0, y, x0 + half_w, y + kToggleCardH), state_.is_start,
       false, 0, 0});
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kToggleSystemProxy)),
       HitKind::kToggleSystemProxy,
       D2D1::RectF(x0 + half_w + 8.0f, y, x1, y + kToggleCardH),
       state_.is_start, false, 0, 0});
  y += kToggleCardH + 8.0f;

  // Quick Toggles Row 2 (28 DIP)
  constexpr float kPillH = 28.0f;
  if (state_.show_macos_toggles) {
    const float third_w = (kInnerWidthDip - 12.0f) / 3.0f;
    const HitKind pill_kinds[3] = {HitKind::kToggleSpeedStats,
                                   HitKind::kToggleMonochrome,
                                   HitKind::kToggleAutoLaunch};
    for (int i = 0; i < 3; ++i) {
      const float px = x0 + static_cast<float>(i) * (third_w + 6.0f);
      layout_.hits.push_back(
          {MakeHitKey(static_cast<int>(pill_kinds[i])), pill_kinds[i],
           D2D1::RectF(px, y, px + third_w, y + kPillH), true, false, 0, 0});
    }
  } else {
    layout_.hits.push_back(
        {MakeHitKey(static_cast<int>(HitKind::kToggleAutoLaunch)),
         HitKind::kToggleAutoLaunch, D2D1::RectF(x0, y, x1, y + kPillH), true,
         false, 0, 0});
  }
  y += kPillH + kSectionGapDip;

  // Footer fixed height: divider (1) + gap (10) + footer buttons (30) + pad (14)
  constexpr float kFooterReservedDip = 55.0f;

  if (!state_.groups.empty()) {
    constexpr float kGroupsHeaderH = 24.0f;
    layout_.groups_header_rect = D2D1::RectF(x0, y, x1, y + kGroupsHeaderH);
    const float test_x = x1 - 24.0f;
    const float search_x = test_x - 6.0f - 24.0f;
    layout_.hits.push_back(
        {MakeHitKey(static_cast<int>(HitKind::kSearchToggle)),
         HitKind::kSearchToggle,
         D2D1::RectF(search_x, y, search_x + 24.0f, y + kGroupsHeaderH), true,
         false, 0, 0});
    layout_.hits.push_back(
        {MakeHitKey(static_cast<int>(HitKind::kTestAllDelays)),
         HitKind::kTestAllDelays,
         D2D1::RectF(test_x, y, test_x + 24.0f, y + kGroupsHeaderH),
         !state_.testing_all, false, 0, 0});
    y += kGroupsHeaderH + 8.0f;

    if (search_visible_) {
      constexpr float kSearchH = 28.0f;
      layout_.search_box_rect = D2D1::RectF(x0, y, x1, y + kSearchH);
      layout_.search_clear_rect =
          D2D1::RectF(x1 - 24.0f, y + 2.0f, x1 - 4.0f, y + kSearchH - 2.0f);
      if (!search_query_.empty()) {
        layout_.hits.push_back(
            {MakeHitKey(static_cast<int>(HitKind::kSearchClear)),
             HitKind::kSearchClear, layout_.search_clear_rect, true, false, 0,
             0});
      }
      layout_.hits.push_back(
          {MakeHitKey(static_cast<int>(HitKind::kSearchBox)),
           HitKind::kSearchBox, layout_.search_box_rect, true, false, 0, 0});
      y += kSearchH + 8.0f;
    } else {
      layout_.search_box_rect = {};
      layout_.search_clear_rect = {};
    }

    if (filtered_groups_.empty()) {
      constexpr float kEmptyH = 68.0f;
      layout_.groups_viewport_rect = D2D1::RectF(x0, y, x1, y + kEmptyH);
      layout_.groups_content_height_dip = kEmptyH;
      layout_.max_scroll_dip = 0.0f;
      y += kEmptyH + kSectionGapDip;
    } else {
      float content_y = y;
      for (size_t idx = 0; idx < filtered_groups_.size(); ++idx) {
        const auto& fg = filtered_groups_[idx];
        GroupCardLayout card;
        card.group_index = fg.group_index;
        card.expanded = fg.expanded;
        const float card_top = content_y;
        constexpr float kCardPad = 10.0f;
        constexpr float kHeaderRowH = 34.0f;
        const float header_top = card_top + kCardPad;
        const float header_bottom = header_top + kHeaderRowH;

        card.chevron_rect =
            D2D1::RectF(x1 - kCardPad - 14.0f, header_top, x1 - kCardPad,
                        header_bottom);
        card.test_rect =
            D2D1::RectF(card.chevron_rect.left - 6.0f - 22.0f,
                        header_top + 6.0f, card.chevron_rect.left - 6.0f,
                        header_top + 28.0f);
        card.header_rect = D2D1::RectF(x0, card_top, x1, header_bottom + 4.0f);
        card.header_key =
            MakeHitKey(static_cast<int>(HitKind::kGroupHeader), fg.group_index);
        card.test_key = MakeHitKey(static_cast<int>(HitKind::kGroupTestDelay),
                                   fg.group_index);

        float card_bottom = header_bottom + kCardPad;
        if (fg.expanded && !fg.proxy_indices.empty()) {
          const float tiles_top = header_bottom + 8.0f;
          const float tile_w = (kInnerWidthDip - 2.0f * kCardPad - 6.0f) / 2.0f;
          constexpr float kTileH = 44.0f;
          constexpr float kTileGap = 6.0f;
          const size_t rows = (fg.proxy_indices.size() + 1) / 2;
          for (size_t i = 0; i < fg.proxy_indices.size(); ++i) {
            const size_t row = i / 2;
            const size_t col = i % 2;
            const float tx = x0 + kCardPad + static_cast<float>(col) *
                                                 (tile_w + kTileGap);
            const float ty =
                tiles_top + static_cast<float>(row) * (kTileH + kTileGap);
            ProxyTileLayout tile;
            tile.group_index = fg.group_index;
            tile.proxy_index = fg.proxy_indices[i];
            tile.rect = D2D1::RectF(tx, ty, tx + tile_w, ty + kTileH);
            tile.hit_key = MakeHitKey(static_cast<int>(HitKind::kProxyTile),
                                      fg.group_index, tile.proxy_index);
            layout_.hits.push_back({tile.hit_key, HitKind::kProxyTile,
                                    tile.rect, true, true, fg.group_index,
                                    tile.proxy_index});
            card.tiles.push_back(tile);
          }
          card_bottom = tiles_top + static_cast<float>(rows) * kTileH +
                        static_cast<float>(rows - 1) * kTileGap + kCardPad;
        }
        card.card_rect = D2D1::RectF(x0, card_top, x1, card_bottom);

        layout_.hits.push_back(
            {card.test_key, HitKind::kGroupTestDelay, card.test_rect,
             !state_.groups[fg.group_index].testing, true, fg.group_index, 0});
        layout_.hits.push_back({card.header_key, HitKind::kGroupHeader,
                                card.header_rect, true, true, fg.group_index,
                                0});
        layout_.group_cards.push_back(std::move(card));

        content_y = card_bottom + (idx + 1 < filtered_groups_.size() ? 8.0f : 0.0f);
      }

      layout_.groups_content_height_dip = content_y - y;
      const float avail_scroll = (std::max)(
          44.0f, layout_.max_panel_height_dip - y - kFooterReservedDip);
      const float viewport_h = (std::min)(
          (std::max)(44.0f, layout_.groups_content_height_dip), avail_scroll);
      layout_.groups_viewport_rect = D2D1::RectF(x0, y, x1, y + viewport_h);
      layout_.max_scroll_dip =
          (std::max)(0.0f, layout_.groups_content_height_dip - viewport_h);
      y += viewport_h + kSectionGapDip;
    }
  } else {
    layout_.groups_header_rect = {};
    layout_.search_box_rect = {};
    layout_.groups_viewport_rect = {};
    layout_.groups_content_height_dip = 0.0f;
    layout_.max_scroll_dip = 0.0f;
  }

  // Divider + Footer
  layout_.divider_y_dip = y;
  y += 1.0f + kSectionGapDip;
  layout_.footer_y_dip = y;
  constexpr float kFooterH = 28.0f;
  const float copy_w = (kInnerWidthDip - 8.0f) * 0.56f;
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kCopyEnv)), HitKind::kCopyEnv,
       D2D1::RectF(x0, y, x0 + copy_w, y + kFooterH), true, false, 0, 0});
  layout_.hits.push_back(
      {MakeHitKey(static_cast<int>(HitKind::kShowWindow), 1),
       HitKind::kShowWindow,
       D2D1::RectF(x0 + copy_w + 8.0f, y, x1, y + kFooterH), true, false, 0,
       0});
  y += kFooterH + kOuterPadDip;

  layout_.panel_height_dip = (std::max)(180.0f, y);
}

void TrayPanelWindow::ClampScroll() {
  scroll_offset_dip_ =
      (std::max)(0.0f, (std::min)(layout_.max_scroll_dip, scroll_offset_dip_));
}

std::optional<TrayPanelWindow::HitTarget> TrayPanelWindow::HitTest(
    float dip_x,
    float dip_y) const {
  const float current_h = CurrentPanelHeightDip();
  const float footer_y = height_anim_active_
                             ? (current_h - kFooterOffsetFromBottomDip)
                             : layout_.footer_y_dip;
  const float footer_dy = footer_y - layout_.footer_y_dip;
  D2D1_RECT_F effective_vp = layout_.groups_viewport_rect;
  if (height_anim_active_) {
    const float max_vp_bottom =
        current_h - kDividerOffsetFromBottomDip - kSectionGapDip;
    effective_vp.bottom = (std::min)(effective_vp.bottom, max_vp_bottom);
  }
  const bool in_viewport =
      effective_vp.bottom > effective_vp.top &&
      PointInRectF(effective_vp, dip_x, dip_y);
  for (const auto& hit : layout_.hits) {
    if (hit.in_scroll_viewport) {
      if (!in_viewport) {
        continue;
      }
      if (PointInRectF(OffsetRectF(hit.rect, -scroll_offset_dip_), dip_x,
                       dip_y)) {
        return hit;
      }
    } else {
      const D2D1_RECT_F rect =
          (hit.rect.top >= layout_.footer_y_dip - 2.0f)
              ? OffsetRectF(hit.rect, footer_dy)
              : hit.rect;
      if (PointInRectF(rect, dip_x, dip_y)) {
        return hit;
      }
    }
  }
  return std::nullopt;
}

void TrayPanelWindow::DispatchHit(const HitTarget& hit) {
  if (!hit.enabled) {
    return;
  }
  const auto emit = [&](const std::string& action,
                        const flutter::EncodableMap& payload = {}) {
    if (on_action_) {
      on_action_(action, payload);
    }
  };

  switch (hit.kind) {
    case HitKind::kNone:
      break;
    case HitKind::kToggleRunning:
      emit("toggleRunning");
      break;
    case HitKind::kShowWindow:
      HideInternal(true, false);
      emit("showWindow");
      break;
    case HitKind::kQuit:
      HideInternal(true, false);
      emit("quit");
      break;
    case HitKind::kModeRule:
      if (state_.mode != "rule") {
        flutter::EncodableMap p;
        p[flutter::EncodableValue("mode")] = flutter::EncodableValue("rule");
        emit("setMode", p);
      }
      break;
    case HitKind::kModeGlobal:
      if (state_.mode != "global") {
        flutter::EncodableMap p;
        p[flutter::EncodableValue("mode")] = flutter::EncodableValue("global");
        emit("setMode", p);
      }
      break;
    case HitKind::kModeDirect:
      if (state_.mode != "direct") {
        flutter::EncodableMap p;
        p[flutter::EncodableValue("mode")] = flutter::EncodableValue("direct");
        emit("setMode", p);
      }
      break;
    case HitKind::kToggleTun:
      emit("toggleTun");
      break;
    case HitKind::kToggleSystemProxy:
      emit("toggleSystemProxy");
      break;
    case HitKind::kToggleSpeedStats:
      emit("toggleSpeedStatistics");
      break;
    case HitKind::kToggleMonochrome:
      emit("toggleMonochromeIcon");
      break;
    case HitKind::kToggleAutoLaunch:
      emit("toggleAutoLaunch");
      break;
    case HitKind::kSearchToggle:
      search_visible_ = !search_visible_;
      if (!search_visible_) {
        search_query_.clear();
      }
      caret_visible_ = true;
      ApplyLocalLayoutChange(true);
      break;
    case HitKind::kSearchBox:
      ::SetFocus(hwnd_);
      caret_visible_ = true;
      ::InvalidateRect(hwnd_, nullptr, FALSE);
      break;
    case HitKind::kSearchClear:
      search_query_.clear();
      scroll_offset_dip_ = 0.0f;
      ApplyLocalLayoutChange(false);
      break;
    case HitKind::kTestAllDelays:
      emit("testAllDelays");
      break;
    case HitKind::kGroupHeader:
      if (hit.group_index < state_.groups.size()) {
        const std::string& name = state_.groups[hit.group_index].name_utf8;
        if (expanded_groups_.count(name) > 0) {
          expanded_groups_.erase(name);
        } else {
          expanded_groups_.insert(name);
        }
        ApplyLocalLayoutChange(false);
      }
      break;
    case HitKind::kGroupTestDelay:
      if (hit.group_index < state_.groups.size()) {
        flutter::EncodableMap p;
        p[flutter::EncodableValue("groupName")] =
            flutter::EncodableValue(state_.groups[hit.group_index].name_utf8);
        emit("testGroupDelay", p);
      }
      break;
    case HitKind::kProxyTile:
      if (hit.group_index < state_.groups.size() &&
          hit.proxy_index < state_.groups[hit.group_index].proxies.size()) {
        flutter::EncodableMap p;
        p[flutter::EncodableValue("groupName")] =
            flutter::EncodableValue(state_.groups[hit.group_index].name_utf8);
        p[flutter::EncodableValue("proxyName")] = flutter::EncodableValue(
            state_.groups[hit.group_index].proxies[hit.proxy_index].name_utf8);
        emit("selectProxy", p);
      }
      break;
    case HitKind::kCopyEnv:
      copied_feedback_ = true;
      if (hwnd_ != nullptr) {
        ::SetTimer(hwnd_, kCopyFeedbackTimerId, kCopyFeedbackDurationMs,
                   nullptr);
      }
      ::InvalidateRect(hwnd_, nullptr, FALSE);
      emit("copyEnv");
      break;
  }
}

void TrayPanelWindow::Render() {
  if (!has_state_ || !EnsureRenderTarget()) {
    return;
  }

  render_target_->BeginDraw();
  const int build = QueryWindowsBuild();
  const bool has_acrylic = build >= 17134 && !state_.theme.pure_black;
  const uint32_t bg_argb =
      has_acrylic
          ? (build >= 22621 ? state_.theme.glass_tint
                            : WithAlpha(state_.theme.glass_tint, 0.05f))
          : CompositeOver(state_.theme.glass_tint, state_.theme.card_bg);
  render_target_->Clear(ColorFromArgb(bg_argb));

  RECT client{};
  ::GetClientRect(hwnd_, &client);
  const float client_height_dip =
      DipFromPx(static_cast<int>((std::max)(1L, client.bottom - client.top)));
  const float divider_y = height_anim_active_
                              ? (client_height_dip - kDividerOffsetFromBottomDip)
                              : layout_.divider_y_dip;
  const float footer_y = height_anim_active_
                             ? (client_height_dip - kFooterOffsetFromBottomDip)
                             : layout_.footer_y_dip;
  const float max_proxies_bottom = divider_y - kSectionGapDip;

  float y = kOuterPadDip;
  DrawHeader(y);
  y += 36.0f + kSectionGapDip;
  DrawOutboundMode(y);
  y += 34.0f + kSectionGapDip;
  DrawQuickToggles(y);

  if (proxies_anim_active_) {
    DrawAnimatedProxiesSection(max_proxies_bottom);
  } else if (!state_.groups.empty()) {
    DrawProxiesSectionContent(state_.groups, filtered_groups_, layout_,
                              search_visible_, state_.testing_all,
                              search_query_, scroll_offset_dip_,
                              max_proxies_bottom, 1.0f, true);
  }

  brush_->SetColor(ColorFromArgb(state_.theme.hairline));
  render_target_->FillRectangle(
      D2D1::RectF(kOuterPadDip, divider_y, kPanelWidthDip - kOuterPadDip,
                  divider_y + 0.75f),
      brush_.Get());

  DrawFooter(footer_y);

  const HRESULT hr = render_target_->EndDraw();
  if (hr == D2DERR_RECREATE_TARGET) {
    DiscardRenderResources();
    ::InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void TrayPanelWindow::DrawHeader(float y_top) {
  const auto& t = state_.theme;
  const uint32_t dot_color = !state_.is_start
                                 ? WithAlpha(t.on_surface_variant, 0.45f)
                                 : (state_.suspended ? t.warning : t.success);
  const float dot_cx = kOuterPadDip + 9.0f;
  const float dot_cy = y_top + 18.0f;
  brush_->SetColor(ColorFromArgb(dot_color, 0.22f));
  render_target_->FillEllipse(D2D1::Ellipse(D2D1::Point2F(dot_cx, dot_cy), 9.0f, 9.0f),
                              brush_.Get());
  brush_->SetColor(ColorFromArgb(dot_color));
  render_target_->FillEllipse(D2D1::Ellipse(D2D1::Point2F(dot_cx, dot_cy), 4.0f, 4.0f),
                              brush_.Get());

  const float text_x = kOuterPadDip + 28.0f;
  const float buttons_left = kPanelWidthDip - kOuterPadDip - 3.0f * 28.0f - 12.0f;
  const float max_title_w = buttons_left - text_x - 8.0f;

  float title_w =
      MeasureTextWidth(state_.labels.app_name, fmt_title_.Get(), max_title_w);
  float badge_w = 0.0f;
  if (state_.safe_mode) {
    badge_w = MeasureTextWidth(state_.labels.safe_mode, fmt_badge_.Get(), 90.0f) +
              12.0f;
    title_w = (std::min)(title_w, (std::max)(40.0f, max_title_w - badge_w - 6.0f));
  }
  DrawTextClipped(state_.labels.app_name, fmt_title_.Get(),
                  D2D1::RectF(text_x, y_top, text_x + title_w + 4.0f, y_top + 20.0f),
                  t.on_surface);

  if (state_.safe_mode) {
    const float bx = text_x + title_w + 6.0f;
    const D2D1_RECT_F badge_rect =
        D2D1::RectF(bx, y_top + 2.0f, bx + badge_w, y_top + 18.0f);
    DrawRoundedCard(badge_rect, 8.0f, WithAlpha(t.warning, 0.16f));
    DrawTextClipped(state_.labels.safe_mode, fmt_badge_center_.Get(),
                    badge_rect, t.warning);
  }

  // Live traffic line
  const std::wstring traffic_line =
      L"\u2191 " + traffic_.up + L"   \u2193 " + traffic_.down;
  DrawTextClipped(traffic_line, fmt_small_medium_.Get(),
                  D2D1::RectF(text_x, y_top + 20.0f, buttons_left - 6.0f,
                              y_top + 36.0f),
                  t.on_surface_variant);

  // Header icon buttons
  const auto draw_icon_btn = [&](HitKind kind, uint32_t bg, uint32_t hover_bg,
                                 uint32_t fg, uint32_t hover_fg) {
    for (const auto& hit : layout_.hits) {
      if (hit.kind != kind || hit.rect.top > 60.0f) {
        continue;
      }
      const bool hovered = hovered_key_ == hit.key;
      DrawRoundedCard(hit.rect, 9.0f, hovered ? hover_bg : bg);
      const uint32_t icon_color = hovered ? hover_fg : fg;
      brush_->SetColor(ColorFromArgb(icon_color));
      const float cx = (hit.rect.left + hit.rect.right) * 0.5f;
      const float cy = (hit.rect.top + hit.rect.bottom) * 0.5f;
      if (kind == HitKind::kToggleRunning) {
        if (state_.is_start) {
          render_target_->FillRectangle(
              D2D1::RectF(cx - 4.0f, cy - 5.0f, cx - 1.5f, cy + 5.0f),
              brush_.Get());
          render_target_->FillRectangle(
              D2D1::RectF(cx + 1.5f, cy - 5.0f, cx + 4.0f, cy + 5.0f),
              brush_.Get());
        } else {
          ComPtr<ID2D1PathGeometry> geo;
          ComPtr<ID2D1GeometrySink> sink;
          if (SUCCEEDED(d2d_factory_->CreatePathGeometry(geo.GetAddressOf())) &&
              SUCCEEDED(geo->Open(sink.GetAddressOf()))) {
            sink->BeginFigure(D2D1::Point2F(cx - 3.5f, cy - 5.0f),
                              D2D1_FIGURE_BEGIN_FILLED);
            sink->AddLine(D2D1::Point2F(cx + 5.0f, cy));
            sink->AddLine(D2D1::Point2F(cx - 3.5f, cy + 5.0f));
            sink->EndFigure(D2D1_FIGURE_END_CLOSED);
            sink->Close();
            render_target_->FillGeometry(geo.Get(), brush_.Get());
          }
        }
      } else if (kind == HitKind::kShowWindow) {
        const D2D1_ROUNDED_RECT r = D2D1::RoundedRect(
            D2D1::RectF(cx - 6.0f, cy - 5.0f, cx + 6.0f, cy + 5.0f), 2.0f, 2.0f);
        render_target_->DrawRoundedRectangle(r, brush_.Get(), 1.4f);
        render_target_->DrawLine(D2D1::Point2F(cx - 6.0f, cy - 1.8f),
                                 D2D1::Point2F(cx + 6.0f, cy - 1.8f),
                                 brush_.Get(), 1.2f);
      } else if (kind == HitKind::kQuit) {
        ComPtr<ID2D1PathGeometry> geo;
        ComPtr<ID2D1GeometrySink> sink;
        if (SUCCEEDED(d2d_factory_->CreatePathGeometry(geo.GetAddressOf())) &&
            SUCCEEDED(geo->Open(sink.GetAddressOf()))) {
          const float rad = 4.8f;
          const float a0 = -55.0f * kPi / 180.0f;
          const float a1 = 235.0f * kPi / 180.0f;
          sink->BeginFigure(
              D2D1::Point2F(cx + rad * std::cos(a0), cy + rad * std::sin(a0)),
              D2D1_FIGURE_BEGIN_HOLLOW);
          sink->AddArc(D2D1::ArcSegment(
              D2D1::Point2F(cx + rad * std::cos(a1), cy + rad * std::sin(a1)),
              D2D1::SizeF(rad, rad), 0.0f, D2D1_SWEEP_DIRECTION_CLOCKWISE,
              D2D1_ARC_SIZE_LARGE));
          sink->EndFigure(D2D1_FIGURE_END_OPEN);
          sink->Close();
          render_target_->DrawGeometry(geo.Get(), brush_.Get(), 1.5f);
        }
        render_target_->DrawLine(D2D1::Point2F(cx, cy - 6.0f),
                                 D2D1::Point2F(cx, cy - 0.5f), brush_.Get(),
                                 1.5f);
      }
      break;
    }
  };

  draw_icon_btn(HitKind::kToggleRunning,
                state_.is_start ? WithAlpha(t.primary, 0.16f) : t.card_bg,
                state_.is_start ? WithAlpha(t.primary, 0.24f) : t.block_bg,
                state_.is_start ? t.primary : t.on_surface,
                state_.is_start ? t.primary : t.on_surface);
  draw_icon_btn(HitKind::kShowWindow, t.card_bg, t.block_bg,
                t.on_surface_variant, t.on_surface);
  draw_icon_btn(HitKind::kQuit, t.card_bg, WithAlpha(t.error, 0.16f),
                t.on_surface_variant, t.error);
}

void TrayPanelWindow::DrawOutboundMode(float y_top) {
  const auto& t = state_.theme;
  DrawRoundedCard(D2D1::RectF(kOuterPadDip, y_top,
                              kPanelWidthDip - kOuterPadDip, y_top + 34.0f),
                  13.0f, t.inset_bg);

  const struct {
    HitKind kind;
    const char* key;
    const std::wstring* label;
  } modes[3] = {
      {HitKind::kModeRule, "rule", &state_.labels.mode_rule},
      {HitKind::kModeGlobal, "global", &state_.labels.mode_global},
      {HitKind::kModeDirect, "direct", &state_.labels.mode_direct},
  };

  const D2D1_RECT_F pill_rect =
      mode_anim_active_ ? pill_current_rect_ : ModeSegmentRect(state_.mode);

  for (const auto& m : modes) {
    for (const auto& hit : layout_.hits) {
      if (hit.kind != m.kind) {
        continue;
      }
      const float overlap = RectHorizontalOverlapRatio(pill_rect, hit.rect);
      if (hovered_key_ == hit.key && overlap < 0.5f) {
        DrawRoundedCard(hit.rect, 10.0f,
                        WithAlpha(t.on_surface, 0.06f * (1.0f - overlap)));
      }
      break;
    }
  }

  if (pill_rect.right > pill_rect.left) {
    DrawRoundedCard(pill_rect, 10.0f, t.primary);
  }

  for (const auto& m : modes) {
    for (const auto& hit : layout_.hits) {
      if (hit.kind != m.kind) {
        continue;
      }
      const float overlap = RectHorizontalOverlapRatio(pill_rect, hit.rect);
      const uint32_t text_color =
          LerpArgb(t.on_surface_variant, t.on_primary, overlap);
      DrawTextClipped(
          *m.label,
          overlap >= 0.5f ? fmt_body_semibold_.Get() : fmt_body_.Get(),
          hit.rect, text_color, DWRITE_TEXT_ALIGNMENT_CENTER);
      break;
    }
  }
}

void TrayPanelWindow::DrawQuickToggles(float y_top) {
  const auto& t = state_.theme;
  const float alpha_scale = state_.is_start ? 1.0f : 0.45f;

  const auto draw_card = [&](HitKind kind, const std::wstring& title,
                             const std::wstring& shortcut, bool active) {
    for (const auto& hit : layout_.hits) {
      if (hit.kind != kind) {
        continue;
      }
      const bool hovered = hit.enabled && hovered_key_ == hit.key;
      const uint32_t bg =
          active ? WithAlpha(t.primary, 0.16f)
                 : (hovered ? t.block_bg : t.card_bg);
      DrawRoundedCard(hit.rect, 12.0f,
                      WithAlpha(bg, ColorFromArgb(bg).a * alpha_scale));

      const D2D1_RECT_F icon_box =
          D2D1::RectF(hit.rect.left + 9.0f, hit.rect.top + 7.0f,
                      hit.rect.left + 33.0f, hit.rect.top + 31.0f);
      DrawRoundedCard(
          icon_box, 7.0f,
          active ? WithAlpha(t.primary, 0.14f * alpha_scale)
                 : WithAlpha(t.block_bg, alpha_scale));
      const uint32_t fg = WithAlpha(active ? t.primary : t.on_surface_variant,
                                    alpha_scale);
      brush_->SetColor(ColorFromArgb(fg));
      const float icx = (icon_box.left + icon_box.right) * 0.5f;
      const float icy = (icon_box.top + icon_box.bottom) * 0.5f;
      if (kind == HitKind::kToggleTun) {
        ComPtr<ID2D1PathGeometry> geo;
        ComPtr<ID2D1GeometrySink> sink;
        if (SUCCEEDED(d2d_factory_->CreatePathGeometry(geo.GetAddressOf())) &&
            SUCCEEDED(geo->Open(sink.GetAddressOf()))) {
          sink->BeginFigure(D2D1::Point2F(icx, icy - 6.0f),
                            D2D1_FIGURE_BEGIN_HOLLOW);
          sink->AddLine(D2D1::Point2F(icx + 5.0f, icy - 3.5f));
          sink->AddLine(D2D1::Point2F(icx + 4.5f, icy + 2.0f));
          sink->AddLine(D2D1::Point2F(icx, icy + 6.0f));
          sink->AddLine(D2D1::Point2F(icx - 4.5f, icy + 2.0f));
          sink->AddLine(D2D1::Point2F(icx - 5.0f, icy - 3.5f));
          sink->EndFigure(D2D1_FIGURE_END_CLOSED);
          sink->Close();
          render_target_->DrawGeometry(geo.Get(), brush_.Get(), 1.4f);
        }
      } else {
        render_target_->DrawEllipse(
            D2D1::Ellipse(D2D1::Point2F(icx, icy), 5.5f, 5.5f), brush_.Get(),
            1.3f);
        render_target_->DrawEllipse(
            D2D1::Ellipse(D2D1::Point2F(icx, icy), 2.5f, 5.5f), brush_.Get(),
            1.1f);
        render_target_->DrawLine(D2D1::Point2F(icx - 5.5f, icy),
                                 D2D1::Point2F(icx + 5.5f, icy), brush_.Get(),
                                 1.1f);
      }

      float right_limit = hit.rect.right - 9.0f;
      if (!shortcut.empty()) {
        const float sw = (std::min)(
            54.0f, MeasureTextWidth(shortcut, fmt_badge_.Get(), 60.0f) + 8.0f);
        const D2D1_RECT_F srect = D2D1::RectF(
            right_limit - sw, hit.rect.top + 11.0f, right_limit,
            hit.rect.bottom - 11.0f);
        DrawRoundedCard(srect, 4.0f,
                        active ? WithAlpha(t.primary, 0.14f * alpha_scale)
                               : WithAlpha(t.inset_bg, alpha_scale));
        DrawTextClipped(shortcut, fmt_badge_center_.Get(), srect,
                        WithAlpha(active ? t.primary : t.on_surface_variant,
                                  alpha_scale));
        right_limit = srect.left - 4.0f;
      }

      DrawTextClipped(
          title, active ? fmt_body_semibold_.Get() : fmt_body_.Get(),
          D2D1::RectF(icon_box.right + 7.0f, hit.rect.top, right_limit,
                      hit.rect.bottom),
          fg);
      break;
    }
  };

  draw_card(HitKind::kToggleTun, state_.labels.tun, state_.shortcuts.tun,
            state_.tun_enable);
  draw_card(HitKind::kToggleSystemProxy, state_.labels.system_proxy,
            state_.shortcuts.system_proxy, state_.system_proxy);

  const auto draw_pill = [&](HitKind kind, const std::wstring& title,
                             bool active) {
    for (const auto& hit : layout_.hits) {
      if (hit.kind != kind) {
        continue;
      }
      const bool hovered = hovered_key_ == hit.key;
      const uint32_t bg =
          active ? WithAlpha(t.primary, 0.16f)
                 : (hovered ? t.block_bg : t.card_bg);
      DrawRoundedCard(hit.rect, 14.0f, bg);
      const uint32_t fg = active ? t.primary : t.on_surface_variant;
      const float tw = MeasureTextWidth(title, fmt_small_medium_.Get(),
                                        hit.rect.right - hit.rect.left - 24.0f);
      const float total_w = 14.0f + tw;
      const float start_x =
          (hit.rect.left + hit.rect.right - total_w) * 0.5f;
      const float cy = (hit.rect.top + hit.rect.bottom) * 0.5f;
      brush_->SetColor(ColorFromArgb(fg));
      render_target_->DrawEllipse(
          D2D1::Ellipse(D2D1::Point2F(start_x + 5.0f, cy), 4.2f, 4.2f),
          brush_.Get(), 1.3f);
      if (active) {
        render_target_->FillEllipse(
            D2D1::Ellipse(D2D1::Point2F(start_x + 5.0f, cy), 2.0f, 2.0f),
            brush_.Get());
      }
      DrawTextClipped(
          title, fmt_small_medium_.Get(),
          D2D1::RectF(start_x + 14.0f, hit.rect.top, hit.rect.right - 6.0f,
                      hit.rect.bottom),
          fg);
      break;
    }
  };

  if (state_.show_macos_toggles) {
    draw_pill(HitKind::kToggleSpeedStats, state_.labels.speed_statistics,
              state_.show_tray_title);
    draw_pill(HitKind::kToggleMonochrome, state_.labels.monochrome_icon,
              state_.monochrome_tray_icon);
  }
  draw_pill(HitKind::kToggleAutoLaunch, state_.labels.auto_launch,
            state_.auto_launch);
}

void TrayPanelWindow::DrawAnimatedProxiesSection(float max_bottom_dip) {
  const float eased = EaseOutCubic(proxies_anim_progress_);
  if (outgoing_proxies_.valid && state_.groups.empty()) {
    const float out_alpha = 1.0f - eased;
    if (out_alpha > 0.01f) {
      DrawProxiesSectionContent(
          outgoing_proxies_.groups, outgoing_proxies_.filtered_groups,
          outgoing_proxies_.layout, outgoing_proxies_.search_visible,
          outgoing_proxies_.testing_all, outgoing_proxies_.search_query,
          outgoing_proxies_.scroll_offset_dip, max_bottom_dip, out_alpha,
          false);
    }
    return;
  }

  if (!outgoing_proxies_.valid && !state_.groups.empty()) {
    if (eased > 0.01f) {
      DrawProxiesSectionContent(state_.groups, filtered_groups_, layout_,
                                search_visible_, state_.testing_all,
                                search_query_, scroll_offset_dip_,
                                max_bottom_dip, eased, true);
    }
    return;
  }

  if (outgoing_proxies_.valid && !state_.groups.empty()) {
    const float out_alpha = Clamp01(1.0f - proxies_anim_progress_ * 2.5f);
    const float in_alpha =
        Clamp01((proxies_anim_progress_ - 0.35f) / 0.65f);
    if (out_alpha > 0.01f) {
      DrawProxiesSectionContent(
          outgoing_proxies_.groups, outgoing_proxies_.filtered_groups,
          outgoing_proxies_.layout, outgoing_proxies_.search_visible,
          outgoing_proxies_.testing_all, outgoing_proxies_.search_query,
          outgoing_proxies_.scroll_offset_dip, max_bottom_dip, out_alpha,
          false);
    }
    if (in_alpha > 0.01f) {
      DrawProxiesSectionContent(state_.groups, filtered_groups_, layout_,
                                search_visible_, state_.testing_all,
                                search_query_, scroll_offset_dip_,
                                max_bottom_dip, in_alpha, true);
    }
  }
}

void TrayPanelWindow::DrawProxiesSectionContent(
    const std::vector<TrayPanelGroup>& groups,
    const std::vector<FilteredGroup>& filtered_groups,
    const PanelLayout& layout,
    bool search_visible,
    bool testing_all,
    const std::wstring& search_query,
    float scroll_offset_dip,
    float max_bottom_dip,
    float alpha_scale,
    bool interactive) {
  const D2D1_RECT_F& hdr = layout.groups_header_rect;
  if (max_bottom_dip <= hdr.top + 1.0f) {
    return;
  }

  const float prev_alpha_scale = draw_alpha_scale_;
  draw_alpha_scale_ = prev_alpha_scale * Clamp01(alpha_scale);
  render_target_->PushAxisAlignedClip(
      D2D1::RectF(0.0f, hdr.top, kPanelWidthDip, max_bottom_dip),
      D2D1_ANTIALIAS_MODE_ALIASED);

  const auto& t = state_.theme;
  const float title_w =
      MeasureTextWidth(state_.labels.proxies, fmt_body_semibold_.Get(), 150.0f);
  DrawTextClipped(state_.labels.proxies, fmt_body_semibold_.Get(),
                  D2D1::RectF(hdr.left, hdr.top, hdr.left + title_w + 4.0f,
                              hdr.bottom),
                  t.on_surface_variant);

  wchar_t count_buf[16]{};
  ::StringCchPrintfW(count_buf, ARRAYSIZE(count_buf), L"%u",
                     static_cast<unsigned>(filtered_groups.size()));
  const std::wstring count_str(count_buf);
  const float count_w =
      (std::max)(20.0f, MeasureTextWidth(count_str, fmt_badge_.Get(), 48.0f) + 12.0f);
  const float count_x = hdr.left + title_w + 6.0f;
  const D2D1_RECT_F count_rect =
      D2D1::RectF(count_x, hdr.top + 3.0f, count_x + count_w, hdr.bottom - 3.0f);
  DrawRoundedCard(count_rect, 9.0f, t.inset_bg);
  DrawTextClipped(count_str, fmt_badge_center_.Get(), count_rect,
                  t.on_surface_variant);

  for (const auto& hit : layout.hits) {
    if (hit.kind == HitKind::kSearchToggle) {
      const bool hovered = interactive && hovered_key_ == hit.key;
      const uint32_t bg =
          search_visible
              ? WithAlpha(t.primary, hovered ? 0.24f : 0.16f)
              : (hovered ? t.block_bg : t.card_bg);
      const uint32_t fg =
          search_visible ? t.primary : t.on_surface_variant;
      DrawRoundedCard(hit.rect, 8.0f, bg);
      brush_->SetColor(ColorFromArgb(fg));
      const float cx = (hit.rect.left + hit.rect.right) * 0.5f - 1.0f;
      const float cy = (hit.rect.top + hit.rect.bottom) * 0.5f - 1.0f;
      render_target_->DrawEllipse(
          D2D1::Ellipse(D2D1::Point2F(cx, cy), 4.0f, 4.0f), brush_.Get(), 1.4f);
      render_target_->DrawLine(D2D1::Point2F(cx + 2.8f, cy + 2.8f),
                               D2D1::Point2F(cx + 5.8f, cy + 5.8f),
                               brush_.Get(), 1.5f);
    } else if (hit.kind == HitKind::kTestAllDelays) {
      const bool hovered = interactive && hit.enabled && hovered_key_ == hit.key;
      DrawRoundedCard(hit.rect, 8.0f, hovered ? t.block_bg : t.card_bg);
      const float cx = (hit.rect.left + hit.rect.right) * 0.5f;
      const float cy = (hit.rect.top + hit.rect.bottom) * 0.5f;
      if (testing_all) {
        DrawSpinner(cx, cy, 5.0f, t.primary);
      } else {
        brush_->SetColor(ColorFromArgb(t.on_surface_variant));
        ComPtr<ID2D1PathGeometry> bolt;
        ComPtr<ID2D1GeometrySink> sink;
        if (SUCCEEDED(d2d_factory_->CreatePathGeometry(bolt.GetAddressOf())) &&
            SUCCEEDED(bolt->Open(sink.GetAddressOf()))) {
          sink->BeginFigure(D2D1::Point2F(cx + 1.0f, cy - 5.5f),
                            D2D1_FIGURE_BEGIN_FILLED);
          sink->AddLine(D2D1::Point2F(cx - 4.0f, cy + 0.5f));
          sink->AddLine(D2D1::Point2F(cx - 0.5f, cy + 0.5f));
          sink->AddLine(D2D1::Point2F(cx - 1.5f, cy + 5.5f));
          sink->AddLine(D2D1::Point2F(cx + 4.0f, cy - 0.5f));
          sink->AddLine(D2D1::Point2F(cx + 0.5f, cy - 0.5f));
          sink->EndFigure(D2D1_FIGURE_END_CLOSED);
          sink->Close();
          render_target_->FillGeometry(bolt.Get(), brush_.Get());
        }
      }
    }
  }

  if (search_visible) {
    const D2D1_RECT_F& sbox = layout.search_box_rect;
    DrawRoundedCard(sbox, 10.0f, t.inset_bg, WithAlpha(t.primary, 0.35f), 0.75f);
    brush_->SetColor(ColorFromArgb(t.on_surface_variant));
    const float gcx = sbox.left + 14.0f;
    const float gcy = (sbox.top + sbox.bottom) * 0.5f - 1.0f;
    render_target_->DrawEllipse(
        D2D1::Ellipse(D2D1::Point2F(gcx, gcy), 3.6f, 3.6f), brush_.Get(), 1.2f);
    render_target_->DrawLine(D2D1::Point2F(gcx + 2.5f, gcy + 2.5f),
                             D2D1::Point2F(gcx + 4.8f, gcy + 4.8f),
                             brush_.Get(), 1.3f);

    const float text_left = sbox.left + 26.0f;
    const float text_right =
        search_query.empty() ? sbox.right - 10.0f : layout.search_clear_rect.left - 4.0f;
    const float field_w = (std::max)(20.0f, text_right - text_left);
    if (search_query.empty()) {
      DrawTextClipped(state_.labels.search, fmt_body_.Get(),
                      D2D1::RectF(text_left, sbox.top, text_right, sbox.bottom),
                      WithAlpha(t.on_surface_variant, 0.7f));
      if (interactive && caret_visible_) {
        brush_->SetColor(ColorFromArgb(t.primary));
        render_target_->DrawLine(
            D2D1::Point2F(text_left, sbox.top + 6.0f),
            D2D1::Point2F(text_left, sbox.bottom - 6.0f), brush_.Get(), 1.3f);
      }
    } else {
      const float q_width =
          MeasureTextWidth(search_query, fmt_body_.Get(), 4000.0f);
      const float shift = q_width > field_w ? field_w - q_width : 0.0f;
      render_target_->PushAxisAlignedClip(
          D2D1::RectF(text_left, sbox.top, text_right, sbox.bottom),
          D2D1_ANTIALIAS_MODE_ALIASED);
      DrawTextClipped(
          search_query, fmt_body_.Get(),
          D2D1::RectF(text_left + shift, sbox.top,
                      text_left + shift + (std::max)(field_w, q_width + 4.0f),
                      sbox.bottom),
          t.on_surface);
      render_target_->PopAxisAlignedClip();
      if (interactive && caret_visible_) {
        const float cx = (std::min)(text_right - 1.0f, text_left + q_width + 1.0f);
        brush_->SetColor(ColorFromArgb(t.primary));
        render_target_->DrawLine(
            D2D1::Point2F(cx, sbox.top + 6.0f),
            D2D1::Point2F(cx, sbox.bottom - 6.0f), brush_.Get(), 1.3f);
      }

      const D2D1_RECT_F& cr = layout.search_clear_rect;
      const float ccx = (cr.left + cr.right) * 0.5f;
      const float ccy = (cr.top + cr.bottom) * 0.5f;
      brush_->SetColor(ColorFromArgb(t.on_surface_variant));
      render_target_->FillEllipse(
          D2D1::Ellipse(D2D1::Point2F(ccx, ccy), 6.0f, 6.0f), brush_.Get());
      brush_->SetColor(ColorFromArgb(t.inset_bg));
      render_target_->DrawLine(D2D1::Point2F(ccx - 2.3f, ccy - 2.3f),
                               D2D1::Point2F(ccx + 2.3f, ccy + 2.3f),
                               brush_.Get(), 1.3f);
      render_target_->DrawLine(D2D1::Point2F(ccx + 2.3f, ccy - 2.3f),
                               D2D1::Point2F(ccx - 2.3f, ccy + 2.3f),
                               brush_.Get(), 1.3f);
    }
  }

  if (filtered_groups.empty()) {
    DrawTextClipped(state_.labels.no_proxies, fmt_body_.Get(),
                    layout.groups_viewport_rect,
                    WithAlpha(t.on_surface_variant, 0.75f),
                    DWRITE_TEXT_ALIGNMENT_CENTER);
  } else {
    D2D1_RECT_F vp = layout.groups_viewport_rect;
    vp.bottom = (std::min)(vp.bottom, max_bottom_dip);
    if (vp.bottom > vp.top) {
      render_target_->PushAxisAlignedClip(vp, D2D1_ANTIALIAS_MODE_ALIASED);
      render_target_->SetTransform(
          D2D1::Matrix3x2F::Translation(0.0f, -scroll_offset_dip));

      for (const auto& card : layout.group_cards) {
        if (card.group_index >= groups.size() ||
            card.card_rect.bottom - scroll_offset_dip < vp.top - 4.0f ||
            card.card_rect.top - scroll_offset_dip > vp.bottom + 4.0f) {
          continue;
        }
        DrawGroupCard(card, groups[card.group_index], interactive);
      }

      render_target_->SetTransform(D2D1::Matrix3x2F::Identity());
      render_target_->PopAxisAlignedClip();

      if (layout.max_scroll_dip > 0.5f) {
        const float full_vp_h =
            layout.groups_viewport_rect.bottom - layout.groups_viewport_rect.top;
        const float thumb_h = (std::max)(
            24.0f, full_vp_h * (full_vp_h / layout.groups_content_height_dip));
        const float ratio = scroll_offset_dip / layout.max_scroll_dip;
        const float thumb_y =
            layout.groups_viewport_rect.top + ratio * (full_vp_h - thumb_h);
        DrawRoundedCard(D2D1::RectF(vp.right - 3.5f, thumb_y, vp.right - 0.5f,
                                    thumb_y + thumb_h),
                        1.5f, WithAlpha(t.on_surface_variant, 0.32f));
      }
    }
  }

  render_target_->PopAxisAlignedClip();
  draw_alpha_scale_ = prev_alpha_scale;
}

void TrayPanelWindow::DrawGroupCard(const GroupCardLayout& card,
                                    const TrayPanelGroup& group,
                                    bool interactive) {
  const auto& t = state_.theme;
  const bool header_hovered =
      interactive && !card.expanded && hovered_key_ == card.header_key;
  DrawRoundedCard(card.card_rect, 14.0f,
                  header_hovered ? t.block_bg : t.card_bg);

  const float left_x = card.card_rect.left + 10.0f;
  const float header_top = card.card_rect.top + 10.0f;

  // Delay badge + bolt + chevron on right
  const float badge_right = card.test_rect.left - 6.0f;
  DrawDelayBadge(group.selected_delay, group.testing, badge_right,
                 header_top + 17.0f, false);

  const float delay_reserved =
      (group.testing || group.selected_delay.has_value()) ? 64.0f : 0.0f;
  const float title_max_right = badge_right - delay_reserved - 6.0f;
  const float type_w =
      group.type.empty()
          ? 0.0f
          : (std::min)(
                74.0f, MeasureTextWidth(group.type, fmt_badge_.Get(), 74.0f) + 10.0f);
  const float name_max_w =
      (std::max)(40.0f, title_max_right - left_x - (type_w > 0.0f ? type_w + 5.0f : 0.0f));
  const float name_w =
      (std::min)(name_max_w,
                 MeasureTextWidth(group.name, fmt_group_.Get(), name_max_w));
  DrawTextClipped(group.name, fmt_group_.Get(),
                  D2D1::RectF(left_x, header_top, left_x + name_w + 2.0f,
                              header_top + 18.0f),
                  t.on_surface);

  if (!group.type.empty()) {
    const float tx = left_x + name_w + 5.0f;
    const D2D1_RECT_F trect = D2D1::RectF(tx, header_top + 2.0f,
                                          tx + type_w, header_top + 17.0f);
    DrawRoundedCard(trect, 7.5f, t.inset_bg);
    DrawTextClipped(group.type, fmt_badge_center_.Get(), trect,
                    t.on_surface_variant);
  }

  const std::wstring selected_label =
      group.selected_proxy_name.empty() ? L"-" : group.selected_proxy_name;
  DrawTextClipped(selected_label, fmt_small_.Get(),
                  D2D1::RectF(left_x, header_top + 18.0f, title_max_right,
                              header_top + 34.0f),
                  t.on_surface_variant);

  const bool test_hovered =
      interactive && !group.testing && hovered_key_ == card.test_key;
  DrawRoundedCard(card.test_rect, 7.0f,
                  test_hovered ? t.inset_bg : t.block_bg);
  const float tcx = (card.test_rect.left + card.test_rect.right) * 0.5f;
  const float tcy = (card.test_rect.top + card.test_rect.bottom) * 0.5f;
  if (group.testing) {
    DrawSpinner(tcx, tcy, 4.5f, t.primary);
  } else {
    brush_->SetColor(ColorFromArgb(t.on_surface_variant));
    ComPtr<ID2D1PathGeometry> bolt;
    ComPtr<ID2D1GeometrySink> sink;
    if (SUCCEEDED(d2d_factory_->CreatePathGeometry(bolt.GetAddressOf())) &&
        SUCCEEDED(bolt->Open(sink.GetAddressOf()))) {
      sink->BeginFigure(D2D1::Point2F(tcx + 0.8f, tcy - 4.8f),
                        D2D1_FIGURE_BEGIN_FILLED);
      sink->AddLine(D2D1::Point2F(tcx - 3.5f, tcy + 0.4f));
      sink->AddLine(D2D1::Point2F(tcx - 0.4f, tcy + 0.4f));
      sink->AddLine(D2D1::Point2F(tcx - 1.2f, tcy + 4.8f));
      sink->AddLine(D2D1::Point2F(tcx + 3.5f, tcy - 0.4f));
      sink->AddLine(D2D1::Point2F(tcx + 0.4f, tcy - 0.4f));
      sink->EndFigure(D2D1_FIGURE_END_CLOSED);
      sink->Close();
      render_target_->FillGeometry(bolt.Get(), brush_.Get());
    }
  }

  // Chevron
  const float ccx = (card.chevron_rect.left + card.chevron_rect.right) * 0.5f;
  const float ccy = (card.chevron_rect.top + card.chevron_rect.bottom) * 0.5f;
  brush_->SetColor(ColorFromArgb(t.on_surface_variant));
  if (card.expanded) {
    render_target_->DrawLine(D2D1::Point2F(ccx - 3.5f, ccy - 1.5f),
                             D2D1::Point2F(ccx, ccy + 2.0f), brush_.Get(),
                             1.5f);
    render_target_->DrawLine(D2D1::Point2F(ccx, ccy + 2.0f),
                             D2D1::Point2F(ccx + 3.5f, ccy - 1.5f),
                             brush_.Get(), 1.5f);
  } else {
    render_target_->DrawLine(D2D1::Point2F(ccx - 1.5f, ccy - 3.5f),
                             D2D1::Point2F(ccx + 2.0f, ccy), brush_.Get(),
                             1.5f);
    render_target_->DrawLine(D2D1::Point2F(ccx + 2.0f, ccy),
                             D2D1::Point2F(ccx - 1.5f, ccy + 3.5f),
                             brush_.Get(), 1.5f);
  }

  for (const auto& tile : card.tiles) {
    if (tile.proxy_index < group.proxies.size()) {
      DrawProxyTile(tile, group.proxies[tile.proxy_index], interactive);
    }
  }
}

void TrayPanelWindow::DrawProxyTile(const ProxyTileLayout& tile,
                                    const TrayPanelProxy& proxy,
                                    bool interactive) {
  const auto& t = state_.theme;
  const bool hovered = interactive && hovered_key_ == tile.hit_key;
  const uint32_t bg = proxy.selected
                          ? WithAlpha(t.primary, 0.14f)
                          : (hovered ? t.inset_bg : t.block_bg);
  DrawRoundedCard(tile.rect, 10.0f, bg);

  const float x0 = tile.rect.left + 8.0f;
  const float x1 = tile.rect.right - 8.0f;
  const float top_y = tile.rect.top + 7.0f;
  const float bot_y = tile.rect.top + 23.0f;

  const float name_right = proxy.selected ? x1 - 15.0f : x1;
  DrawTextClipped(proxy.name,
                  proxy.selected ? fmt_body_semibold_.Get() : fmt_body_.Get(),
                  D2D1::RectF(x0, top_y, name_right, top_y + 16.0f),
                  proxy.selected ? t.primary : t.on_surface);

  if (proxy.selected) {
    const float cx = x1 - 5.5f;
    const float cy = top_y + 8.0f;
    brush_->SetColor(ColorFromArgb(t.primary));
    render_target_->FillEllipse(D2D1::Ellipse(D2D1::Point2F(cx, cy), 5.2f, 5.2f),
                                brush_.Get());
    brush_->SetColor(ColorFromArgb(t.on_primary));
    render_target_->DrawLine(D2D1::Point2F(cx - 2.2f, cy + 0.2f),
                             D2D1::Point2F(cx - 0.5f, cy + 2.0f),
                             brush_.Get(), 1.3f);
    render_target_->DrawLine(D2D1::Point2F(cx - 0.5f, cy + 2.0f),
                             D2D1::Point2F(cx + 2.4f, cy - 1.6f),
                             brush_.Get(), 1.3f);
  }

  const float badge_space =
      (proxy.testing || proxy.delay.has_value()) ? 46.0f : 0.0f;
  DrawTextClipped(proxy.type, fmt_badge_.Get(),
                  D2D1::RectF(x0, bot_y, (std::max)(x0 + 20.0f, x1 - badge_space),
                              bot_y + 15.0f),
                  t.on_surface_variant);
  DrawDelayBadge(proxy.delay, proxy.testing, x1, bot_y + 7.5f, true);
}

void TrayPanelWindow::DrawDelayBadge(const std::optional<int>& delay,
                                     bool testing,
                                     float right_x,
                                     float center_y,
                                     bool compact) {
  if (testing) {
    DrawSpinner(right_x - 7.0f, center_y, compact ? 4.2f : 5.0f,
                state_.theme.primary);
    return;
  }
  if (!delay.has_value()) {
    return;
  }
  const int val = *delay;
  const uint32_t fg = DelayColor(val, state_.theme);
  const std::wstring text = FormatDelayText(val, state_.labels, !compact);
  const float pad_x = compact ? 5.0f : 6.0f;
  const float max_w = compact ? 54.0f : 66.0f;
  const float w =
      (std::min)(max_w, MeasureTextWidth(text, fmt_badge_.Get(), max_w) +
                            pad_x * 2.0f);
  const D2D1_RECT_F rect =
      D2D1::RectF(right_x - w, center_y - 8.5f, right_x, center_y + 8.5f);
  DrawRoundedCard(rect, 8.5f, WithAlpha(fg, 0.14f));
  DrawTextClipped(text, fmt_badge_center_.Get(), rect, fg);
}

void TrayPanelWindow::DrawFooter(float y_top) {
  const auto& t = state_.theme;
  const float footer_dy = y_top - layout_.footer_y_dip;
  for (const auto& hit : layout_.hits) {
    if (hit.rect.top < layout_.footer_y_dip - 2.0f) {
      continue;
    }
    const D2D1_RECT_F rect = OffsetRectF(hit.rect, footer_dy);
    if (hit.kind == HitKind::kCopyEnv) {
      const bool hovered = hovered_key_ == hit.key;
      const uint32_t bg = copied_feedback_
                              ? WithAlpha(t.success, 0.16f)
                              : (hovered ? t.block_bg : t.card_bg);
      const uint32_t fg = copied_feedback_ ? t.success : t.on_surface_variant;
      DrawRoundedCard(rect, 10.0f, bg);

      wchar_t port_buf[64]{};
      ::StringCchPrintfW(port_buf, ARRAYSIZE(port_buf), L"%ls :%d",
                         state_.labels.copy_env_var.c_str(), state_.port);
      const std::wstring label(port_buf);

      float text_right = rect.right - 8.0f;
      if (!copied_feedback_ && !state_.shortcuts.copy_env.empty()) {
        const float sw = (std::min)(
            52.0f, MeasureTextWidth(state_.shortcuts.copy_env, fmt_badge_.Get(),
                                    52.0f) +
                       8.0f);
        const D2D1_RECT_F srect = D2D1::RectF(
            text_right - sw, rect.top + 6.0f, text_right, rect.bottom - 6.0f);
        DrawRoundedCard(srect, 4.0f, t.inset_bg);
        DrawTextClipped(state_.shortcuts.copy_env, fmt_badge_center_.Get(),
                        srect, t.on_surface_variant);
        text_right = srect.left - 4.0f;
      }

      const float cy = (rect.top + rect.bottom) * 0.5f;
      const float ix = rect.left + 12.0f;
      brush_->SetColor(ColorFromArgb(fg));
      if (copied_feedback_) {
        render_target_->DrawLine(D2D1::Point2F(ix - 3.0f, cy),
                                 D2D1::Point2F(ix - 0.5f, cy + 2.5f),
                                 brush_.Get(), 1.5f);
        render_target_->DrawLine(D2D1::Point2F(ix - 0.5f, cy + 2.5f),
                                 D2D1::Point2F(ix + 4.0f, cy - 2.5f),
                                 brush_.Get(), 1.5f);
      } else {
        render_target_->DrawLine(D2D1::Point2F(ix - 3.0f, cy - 3.0f),
                                 D2D1::Point2F(ix, cy), brush_.Get(), 1.3f);
        render_target_->DrawLine(D2D1::Point2F(ix, cy),
                                 D2D1::Point2F(ix - 3.0f, cy + 3.0f),
                                 brush_.Get(), 1.3f);
        render_target_->DrawLine(D2D1::Point2F(ix + 1.0f, cy + 3.0f),
                                 D2D1::Point2F(ix + 4.5f, cy + 3.0f),
                                 brush_.Get(), 1.3f);
      }
      DrawTextClipped(
          label, fmt_small_medium_.Get(),
          D2D1::RectF(ix + 8.0f, rect.top, text_right, rect.bottom), fg);
    } else if (hit.kind == HitKind::kShowWindow) {
      const bool hovered = hovered_key_ == hit.key;
      DrawRoundedCard(rect, 10.0f,
                      WithAlpha(t.primary, hovered ? 0.24f : 0.16f));
      float text_right = rect.right - 8.0f;
      if (!state_.shortcuts.show_window.empty()) {
        const float sw = (std::min)(
            52.0f, MeasureTextWidth(state_.shortcuts.show_window,
                                    fmt_badge_.Get(), 52.0f) +
                       8.0f);
        const D2D1_RECT_F srect = D2D1::RectF(
            text_right - sw, rect.top + 6.0f, text_right, rect.bottom - 6.0f);
        DrawRoundedCard(srect, 4.0f, WithAlpha(t.primary, 0.14f));
        DrawTextClipped(state_.shortcuts.show_window, fmt_badge_center_.Get(),
                        srect, t.primary);
        text_right = srect.left - 4.0f;
      }
      DrawTextClipped(
          state_.labels.show_window, fmt_small_medium_.Get(),
          D2D1::RectF(rect.left + 8.0f, rect.top, text_right, rect.bottom),
          t.primary, DWRITE_TEXT_ALIGNMENT_CENTER);
    }
  }
}

void TrayPanelWindow::DrawTextClipped(const std::wstring& text,
                                      IDWriteTextFormat* format,
                                      const D2D1_RECT_F& rect,
                                      uint32_t argb,
                                      DWRITE_TEXT_ALIGNMENT align) {
  if (!render_target_ || !brush_ || format == nullptr || text.empty()) {
    return;
  }
  const float w = (std::max)(1.0f, rect.right - rect.left);
  const float h = (std::max)(1.0f, rect.bottom - rect.top);
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(dwrite_factory_->CreateTextLayout(
          text.c_str(), static_cast<UINT32>(text.size()), format, w, h,
          layout.GetAddressOf()))) {
    return;
  }
  layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  if (align != DWRITE_TEXT_ALIGNMENT_LEADING) {
    layout->SetTextAlignment(align);
  }
  brush_->SetColor(ColorFromArgb(argb));
  render_target_->DrawTextLayout(D2D1::Point2F(rect.left, rect.top),
                                 layout.Get(), brush_.Get(),
                                 D2D1_DRAW_TEXT_OPTIONS_CLIP);
}

float TrayPanelWindow::MeasureTextWidth(const std::wstring& text,
                                        IDWriteTextFormat* format,
                                        float max_width) {
  if (!dwrite_factory_ || format == nullptr || text.empty()) {
    return 0.0f;
  }
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(dwrite_factory_->CreateTextLayout(
          text.c_str(), static_cast<UINT32>(text.size()), format, max_width,
          40.0f, layout.GetAddressOf()))) {
    return 0.0f;
  }
  DWRITE_TEXT_METRICS metrics{};
  if (FAILED(layout->GetMetrics(&metrics))) {
    return 0.0f;
  }
  return metrics.widthIncludingTrailingWhitespace;
}

void TrayPanelWindow::DrawSpinner(float cx,
                                  float cy,
                                  float radius,
                                  uint32_t argb) {
  if (!d2d_factory_ || !render_target_ || !brush_) {
    return;
  }
  ComPtr<ID2D1PathGeometry> geo;
  ComPtr<ID2D1GeometrySink> sink;
  if (FAILED(d2d_factory_->CreatePathGeometry(geo.GetAddressOf())) ||
      FAILED(geo->Open(sink.GetAddressOf()))) {
    return;
  }
  const float a0 = spinner_angle_deg_ * kPi / 180.0f;
  const float a1 = (spinner_angle_deg_ + 250.0f) * kPi / 180.0f;
  sink->BeginFigure(
      D2D1::Point2F(cx + radius * std::cos(a0), cy + radius * std::sin(a0)),
      D2D1_FIGURE_BEGIN_HOLLOW);
  sink->AddArc(D2D1::ArcSegment(
      D2D1::Point2F(cx + radius * std::cos(a1), cy + radius * std::sin(a1)),
      D2D1::SizeF(radius, radius), 0.0f, D2D1_SWEEP_DIRECTION_CLOCKWISE,
      D2D1_ARC_SIZE_LARGE));
  sink->EndFigure(D2D1_FIGURE_END_OPEN);
  sink->Close();
  brush_->SetColor(ColorFromArgb(argb));
  render_target_->DrawGeometry(geo.Get(), brush_.Get(), 1.6f);
}

void TrayPanelWindow::DrawRoundedCard(const D2D1_RECT_F& rect,
                                      float radius,
                                      uint32_t fill_argb,
                                      uint32_t stroke_argb,
                                      float stroke_width) {
  if (!render_target_ || !brush_) {
    return;
  }
  const D2D1_ROUNDED_RECT rr = D2D1::RoundedRect(rect, radius, radius);
  brush_->SetColor(ColorFromArgb(fill_argb));
  render_target_->FillRoundedRectangle(rr, brush_.Get());
  if ((stroke_argb >> 24) != 0) {
    brush_->SetColor(ColorFromArgb(stroke_argb));
    render_target_->DrawRoundedRectangle(rr, brush_.Get(), stroke_width);
  }
}

float TrayPanelWindow::DipFromPx(int px) const {
  return static_cast<float>(px) * 96.0f / static_cast<float>(dpi_);
}

int TrayPanelWindow::PxFromDip(float dip) const {
  return static_cast<int>(
      std::lround(dip * static_cast<float>(dpi_) / 96.0f));
}

D2D1_COLOR_F TrayPanelWindow::ColorFromArgb(uint32_t argb,
                                            float alpha_scale) const {
  const float a =
      (static_cast<float>((argb >> 24) & 0xFFU) / 255.0f) * alpha_scale *
      draw_alpha_scale_;
  const float r = static_cast<float>((argb >> 16) & 0xFFU) / 255.0f;
  const float g = static_cast<float>((argb >> 8) & 0xFFU) / 255.0f;
  const float b = static_cast<float>(argb & 0xFFU) / 255.0f;
  return D2D1::ColorF(r, g, b, a);
}

LRESULT CALLBACK TrayPanelWindow::WindowProc(HWND hwnd,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* self = static_cast<TrayPanelWindow*>(cs->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
    return TRUE;
  }
  auto* self =
      reinterpret_cast<TrayPanelWindow*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->HandleMessage(hwnd, message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT TrayPanelWindow::HandleMessage(HWND hwnd,
                                       UINT message,
                                       WPARAM wparam,
                                       LPARAM lparam) {
  static const UINT pointer_down_message =
      ::RegisterWindowMessageW(L"FlClashTrayIconPointerDown");
  if (pointer_down_message != 0 && message == pointer_down_message) {
    NoteTrayIconPointerDown();
    return 0;
  }
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam != 0) {
        return 0;
      }
      break;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps{};
      ::BeginPaint(hwnd, &ps);
      Render();
      ::EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) {
        HideInternal(true, true);
      }
      return 0;
    case WM_DPICHANGED: {
      dpi_ = HIWORD(wparam);
      const auto* suggested = reinterpret_cast<const RECT*>(lparam);
      if (render_target_) {
        render_target_->SetDpi(static_cast<float>(dpi_),
                               static_cast<float>(dpi_));
      }
      if (is_visible_) {
        ::SetWindowPos(hwnd, nullptr, suggested->left, suggested->top,
                       suggested->right - suggested->left,
                       suggested->bottom - suggested->top,
                       SWP_NOZORDER | SWP_NOACTIVATE);
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_DISPLAYCHANGE:
    case WM_POWERBROADCAST:
      if (is_visible_) {
        HideInternal(true, false);
      }
      return 0;
    case WM_SETCURSOR:
      if (LOWORD(lparam) == HTCLIENT) {
        POINT pt{};
        ::GetCursorPos(&pt);
        ::ScreenToClient(hwnd, &pt);
        const auto hit = HitTest(DipFromPx(pt.x), DipFromPx(pt.y));
        LPCWSTR cursor_id = IDC_ARROW;
        if (hit.has_value() && hit->enabled) {
          cursor_id =
              hit->kind == HitKind::kSearchBox ? IDC_IBEAM : IDC_HAND;
        }
        ::SetCursor(::LoadCursorW(nullptr, cursor_id));
        return TRUE;
      }
      break;
    case WM_MOUSEMOVE: {
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT tme{sizeof(TRACKMOUSEEVENT), TME_LEAVE, hwnd, 0};
        ::TrackMouseEvent(&tme);
        tracking_mouse_ = true;
      }
      const float dx = DipFromPx(GET_X_LPARAM(lparam));
      const float dy = DipFromPx(GET_Y_LPARAM(lparam));
      const auto hit = HitTest(dx, dy);
      const uint64_t next_hover =
          (hit.has_value() && hit->enabled) ? hit->key : 0;
      if (next_hover != hovered_key_) {
        hovered_key_ = next_hover;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      tracking_mouse_ = false;
      if (hovered_key_ != 0) {
        hovered_key_ = 0;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONDOWN: {
      ::SetCapture(hwnd);
      const float dx = DipFromPx(GET_X_LPARAM(lparam));
      const float dy = DipFromPx(GET_Y_LPARAM(lparam));
      const auto hit = HitTest(dx, dy);
      pressed_key_ = (hit.has_value() && hit->enabled) ? hit->key : 0;
      return 0;
    }
    case WM_LBUTTONUP: {
      if (::GetCapture() == hwnd) {
        ::ReleaseCapture();
      }
      const float dx = DipFromPx(GET_X_LPARAM(lparam));
      const float dy = DipFromPx(GET_Y_LPARAM(lparam));
      const auto hit = HitTest(dx, dy);
      const uint64_t released_key = pressed_key_;
      pressed_key_ = 0;
      if (hit.has_value() && hit->enabled && hit->key == released_key) {
        DispatchHit(*hit);
      }
      return 0;
    }
    case WM_MOUSEWHEEL: {
      if (layout_.max_scroll_dip > 0.0f) {
        const short delta = GET_WHEEL_DELTA_WPARAM(wparam);
        const float step =
            (static_cast<float>(delta) / static_cast<float>(WHEEL_DELTA)) *
            48.0f;
        const float prev = scroll_offset_dip_;
        scroll_offset_dip_ -= step;
        ClampScroll();
        if (std::fabs(scroll_offset_dip_ - prev) > 0.1f) {
          ::InvalidateRect(hwnd, nullptr, FALSE);
        }
      }
      return 0;
    }
    case WM_KEYDOWN: {
      if (wparam == VK_ESCAPE) {
        if (search_visible_ && !search_query_.empty()) {
          search_query_.clear();
          scroll_offset_dip_ = 0.0f;
          ApplyLocalLayoutChange(false);
        } else if (search_visible_) {
          search_visible_ = false;
          ApplyLocalLayoutChange(true);
        } else {
          HideInternal(true, false);
        }
        return 0;
      }
      if (wparam == static_cast<WPARAM>('F') &&
          (::GetKeyState(VK_CONTROL) & 0x8000) != 0) {
        search_visible_ = !search_visible_;
        if (!search_visible_) {
          search_query_.clear();
        }
        caret_visible_ = true;
        ApplyLocalLayoutChange(true);
        return 0;
      }
      if (wparam == VK_BACK && search_visible_ && !search_query_.empty()) {
        const wchar_t tail = search_query_.back();
        search_query_.pop_back();
        if (tail >= 0xDC00 && tail <= 0xDFFF && !search_query_.empty()) {
          const wchar_t prev = search_query_.back();
          if (prev >= 0xD800 && prev <= 0xDBFF) {
            search_query_.pop_back();
          }
        }
        caret_visible_ = true;
        scroll_offset_dip_ = 0.0f;
        ApplyLocalLayoutChange(false);
        return 0;
      }
      break;
    }
    case WM_CHAR: {
      if (search_visible_) {
        const wchar_t ch = static_cast<wchar_t>(wparam);
        if (ch >= 0x20 && ch != 0x7F) {
          search_query_.push_back(ch);
          caret_visible_ = true;
          scroll_offset_dip_ = 0.0f;
          ApplyLocalLayoutChange(false);
        }
        return 0;
      }
      break;
    }
    case WM_TIMER:
      if (wparam == kSpinnerTimerId) {
        spinner_angle_deg_ = std::fmod(spinner_angle_deg_ + 18.0f, 360.0f);
        ::InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (wparam == kCopyFeedbackTimerId) {
        ::KillTimer(hwnd, kCopyFeedbackTimerId);
        copied_feedback_ = false;
        ::InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (wparam == kCaretTimerId) {
        caret_visible_ = !caret_visible_;
        ::InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (wparam == kAnimTimerId) {
        if (!is_visible_) {
          ::KillTimer(hwnd, kAnimTimerId);
          anim_timer_running_ = false;
          return 0;
        }
        const bool was_height_anim = height_anim_active_;
        StepAnimationsAt(::GetTickCount64());
        if (!HasActiveAnimations()) {
          ::KillTimer(hwnd, kAnimTimerId);
          anim_timer_running_ = false;
        }
        if (was_height_anim || height_anim_active_) {
          UpdateWindowSizeIfVisible();
        }
        ::InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      break;
    case WM_DESTROY:
      ::KillTimer(hwnd, kSpinnerTimerId);
      ::KillTimer(hwnd, kCopyFeedbackTimerId);
      ::KillTimer(hwnd, kCaretTimerId);
      ::KillTimer(hwnd, kAnimTimerId);
      anim_timer_running_ = false;
      CancelAnimations();
      hwnd_ = nullptr;
      is_visible_ = false;
      return 0;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace tray
