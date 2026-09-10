# 菜单栏图标消失的原因（2026-09-10）

## 现象

App 正常运行，「系统设置 → 菜单栏」里 RightScreen 的开关也是打开的，但菜单栏上看不到图标。

## 原因

`com.rightscreen.RightScreen` 这个 bundle id 在系统侧的菜单栏记录已损坏，macOS 拒绝给它分配菜单栏槽位。
拿不到槽位时 AppKit 会把按钮窗口停在兜底位置：屏幕右上角、高度只有 `NSStatusBar.thickness`（22）而非菜单栏实际高度（30），于是被时钟/控制中心盖住 —— 看起来就是图标不见了。

实测（同一个二进制、同一个 bundle，只改 `CFBundleIdentifier`）：

| bundle id | 按钮窗口 frame | 结果 |
| --- | --- | --- |
| `com.rightscreen.RightScreen` | `(3402, 1418, 38, 22)` | 停在右上角，不可见 |
| 任意其他 id | `(2597, 1410, 38, 30)` | 正常槽位，可见 |

用一个只创建 status item 的最小 App 复现同样结果，**与 RightScreen 的代码无关**。

坏记录的来源应为**同一 bundle id 存在多个各自 ad-hoc 签名的副本**（当时磁盘上有 4 份：`/Applications` 一份，`.build/` 三份），签名身份互相打架。

## 已排除

App 代码、图标绘制、偏好设置（整域删除无效）、`NSStatusItem.autosaveName`、重启 ControlCenter、重启 macOS、同 id 双实例、系统设置里的开关。

## 处理

1. 删除 `.build/` 下所有同 id 的 App 副本并从 LaunchServices 注销 —— 必要但不充分，坏记录清不掉。
2. 换 bundle id 为 `com.rightscreen.RightScreenApp`（同步改 `Info.plist`、`Permissions.swift`、`Scripts/package-app.sh`、`Scripts/sign-app.sh`）。代价：辅助功能权限与偏好域需重新建立。
3. `StatusItemPresence` 增加这种停靠形态的判定（贴屏幕右缘 且 高度低于菜单栏高度），否则图标消失时提示弹窗根本不会弹。

## 约束

不要再让同一 bundle id 的多个副本同时存在于磁盘上（打包/签名测试产物用完即删）。
