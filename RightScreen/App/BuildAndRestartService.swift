import AppKit
import Foundation

enum BuildAndRestartService {
    /// Walk up from this source file to the SwiftPM repository root.
    private static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let scriptPath = url.appendingPathComponent("Scripts/install-local.sh").path
            if FileManager.default.isExecutableFile(atPath: scriptPath) {
                return url
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BuildAndRestartService.swift
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // RightScreen
    }()

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
