# FlClash 定制版

上游版本来自 chen08209/FlClash。应用流量统计位于 `lib/manager/app_traffic_tracker.dart`、`lib/database/app_traffic.dart` 和 `lib/views/traffic/app_traffic.dart`。

macOS 本地构建使用 Flutter 3.50.1、Go 1.27 和 Rust：

```bash
APP_UPDATE_REPOSITORY=<GitHub用户名>/FlClash ./tool/build_local_macos.sh
```

安装包在 `dist/`。更新源通过构建参数 `APP_UPDATE_REPOSITORY` 指定，未指定的上游构建仍然使用原仓库。定制构建传入 `APP_TRAFFIC_CUSTOM_BUILD=true`，支持同一版本号下按构建号检查修复包。

在 `custom` 分支提交目标版本后，推送与 `pubspec.yaml` 中 `version` 一致的 `vX.Y.Z+构建号` 标签。GitHub Actions 中 `build` 的 `custom-installers` 任务会从该标签对应的提交打包，并跳过上游全量测试检查。示例中 `2026112601` 必须先写入 `pubspec.yaml` 的构建号。

```bash
git push origin custom
git tag v0.9.5+2026112601 custom
git push origin refs/tags/v0.9.5+2026112601
```

如果推送标签后没有新的构建任务，可以在 GitHub Actions 的 `Build custom installers` 中选择该标签手动运行，或执行 `gh workflow run custom-release.yaml --ref v0.9.5+2026112601`。

Actions 产物包括 macOS Apple Silicon 和 Intel 的 DMG、Windows x64 安装版和便携 ZIP，以及 Android 的 arm64-v8a、armeabi-v7a 和 x86_64 APK。Android 构建产物使用一次性签名，只用于打包和传输。发布前用本地发布密钥重新签署 APK 并验证签名，检查安装包完整性，合并生成 `FlClash-X.Y.Z.构建号-SHA256SUMS`（例如 `FlClash-0.9.5.2026112601-SHA256SUMS`），再用同一个标签创建 GitHub Release。

macOS 应用内更新沿用上游官方实现（校验 SHA-256、解包替换并在失败时回滚与报错）。应用配置和统计数据库位于应用包外，覆盖安装继续使用原数据。

数据库版本号继续跟随上游，统计表在打开数据库时按实际形状补齐，避免占用上游下一次迁移的版本号。缺少 `profiles.match_target` 的历史定制版 schema 3 也会补齐该列，统计历史表保持原结构。
