import AppKit
import ApplicationServices
import Security

enum Permissions {
    private static let expectedBundleIdentifier = "com.rightscreen.RightScreen"

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 返回会破坏 TCC 身份连续性的打包问题；nil 表示证书签名与 Bundle ID 均符合约束。
    static var signingIssue: String? {
        let actualBundleIdentifier = Bundle.main.bundleIdentifier ?? "<空>"
        guard actualBundleIdentifier == expectedBundleIdentifier else {
            return "Bundle ID 已变为 \(actualBundleIdentifier)，预期为 \(expectedBundleIdentifier)。"
        }

        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return "无法读取当前进程的代码签名。"
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return "无法读取当前 app 的静态代码签名。"
        }

        guard SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else {
            return "当前 app 的代码签名已损坏或与内容不匹配。"
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let information = information as? [String: Any]
        else {
            return "无法读取当前 app 的签名证书信息。"
        }

        if let certificates = information[kSecCodeInfoCertificates as String] as? [Any],
           !certificates.isEmpty {
            return nil
        }

        return "当前 app 使用了临时 adhoc/linker-signed 签名。"
    }

    /// 弹出系统辅助功能授权框（如需要）。不要与自定义 Alert 叠在一起调用。
    @discardableResult
    static func requestAccessibility() -> Bool {
        guard signingIssue == nil else {
            return false
        }
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
    static func accessibilityHelpMessage(signingIssue: String?) -> (title: String, message: String) {
        if let signingIssue {
            return (
                "辅助功能授权无法保持",
                """
                当前安装包身份不正确：\(signingIssue)

                请退出应用后执行：
                Scripts/run-local.sh
                或菜单“生成并升级 app”重新安装到 /Applications/RightScreen.app。

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
