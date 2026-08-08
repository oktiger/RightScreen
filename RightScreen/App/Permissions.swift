import AppKit
import ApplicationServices
import Security

enum Permissions {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 当前进程是否为 adhoc / linker-signed。此类签名的 Designated Requirement 绑定 CDHash，
    /// 每次重新编译都会变化，系统会认为「未授权」，表现为反复要求辅助功能权限。
    static var isAdHocSigned: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return true
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return true
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let information = information as? [String: Any]
        else {
            return true
        }

        if let certificates = information[kSecCodeInfoCertificates as String] as? [Any],
           !certificates.isEmpty {
            return false
        }

        // linker-signed / 纯 adhoc 通常没有证书链。
        return true
    }

    /// 弹出系统辅助功能授权框（如需要）。不要与自定义 Alert 叠在一起调用。
    @discardableResult
    static func requestAccessibility() -> Bool {
        if isAccessibilityGranted {
            return true
        }
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openAccessibilitySettings(promptIfNeeded: Bool = false) {
        if promptIfNeeded {
            _ = requestAccessibility()
        }

        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for urlString in candidates {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @MainActor
    static func accessibilityHelpMessage() -> (title: String, message: String) {
        if isAdHocSigned {
            return (
                "辅助功能授权无法保持",
                """
                当前 RightScreen 使用了临时签名（adhoc），系统按每次编译的校验和记住授权，所以会反复要求权限，开关旧条目也无效。

                请退出应用后执行：
                Scripts/run-local.sh
                或菜单「生成 app」重新打包（会使用稳定的本地开发证书签名）。

                然后在“系统设置 → 隐私与安全性 → 辅助功能”中删除旧的 RightScreen 条目，再重新勾选一次即可长期有效。
                """
            )
        }

        return (
            "需要辅助功能权限",
            "请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 RightScreen，然后再次选择布局。"
        )
    }
}
