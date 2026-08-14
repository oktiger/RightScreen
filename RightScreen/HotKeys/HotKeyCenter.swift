import Carbon.HIToolbox
import Foundation

private let hotKeySignature: OSType = 0x5253486B // 'RSHk'

/// Registers specific chords with the system. Does not install a key-event tap,
/// so Input Monitoring is not required.
@MainActor
final class HotKeyCenter {
    nonisolated(unsafe) static weak var shared: HotKeyCenter?

    private var handler: ((HotKeyAction) -> Void)?
    private var bindings: [HotKeyAction: KeyChord] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionByID: [UInt32: HotKeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
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
        handler?(action)
    }

    private func reregister() {
        unregisterAll()
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let chord = bindings[action] else { continue }
            let hotKeyID = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                chord.keyCode,
                chord.carbonModifiers,
                EventHotKeyID(signature: hotKeySignature, id: hotKeyID),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else { continue }
            hotKeyRefs[hotKeyID] = ref
            actionByID[hotKeyID] = action
        }
    }

    private func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
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
