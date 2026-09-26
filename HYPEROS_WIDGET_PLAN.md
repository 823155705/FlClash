# FlClash AppWidget · HyperOS 适配方案（修订）

## 目标

在现有 Android AppWidget（#2220 移植版）上增加 HyperOS 适配：

- **小米/HyperOS/MIUI 能用的 API 优先走 OEM 通道**
- 其他 Android ROM 自动回退标准 AppWidget
- 优先尺寸：2×2、4×2 卡片
- 处理杀后台、锁屏刷新失败、点击无响应、VPN 状态不同步

## 策略：OEM 优先，标准兜底

```
刷新 / 状态推送
        │
        ▼
┌───────────────────┐
│ HyperOsMiuiBridge │  检测 miui.os.Build / HyperOS
└─────────┬─────────┘
          │
   ┌──────┴──────┐
   │ 小米通道可用 │──► MIUI launcher 广播 / MIUI 增强 API
   └──────┬──────┘
          │ 不可用或未生效
          ▼
   标准 AppWidgetManager.updateAppWidget
          │
          ▼
   其他手机：纯 AOSP Widget 路径（现状）
```

### 小米侧优先能力（反射 / 可选，不硬依赖 SDK）

1. **检测**：`miui.os.Build.IS_HYPEROS` / `IS_MIUI`，失败则 `SystemProperties`
2. **刷新**：向 `com.miui.home` 等 launcher 发 MIUI widget update 广播
3. **后台保活增强**：HyperOS 上用 `AlarmManager.setExactAndAllowWhileIdle` + 解锁/亮屏重绘
4. **尺寸**：4×2 / 2×2 提供 `targetCellWidth/Height` + `previewLayout`，HyperOS 桌面可直接预览
5. **可选增强**：若存在 MIUI LauncherProvider 等类，做能力探测日志，便于后续加深集成

### 回退保证

- 所有 MIUI 调用包在 try/catch + 存在性探测中
- 标准 `WidgetUi.bind` 始终执行，OEM 广播只是加速层
- 非小米设备：`HyperOsMiuiBridge` 几乎为空操作，行为与现网一致

## 架构

```
com.follow.clash
├── WidgetUi / WidgetProvider / WidgetProviderWide   # 标准渲染（2×2 / 4×2）
├── WidgetDataStore / WidgetRefresher                # 状态 + 刷新入口
└── hyperos
    ├── HyperOsCompat              # 机型/系统探测
    ├── HyperOsMiuiBridge          # 小米 API 优先通道
    ├── HyperOsRefreshScheduler    # Alarm + 解锁/亮屏 + BOOT
    ├── HyperOsStyle               # 卡片圆角/配色 token
    └── HyperOsBootstrap           # Application 一处 init
```

## 代码改动边界

**新增（独立目录）**

- `hyperos/*`
- `WidgetUi.kt`、`WidgetProviderWide.kt`
- `res/layout/widget_layout_4x2.xml`、`res/xml/widget_info_4x2.xml`

**最小修改（方便 upstream 同步）**

- `WidgetRefresher.refreshAll` → 转调 `HyperOsMiuiBridge.refreshWidgets`
- `WidgetProvider.updateWidget` → 委托 `WidgetUi.bind`（去重）
- `FlClashApplication.onCreate` → 一行 `HyperOsBootstrap.init`
- `AndroidManifest`：4×2 receiver、`BOOT_COMPLETED`

## UI（HyperOS 卡片）

- 圆角 20–28dp，浅灰/深灰自适应
- 2×2：状态+开关、节点、模式、上下行速度
- 4×2：同上 + 实时曲线
- 文案中文优先，信息密度接近系统小部件

## 手机模拟器预览

产出单文件 `index.html`（移动优先、内联 CSS/JS）：

- 可切换 2×2 / 4×2
- 可点开关、切模式、切节点
- 深/浅色
- 作为「应用」在手机模拟器直接试

## 测试清单

- [ ] 添加/删除 2×2、4×2
- [ ] 重启后状态与点击
- [ ] 杀后台后仍能刷新
- [ ] 深/浅色主题
- [ ] 开关 VPN、切节点、Rule/Global/Direct
- [ ] 小米设备：MIUI 通道生效日志
- [ ] 非小米设备：标准路径无回归
- [ ] HyperOS 桌面不同网格尺寸
