import AppKit
import Carbon.HIToolbox
import Foundation

private let hotKeySignature: OSType = 0x5253486B // 'RSHk'
private let duplicateDeliveryWindow: Duration = .milliseconds(80)

/// Registers specific chords with the system. Does not install a key-event tap,
/// so Input Monitoring is not required.
///
/// Carbon `RegisterEventHotKey` is the primary path and can swallow the chord.
/// Arrow keys are often consumed by the frontmost app (editors, browsers,
/// terminals) before Carbon sees them, so a matching NSEvent monitor is kept as
/// a fallback. Only registered chords are acted on.
@MainActor
final class HotKeyCenter {
    nonisolated(unsafe) static weak var shared: HotKeyCenter?

    private var handler: ((HotKeyAction) -> Void)?
    private var bindings: [HotKeyAction: KeyChord] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionByID: [UInt32: HotKeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastDelivery: (action: HotKeyAction, time: ContinuousClock.Instant)?
    private var isSuspended = false

    init() {
        Self.shared = self
        installEventHandlerIfNeeded()
    }

    func setHandler(_ handler: @escaping (HotKeyAction) -> Void) {
        self.handler = handler
    }

    func updateBindings(_ bindings: [HotKeyAction: KeyChord]) {
        self.bindings = bindings
        if !isSuspended {
            reregister()
        }
    }

    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        reregister()
    }

    func invalidate() {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if Self.shared === self {
            Self.shared = nil
        }
    }

    func handlePress(id: UInt32) {
        guard let action = actionByID[id] else { return }
        deliver(action)
    }

    private func reregister() {
        unregisterAll()
        installCarbonHotKeys()
        installEventMonitors()
    }

    private func installCarbonHotKeys() {
        let dispatcher = GetEventDispatcherTarget()
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let chord = bindings[action] else { continue }
            let hotKeyID = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                chord.keyCode,
                chord.carbonModifiers,
                EventHotKeyID(signature: hotKeySignature, id: hotKeyID),
                dispatcher,
                0,
                &ref
            )
            guard status == noErr, let ref else { continue }
            hotKeyRefs[hotKeyID] = ref
            actionByID[hotKeyID] = action
        }
    }

    private func installEventMonitors() {
        guard !bindings.isEmpty else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isRepeat = event.isARepeat
            let chord = KeyChord(event: event)
            var shouldSwallow = false
            MainActor.assumeIsolated {
                shouldSwallow = self?.deliver(chord: chord, isRepeat: isRepeat) == true
            }
            return shouldSwallow ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isRepeat = event.isARepeat
            let chord = KeyChord(event: event)
            Task { @MainActor in
                _ = self?.deliver(chord: chord, isRepeat: isRepeat)
            }
        }
    }

    @discardableResult
    private func deliver(chord: KeyChord?, isRepeat: Bool) -> Bool {
        guard !isRepeat, let chord else { return false }
        guard let action = bindings.first(where: { $0.value == chord })?.key else { return false }
        deliver(action)
        return true
    }

    private func deliver(_ action: HotKeyAction) {
        let now = ContinuousClock.now
        if let lastDelivery,
           lastDelivery.action == action,
           now - lastDelivery.time < duplicateDeliveryWindow {
            return
        }
        lastDelivery = (action, now)
        handler?(action)
    }

    private func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
        removeEventMonitors()
        lastDelivery = nil
    }

    private func removeEventMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyPressedHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}

private func hotKeyPressedHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let identifier = hotKeyID.id
    Task { @MainActor in
        HotKeyCenter.shared?.handlePress(id: identifier)
    }
    return noErr
}
