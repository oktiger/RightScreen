import AppKit
import Foundation

enum BuildAndRestartService {
    /// The local development app is built from the repository that contains this source file.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // App
        .deletingLastPathComponent() // RightScreen
        // SwiftPM repository root

    @MainActor
    static func start() {
        let scriptURL = repositoryRoot.appendingPathComponent("Scripts/install-local.sh")

        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            showError("找不到升级脚本", "请确认 Scripts/install-local.sh 存在且可执行。")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path
        ]

        let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RightScreen-build.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
        } catch {
            showError("无法生成 app", "构建任务启动失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private static func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
