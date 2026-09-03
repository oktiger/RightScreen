import AppKit
import ApplicationServices

/// AXObserver 的 C 回调由主 RunLoop 同步调用。该包装只用于通过 Swift 6 的
/// Sendable 检查，引用不会逃逸到其他线程，随后立即在 MainActor 中消费。
private struct AXCallbackPayload: @unchecked Sendable {
    let observer: AXObserver
    let element: AXUIElement
    let notification: String
}

private let windowObservationCallback: AXObserverCallback = {
    observer,
    element,
    notification,
    refcon in
    guard let refcon else { return }
    let serviceAddress = UInt(bitPattern: refcon)
    let payload = AXCallbackPayload(
        observer: observer,
        element: element,
        notification: notification as String
    )

    // 所有 AXObserver source 都安装在主 RunLoop，因此回调可以安全回到主 actor，
    // 避免在 AX 回调期间并发修改布局会话或 AppKit UI。
    MainActor.assumeIsolated {
        guard
            let servicePointer = UnsafeRawPointer(bitPattern: serviceAddress)
        else {
            return
        }
        let service = Unmanaged<WindowObservationService>
            .fromOpaque(servicePointer)
            .takeUnretainedValue()
        service.receive(
            observer: payload.observer,
            element: payload.element,
            notification: payload.notification
        )
    }
}

@MainActor
final class WindowObservationService: NSObject {
    private struct Registration {
        let applicationElement: AXUIElement
        let observer: AXObserver
    }

    private let onWindowCreated: (pid_t) -> Void
    private let onWindowStateChanged: () -> Void
    private let onFocusChanged: () -> Void
    private var registrations: [pid_t: Registration] = [:]
    private var isRunning = false

    init(
        onWindowCreated: @escaping (pid_t) -> Void,
        onWindowStateChanged: @escaping () -> Void,
        onFocusChanged: @escaping () -> Void
    ) {
        self.onWindowCreated = onWindowCreated
        self.onWindowStateChanged = onWindowStateChanged
        self.onFocusChanged = onFocusChanged
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        for application in NSWorkspace.shared.runningApplications {
            register(application, reconcileAfterRegistration: false)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        for registration in registrations.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(registration.observer),
                .commonModes
            )
        }
        registrations.removeAll()
    }

    private func register(
        _ application: NSRunningApplication,
        reconcileAfterRegistration: Bool
    ) {
        let pid = application.processIdentifier
        guard
            application.activationPolicy == .regular,
            pid != getpid(),
            registrations[pid] == nil
        else {
            return
        }

        var observer: AXObserver?
        guard
            AXObserverCreate(pid, windowObservationCallback, &observer) == .success,
            let observer
        else {
            return
        }

        let applicationElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let creationResult = AXObserverAddNotification(
            observer,
            applicationElement,
            kAXWindowCreatedNotification as CFString,
            refcon
        )
        guard creationResult == .success || creationResult == .notificationAlreadyRegistered else {
            return
        }

        // 部分 App 不支持焦点通知；窗口创建观察成功时仍应保留该注册。
        _ = AXObserverAddNotification(
            observer,
            applicationElement,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )

        registrations[pid] = Registration(
            applicationElement: applicationElement,
            observer: observer
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        // 覆盖 App 在观察器安装完成前已创建首个窗口的竞态。
        observeDestructionOfExistingWindows(for: pid)
        if reconcileAfterRegistration {
            onWindowCreated(pid)
        }
    }

    private func unregister(pid: pid_t) {
        guard let registration = registrations.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(registration.observer),
            .commonModes
        )
    }

    private func observeDestructionOfExistingWindows(for pid: pid_t) {
        guard let registration = registrations[pid] else { return }
        for window in AXHelpers.windows(of: registration.applicationElement) {
            observeDestruction(of: window, registration: registration)
        }
    }

    private func observeDestruction(of window: AXUIElement, registration: Registration) {
        _ = AXObserverAddNotification(
            registration.observer,
            window,
            kAXUIElementDestroyedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    fileprivate func receive(
        observer: AXObserver,
        element: AXUIElement,
        notification: String
    ) {
        guard isRunning else { return }
        guard let (pid, registration) = registrations.first(where: {
            CFEqual($0.value.observer, observer)
        }) else {
            return
        }

        switch notification {
        case kAXWindowCreatedNotification:
            observeDestruction(of: element, registration: registration)
            onWindowCreated(pid)
        case kAXUIElementDestroyedNotification:
            onWindowStateChanged()
        case kAXFocusedWindowChangedNotification:
            onFocusChanged()
        default:
            break
        }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else {
            return
        }
        register(application, reconcileAfterRegistration: true)
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else {
            return
        }
        unregister(pid: application.processIdentifier)
        onWindowStateChanged()
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication {
            // 某些 App 在 didLaunch 时仍是 accessory/prohibited，首次激活时再补注册。
            register(application, reconcileAfterRegistration: true)
        }
        onFocusChanged()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        onWindowStateChanged()
    }
}
