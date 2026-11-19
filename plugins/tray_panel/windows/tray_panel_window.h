#ifndef FLUTTER_PLUGIN_TRAY_PANEL_WINDOW_H_
#define FLUTTER_PLUGIN_TRAY_PANEL_WINDOW_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <d2d1.h>
#include <dwrite.h>
#include <shellapi.h>

#include <cstdint>
#include <functional>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "tray_panel_model.h"

namespace tray {

template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() { Reset(); }

  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  ComPtr(ComPtr&& other) noexcept : ptr_(other.ptr_) { other.ptr_ = nullptr; }

  ComPtr& operator=(ComPtr&& other) noexcept {
    if (this != &other) {
      Reset();
      ptr_ = other.ptr_;
      other.ptr_ = nullptr;
    }
    return *this;
  }

  void Reset() {
    if (ptr_ != nullptr) {
      ptr_->Release();
      ptr_ = nullptr;
    }
  }

  T* Get() const { return ptr_; }
  T** GetAddressOf() {
    Reset();
    return &ptr_;
  }

  T* operator->() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }

 private:
  T* ptr_ = nullptr;
};

class TrayPanelWindow {
 public:
  using VisibilityCallback = std::function<void(bool visible)>;
  using ActionCallback =
      std::function<void(const std::string& action,
                         const flutter::EncodableMap& payload)>;

  TrayPanelWindow(VisibilityCallback on_visibility_changed,
                  ActionCallback on_action);
  ~TrayPanelWindow();

  TrayPanelWindow(const TrayPanelWindow&) = delete;
  TrayPanelWindow& operator=(const TrayPanelWindow&) = delete;

  void SetOwner(HWND owner_hwnd, UINT tray_icon_id);
  bool SetState(const TrayPanelState& state);
  void SetTraffic(const TrayPanelTraffic& traffic);

  bool Open();
  bool Close();
  bool Toggle();
  void Destroy();

  void NoteTrayIconPointerDown();
  bool IsVisible() const { return is_visible_; }

 private:
  enum class HitKind {
    kNone,
    kToggleRunning,
    kShowWindow,
    kQuit,
    kModeRule,
    kModeGlobal,
    kModeDirect,
    kToggleTun,
    kToggleSystemProxy,
    kToggleSpeedStats,
    kToggleMonochrome,
    kToggleAutoLaunch,
    kSearchToggle,
    kSearchBox,
    kSearchClear,
    kTestAllDelays,
    kGroupHeader,
    kGroupTestDelay,
    kProxyTile,
    kCopyEnv,
  };

  struct HitTarget {
    uint64_t key = 0;
    HitKind kind = HitKind::kNone;
    D2D1_RECT_F rect{};
    bool enabled = true;
    bool in_scroll_viewport = false;
    size_t group_index = 0;
    size_t proxy_index = 0;
  };

  struct FilteredGroup {
    size_t group_index = 0;
    std::vector<size_t> proxy_indices;
    bool expanded = false;
  };

  struct ProxyTileLayout {
    size_t group_index = 0;
    size_t proxy_index = 0;
    D2D1_RECT_F rect{};
    uint64_t hit_key = 0;
  };

  struct GroupCardLayout {
    size_t group_index = 0;
    bool expanded = false;
    D2D1_RECT_F card_rect{};
    D2D1_RECT_F header_rect{};
    D2D1_RECT_F test_rect{};
    D2D1_RECT_F chevron_rect{};
    uint64_t header_key = 0;
    uint64_t test_key = 0;
    std::vector<ProxyTileLayout> tiles;
  };

  struct PanelLayout {
    float panel_height_dip = 240.0f;
    float max_panel_height_dip = 600.0f;
    float divider_y_dip = 0.0f;
    float footer_y_dip = 0.0f;
    D2D1_RECT_F mode_segment_rects[3]{};
    D2D1_RECT_F search_box_rect{};
    D2D1_RECT_F search_clear_rect{};
    D2D1_RECT_F groups_header_rect{};
    D2D1_RECT_F groups_viewport_rect{};
    float groups_content_height_dip = 0.0f;
    float max_scroll_dip = 0.0f;
    std::vector<GroupCardLayout> group_cards;
    std::vector<HitTarget> hits;
  };

  struct OutgoingProxiesSnapshot {
    bool valid = false;
    bool search_visible = false;
    bool testing_all = false;
    std::wstring search_query;
    std::vector<TrayPanelGroup> groups;
    std::vector<FilteredGroup> filtered_groups;
    PanelLayout layout;
    float scroll_offset_dip = 0.0f;

    void Reset() {
      valid = false;
      search_visible = false;
      testing_all = false;
      search_query.clear();
      groups.clear();
      filtered_groups.clear();
      layout = PanelLayout{};
      scroll_offset_dip = 0.0f;
    }
  };

  static LRESULT CALLBACK WindowProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  bool EnsureWindowCreated();
  bool EnsureFactories();
  bool EnsureRenderTarget();
  void DiscardRenderResources();
  void ApplyBackdropAndTheme();
  void UpdateDpiForRect(const RECT& anchor_rect);
  void ComputeWindowBounds(bool reposition,
                           int* out_x,
                           int* out_y,
                           int* out_w,
                           int* out_h);
  void UpdateWindowSizeIfVisible();

  void HideInternal(bool notify, bool from_deactivate);
  void SyncTimers();
  void RebuildFilteredGroups();
  void RebuildLayout();
  void ClampScroll();
  void ApplyLocalLayoutChange(bool sync_timers);
  void StartHeightAnimationIfNeeded(float prev_height_dip);
  void SnapAnimationsToCurrentState();
  void CancelAnimations();
  void StepAnimationsAt(ULONGLONG now);
  bool HasActiveAnimations() const;
  float CurrentPanelHeightDip() const;
  D2D1_RECT_F ModeSegmentRect(const std::string& mode) const;

  std::optional<HitTarget> HitTest(float dip_x, float dip_y) const;
  void DispatchHit(const HitTarget& hit);

  void Render();
  void DrawHeader(float y_top);
  void DrawOutboundMode(float y_top);
  void DrawQuickToggles(float y_top);
  void DrawAnimatedProxiesSection(float max_bottom_dip);
  void DrawProxiesSectionContent(
      const std::vector<TrayPanelGroup>& groups,
      const std::vector<FilteredGroup>& filtered_groups,
      const PanelLayout& layout,
      bool search_visible,
      bool testing_all,
      const std::wstring& search_query,
      float scroll_offset_dip,
      float max_bottom_dip,
      float alpha_scale,
      bool interactive);
  void DrawGroupCard(const GroupCardLayout& card,
                     const TrayPanelGroup& group,
                     bool interactive);
  void DrawProxyTile(const ProxyTileLayout& tile,
                     const TrayPanelProxy& proxy,
                     bool interactive);
  void DrawDelayBadge(const std::optional<int>& delay,
                      bool testing,
                      float right_x,
                      float center_y,
                      bool compact);
  void DrawFooter(float y_top);
  void DrawTextClipped(
      const std::wstring& text,
      IDWriteTextFormat* format,
      const D2D1_RECT_F& rect,
      uint32_t argb,
      DWRITE_TEXT_ALIGNMENT align = DWRITE_TEXT_ALIGNMENT_LEADING);
  float MeasureTextWidth(const std::wstring& text,
                         IDWriteTextFormat* format,
                         float max_width = 1000.0f);
  void DrawSpinner(float cx, float cy, float radius, uint32_t argb);
  void DrawRoundedCard(const D2D1_RECT_F& rect,
                       float radius,
                       uint32_t fill_argb,
                       uint32_t stroke_argb = 0,
                       float stroke_width = 0.75f);

  float DipFromPx(int px) const;
  int PxFromDip(float dip) const;
  D2D1_COLOR_F ColorFromArgb(uint32_t argb, float alpha_scale = 1.0f) const;

  VisibilityCallback on_visibility_changed_;
  ActionCallback on_action_;

  HWND owner_hwnd_ = nullptr;
  UINT tray_icon_id_ = 1;
  HWND hwnd_ = nullptr;
  UINT dpi_ = USER_DEFAULT_SCREEN_DPI;
  bool class_registered_ = false;
  bool is_visible_ = false;
  bool has_state_ = false;
  bool tracking_mouse_ = false;

  TrayPanelState state_;
  TrayPanelTraffic traffic_;
  std::set<std::string> expanded_groups_;
  bool search_visible_ = false;
  std::wstring search_query_;
  std::vector<FilteredGroup> filtered_groups_;
  PanelLayout layout_;

  float scroll_offset_dip_ = 0.0f;
  float work_height_dip_ = 800.0f;
  uint64_t hovered_key_ = 0;
  uint64_t pressed_key_ = 0;
  bool copied_feedback_ = false;
  bool caret_visible_ = true;
  float spinner_angle_deg_ = 0.0f;
  bool anchor_bottom_ = true;
  bool anim_timer_running_ = false;
  float draw_alpha_scale_ = 1.0f;

  std::string last_mode_;
  bool mode_anim_active_ = false;
  ULONGLONG mode_anim_start_tick_ = 0;
  D2D1_RECT_F mode_anim_from_rect_{};
  D2D1_RECT_F mode_anim_to_rect_{};
  D2D1_RECT_F pill_current_rect_{};

  bool height_anim_active_ = false;
  ULONGLONG height_anim_start_tick_ = 0;
  float anim_start_height_dip_ = 240.0f;
  float anim_target_height_dip_ = 240.0f;
  float anim_current_height_dip_ = 240.0f;

  bool proxies_anim_active_ = false;
  ULONGLONG proxies_anim_start_tick_ = 0;
  float proxies_anim_progress_ = 1.0f;
  OutgoingProxiesSnapshot outgoing_proxies_;

  RECT last_icon_rect_{};
  bool has_last_icon_rect_ = false;
  ULONGLONG last_deactivate_tick_ = 0;
  bool deactivated_on_tray_icon_ = false;
  ULONGLONG suppress_toggle_until_tick_ = 0;

  ComPtr<ID2D1Factory> d2d_factory_;
  ComPtr<IDWriteFactory> dwrite_factory_;
  ComPtr<ID2D1HwndRenderTarget> render_target_;
  ComPtr<ID2D1SolidColorBrush> brush_;
  ComPtr<IDWriteInlineObject> ellipsis_trimming_;

  ComPtr<IDWriteTextFormat> fmt_title_;
  ComPtr<IDWriteTextFormat> fmt_group_;
  ComPtr<IDWriteTextFormat> fmt_body_;
  ComPtr<IDWriteTextFormat> fmt_body_semibold_;
  ComPtr<IDWriteTextFormat> fmt_small_;
  ComPtr<IDWriteTextFormat> fmt_small_medium_;
  ComPtr<IDWriteTextFormat> fmt_badge_;
  ComPtr<IDWriteTextFormat> fmt_badge_center_;
};

}  // namespace tray

#endif  // FLUTTER_PLUGIN_TRAY_PANEL_WINDOW_H_
