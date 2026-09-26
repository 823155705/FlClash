# Android APK 签名配置

本 Fork 的 `widget` 分支会用 **你自己的 keystore** 编译 release APK。  
官方 APK 是官方开发者签名，和你的签名不同，因此：

1. 第一次安装你的 Widget 版：**先卸载官方 FlClash**，再安装。
2. 之后只要一直用同一个 keystore，你的 APK 可以直接覆盖升级，配置不丢。

## 1. 生成 keystore（只需做一次）

在本机执行：

```bash
./scripts/generate-keystore.sh
```

脚本会：

- 生成 `signing/flclash-widget.jks`
- 打印 `KEYSTORE`（base64）、`KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD`

**请离线备份 jks 和三个密码。** 丢了之后无法对旧安装做覆盖升级。

也可手动指定密码：

```bash
STORE_PASSWORD='你的库密码' KEY_PASSWORD='你的密钥密码' ./scripts/generate-keystore.sh
```

## 2. 配置 GitHub Secrets

打开仓库：**Settings → Secrets and variables → Actions → New repository secret**

| Name | Value |
|------|--------|
| `KEYSTORE` | `base64` 后的 `.jks` 内容（脚本已打印） |
| `KEY_ALIAS` | 例如 `flclash` |
| `STORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | key 密码 |

若用 CLI：

```bash
base64 < signing/flclash-widget.jks | tr -d '\n' | gh secret set KEYSTORE
gh secret set KEY_ALIAS --body "flclash"
gh secret set STORE_PASSWORD --body "..."
gh secret set KEY_PASSWORD --body "..."
```

## 3. 构建产物

`build-android.yml` 会在以下情况自动编译 arm64 APK：

- push 到 `widget` 分支
- 打 `v*` tag（同时创建 GitHub Release）
- 手动 `workflow_dispatch`

构建读取官方脚本已支持的签名字段（写入 `android/local.properties`）：

- `keyAlias`
- `storePassword`
- `keyPassword`

jks 文件路径为 `android/app/keystore.jks`（与官方 `build.yaml` 一致）。

## 4. 本地验证签名

```bash
keytool -printcert -jarfile dist/**/xxx.apk
```

确认 `Owner` 与你生成 keystore 时的 DN 一致。
