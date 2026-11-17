# 发布与公证 / Release & Notarization

TinyTodo 直接分发（DMG），使用 Developer ID 签名 + Apple 公证，不走 App Store。
本机复用的是这台机器上已验证可用的证书与 notarytool profile，与 AgentSpace / MacPilot 等项目的发布配置一致。

## 本机配置

| 项 | 值 |
| --- | --- |
| Team ID | `U8U443D7ZL` |
| 签名证书 | `Developer ID Application: Guofeng Liu (U8U443D7ZL)`（login keychain） |
| 公证凭据 | notarytool keychain profile `agentspace-notary`（也可用 `asc` 的 API key） |
| 公证校验 | `xcrun notarytool history --keychain-profile agentspace-notary` 必须成功才算可用 |
| Developer ID 私钥 | 已在 login keychain；不在仓库、不在文档、不输出 |

凭据不会写入仓库或日志。profile 名称不代表可用：`scripts/notarize.sh` 会先实际调用
`notarytool history`，失败时再尝试 `asc notarization list`，两者都失败才报错并提示恢复命令。

## 一键发布

```bash
# 1) Release 构建 + Developer ID 签名（hardened runtime + secure timestamp）+ 生成 DMG
bash scripts/release.sh

# 2) 公证：先公证 app、staple；再用 staple 后的 app 重建 DMG、签名 DMG、公证、staple
bash scripts/notarize.sh
```

`scripts/release.sh` 的签名参数：

- `CODE_SIGN_STYLE=Manual`、`CODE_SIGN_IDENTITY="Developer ID Application: …"`
- `ENABLE_HARDENED_RUNTIME=YES`
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` —— 不加这一项，Xcode 会写入
  `com.apple.security.get-task-allow`，公证会以 *"The executable requests the
  com.apple.security.get-task-allow entitlement"* 拒绝（本次已实际遇到并修复）
- `OTHER_CODE_SIGN_FLAGS="--timestamp"`

## 公证顺序（重要）

1. 公证 `.app` 的 zip，**staple 到 app**；
2. 用 staple 后的 app 重新生成 DMG；
3. 用 Developer ID **签名 DMG**（否则 `spctl --assess -t open` 报 “no usable signature”）；
4. 公证 DMG，staple 到 DMG；
5. 校验：

```bash
codesign --verify --strict build/products/TinyTodo.app
codesign -dvvv build/products/TinyTodo.app | grep -E "Authority|Timestamp|Runtime"
xcrun stapler validate build/products/TinyTodo.app
xcrun stapler validate build/TinyTodo-1.0.0.dmg
spctl --assess --type execute   build/products/TinyTodo.app     # accepted, Notarized Developer ID
spctl --assess --type open --context context:primary-signature build/TinyTodo-1.0.0.dmg
```

任何一步失败就停下来；不要用“再提交一次”掩盖问题，先 `xcrun notarytool log <id> --keychain-profile agentspace-notary` 看具体原因。

## 应用内更新通道

- 更新源唯一：`https://api.github.com/repos/misswell/TinyTodo/releases/latest`（GitHub 直接提供，镜像不能改变期望的版本或摘要）。
- 资产名必须精确为 `TinyTodo-<version>.dmg`，并带 GitHub 的 `digest`（`sha256:<64 hex>`）；无 digest 的 Release 不会被客户端接受。
- 客户端校验顺序：SHA-256 → DMG 内 `TinyTodo.app` 的 bundle id/版本 → `codesign --deep --strict` → TeamIdentifier `U8U443D7ZL` → 与运行副本相同的 designated requirement → `spctl` 公证校验。
- 安装：`TinyTodo/Resources/update-helper.sh` 等待旧进程退出，备份并替换 `/Applications/TinyTodo.app`，去 quarantine 后直接启动新二进制；非 `/Applications` 副本拒绝自动替换。

**发版完成的判据**：`releases/latest` 必须已经返回新 tag，并且该资产带本次构建的 digest；发布后下载一次附件核对 SHA-256。

## 版本号

`project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 是唯一来源，
`scripts/release.sh`、`scripts/notarize.sh`、DMG 文件名都从它读取。改版本时同时更新
`CHANGELOG.md` 与 `CFBundleShortVersionString`（由 build setting 注入）。

## 发布到 GitHub Release

```bash
git tag -a v1.0.0 -m "TinyTodo 1.0.0"
git push origin main --tags
gh release create v1.0.0 build/TinyTodo-1.0.0.dmg \
  --title "TinyTodo 1.0.0" \
  --notes-file docs/releases/v1.0.0.md
```

Release 附件必须是 **公证并 staple 过的 DMG**（本仓库的 `build/` 被 gitignore，不入库）。

## 环境限制

- 公证需要联网访问 Apple Notary Service；`notarytool` 上传 7 MB 左右产物通常 1–3 分钟。
- 2026-11-17 实测 `notarytool` 上传连续两次在 S3 multipart 阶段 `HTTPClientError.deadlineExceeded`，
  而 notary API key 本身有效；脚本此时自动改用 `asc notarization submit`（`ASC_UPLOAD_TIMEOUT=10m`）
  并成功（1.0.1 的 app 提交 `ef877872-…` 与 DMG 提交均 Accepted）。
- 本机没有 Developer ID Installer 证书，因此不产出 `.pkg`；DMG 内是拖拽安装的 `.app`。
- 公证不等同于 App Store 提交；LSUIElement + 本地数据库的桌面工具走直接分发。
