import AppKit
import ApplicationServices
import Security

enum Permissions {
    private static let expectedBundleIdentifier = "com.rightscreen.RightScreenApp"

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 返回会破坏 TCC 身份连续性的打包问题；nil 表示证书签名与 Bundle ID 均符合约束。
    static var signingIssue: String? {
        let actualBundleIdentifier = Bundle.main.bundleIdentifier ?? localized("<空>")
        guard actualBundleIdentifier == expectedBundleIdentifier else {
            return localized("Bundle ID 已变为 %@，预期为 %@。", actualBundleIdentifier, expectedBundleIdentifier)
        }

        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return localized("无法读取当前进程的代码签名。")
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return localized("无法读取当前 app 的静态代码签名。")
        }

        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else {
            return localized("当前 app 的代码签名已损坏或与内容不匹配。")
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let information = information as? [String: Any]
        else {
            return localized("无法读取当前 app 的签名证书信息。")
        }

        if let certificates = information[kSecCodeInfoCertificates as String] as? [Any],
           !certificates.isEmpty {
            return nil
        }

        return localized("当前 app 使用了临时 adhoc/linker-signed 签名。")
    }

    static func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .accessibility: isAccessibilityGranted
        }
    }

    /// 让系统把 RightScreen 登记进该权限列表（开关默认关闭），用户只需打开开关。
    /// 首次调用时系统会弹出一次授权提示；已登记过则静默返回。
    static func registerInSettingsList(_ permission: AppPermission) {
        switch permission {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    /// 直接打开该权限所在的系统设置列表页。
    @MainActor
    static func openSettings(for permission: AppPermission) {
        for urlString in permission.settingsURLs {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @MainActor
    static func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.MenuBarSettings",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings"
        ]
        for urlString in candidates {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @MainActor
    static func accessibilityHelpMessage(signingIssue: String?) -> (title: String, message: String) {
        if let signingIssue {
            return (
                localized("辅助功能授权无法保持"),
                localized("""
                当前安装包身份不正确：%@

                请退出应用后执行：
                Scripts/run-local.sh
                将应用重新安装到 /Applications/RightScreen.app。

                然后在“系统设置 → 隐私与安全性 → 辅助功能”中删除旧的 RightScreen 条目，再重新勾选一次即可长期有效。
                """, signingIssue)
            )
        }

        return (
            localized("需要辅助功能权限"),
            localized("请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 RightScreen，然后再次选择布局。")
        )
    }
}
