# 应用流量定制版

上游版本来自 chen08209/FlClash。应用流量统计位于 `lib/manager/app_traffic_tracker.dart`、`lib/database/app_traffic.dart` 和 `lib/views/traffic/app_traffic.dart`。

macOS 本地构建使用 Flutter 3.47.6、Go 1.27 和 Rust：

```bash
APP_UPDATE_REPOSITORY=<GitHub用户名>/FlClash ./tool/build_local_macos.sh
```

安装包在 `dist/`。更新源通过构建参数 `APP_UPDATE_REPOSITORY` 指定，未指定的上游构建仍然使用原仓库。定制构建传入 `APP_TRAFFIC_CUSTOM_BUILD=true`，支持同一版本号下按构建号检查修复包。

在 fork 的 GitHub Actions 中手动运行 `Custom app traffic release`，可为选定提交构建 macOS（Apple Silicon 和 Intel）、Windows（x64）和 Android 安装包。运行成功后下载各平台构建产物，用本地发布密钥重新签署 Android APK，验证签名，再生成 `SHA256SUMS` 并发布到该 fork。Android 构建产物使用一次性签名，只用于打包和传输。

macOS 应用内更新会校验下载文件 SHA-256、包签名和 Bundle ID，等待旧进程退出后替换并重启，旧应用保留在安装日志目录内，文件替换失败会恢复旧应用。应用配置和统计数据库位于应用包外，覆盖安装继续使用原数据。

数据库版本号继续跟随上游，统计表在打开数据库时按实际形状补齐，避免占用上游下一次迁移的版本号。缺少 `profiles.match_target` 的历史定制版 schema 3 也会补齐该列，统计历史表保持原结构。
