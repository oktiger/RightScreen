# RightScreen 上架 Mac App Store 清单

工程侧已就绪：沙盒 entitlements、1024 图标、分类与加密声明、`Scripts/package-appstore.sh`。下面是账号侧步骤与提交材料。

## 1. 沙盒兼容结论（已实测）

- App Sandbox 下 `AXIsProcessTrusted()` 为 true、`CGWindowList` 正常，但对其他 App 的 AX 调用全部返回 `kAXErrorCannotComplete (-25204)`；系统日志为 `deny(1) mach-lookup com.apple.axserver (per-pid)`。
- 加上临时例外 `com.apple.security.temporary-exception.mach-lookup.local-name = [com.apple.axserver]` 后，全屏、Tab 切换、退出布局都正常。
- **审核风险**：临时例外需要审核员认可，必须在 App Store Connect →「App 审核信息 / App Sandbox 信息」中写明理由（见第 5 节）。若被拒，备选是 Developer ID 签名 + 公证在官网分发。
- 本地验证沙盒版：`RIGHTSCREEN_SANDBOX=1 Scripts/run-local.sh`（同一签名身份，辅助功能授权不丢；快捷键设置存在容器里，首次会是默认值）。

## 2. 证书（一次性，Team 9THF4SEGPY）

Xcode → 设置 → Accounts → 选中 Team → Manage Certificates → `+`：

1. **Apple Distribution**
2. **Mac Installer Distribution**

## 3. 开发者网站（developer.apple.com → Certificates, IDs & Profiles）

1. Identifiers → `+` → App IDs → App → Platform 选 macOS，Bundle ID（Explicit）填 `com.rightscreen.RightScreenApp`，不勾任何 Capability。
2. Profiles → `+` → Distribution → **Mac App Store Connect** → 选上面的 App ID → 选 Apple Distribution 证书 → 下载 `.provisionprofile`。

## 4. 打包与上传

```bash
Scripts/package-appstore.sh dist/profiles/RightScreen_Mac_App_Store.provisionprofile
```

产物：`dist/AppStore/RightScreen.pkg`（universal、沙盒、分发签名）。加 `--upload` 直接上传：

```bash
Scripts/package-appstore.sh dist/profiles/RightScreen_Mac_App_Store.provisionprofile --upload
```

上传走 `xcodebuild -exportArchive`，使用 Xcode → 设置 → Accounts 中已登录的账号，不需要 API Key 或密码；也可以把 pkg 拖进 Transporter。

每次上传 `CFBundleVersion` 必须更大，脚本默认取 git 提交数；改版本号改 `Info.plist` 的 `CFBundleShortVersionString`。

## 5. App Store Connect 材料

- 新建 App：平台 macOS，名称 RightScreen（被占用则改名），主要语言简体中文，Bundle ID 选上面那个，SKU 例：`rightscreen-mac`。
- 类别：效率（Productivity）。
- App Store Connect：RightScreen（Apple ID 6822256407），版本 1.0，审核通过后自动发布。
- 价格：免费。
- 销售范围：174 个国家或地区，暂不含中国大陆（需 ICP 备案号；备案后在「App 信息 → 中国大陆 ICP 备案号」填写并在「价格与销售范围」加回）。
- 隐私政策 URL：`https://oktiger.github.io/RightScreen/privacy.html`
- 技术支持 URL：`https://oktiger.github.io/RightScreen/`（营销 URL 可留空）
- 站点源文件在 `site/`，推送到 master 后由 `.github/workflows/pages.yml` 自动部署。
- App 隐私：选「不收集数据」。
- 截图：`docs/appstore-screenshots/render.sh` 按中英文各生成 4 张 2880×1800 到 `dist/AppStore/screenshots/{zh,en}/`（二分 + Tab、四等分 + 菜单、网格、拖动预览）；改文案或场景编辑同目录的 `screenshot.html`，菜单文案须与 App 的 Localizable.strings 一致。
- 出口合规：`ITSAppUsesNonExemptEncryption = NO` 已写入，上传后不再询问。

**审核备注（可直接粘贴）**：

> RightScreen is a window manager. It arranges other apps' windows into panes with a tab bar (Tab Mode) or a BSP tiling grid (Grid Mode). It requires Accessibility permission to read and set other apps' window positions and sizes via the public AXUIElement API; the app shows guidance to System Settings → Privacy & Security → Accessibility on first use.
>
> Temporary exception `com.apple.security.temporary-exception.mach-lookup.local-name` = `com.apple.axserver`: without it, the sandbox denies the per-process lookup of `com.apple.axserver`, so every AXUIElement call to another app fails with kAXErrorCannotComplete even after the user grants Accessibility. It is used only for window position/size/raise via the public Accessibility API.
>
> How to test: open 2+ windows (e.g. TextEdit), grant Accessibility, then click the menu bar icon → Tab Mode → 左右二分 (Left/Right split). Use 退出当前布局 to restore.
>
> The app does not use the network and collects no data.
