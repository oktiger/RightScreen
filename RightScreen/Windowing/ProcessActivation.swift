import ApplicationServices
import Darwin

/// `NSRunningApplication.activate()` 会把该进程的所有窗口一起前置。
/// Carbon 的 `SetFrontProcessWithOptions(.frontWindowOnly)` 仍是公开 API，
/// 只是 Swift 把 10.9 前弃用的声明标成了 unavailable，因此用符号调用。
enum ProcessActivation {
    private typealias GetProcessForPIDFn = @convention(c) (
        pid_t,
        UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    private typealias SetFrontProcessWithOptionsFn = @convention(c) (
        UnsafePointer<ProcessSerialNumber>,
        OptionBits
    ) -> OSStatus

    static func bringFrontWindowOnly(pid: pid_t) -> Bool {
        guard
            let getProcess = symbol(GetProcessForPIDFn.self, name: "GetProcessForPID"),
            let setFront = symbol(SetFrontProcessWithOptionsFn.self, name: "SetFrontProcessWithOptions")
        else {
            return false
        }

        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard getProcess(pid, &psn) == noErr else { return false }
        let options = OptionBits(kSetFrontProcessFrontWindowOnly | kSetFrontProcessCausedByUser)
        return setFront(&psn, options) == noErr
    }

    private static func symbol<T>(_ type: T.Type, name: String) -> T? {
        // Swift 不导入 RTLD_DEFAULT 宏（((void *)-2)）。
        guard
            let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2),
            let pointer = dlsym(defaultHandle, name)
        else {
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}
