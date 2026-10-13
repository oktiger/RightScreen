import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var hasModifier: Bool {
        (carbonModifiers & Self.modifierMask) != 0
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
    }

    var isEscape: Bool {
        keyCode == UInt32(kVK_Escape)
    }

    var isClearKey: Bool {
        !hasModifier && (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete))
    }

    var displayString: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += Self.keyName(for: keyCode)
        return parts
    }

    static func defaultBindings() -> [HotKeyAction: KeyChord] {
        let modifiers = UInt32(controlKey | optionKey)
        return [
            .moveLeft: KeyChord(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: modifiers),
            .moveRight: KeyChord(keyCode: UInt32(kVK_RightArrow), carbonModifiers: modifiers),
            .moveUp: KeyChord(keyCode: UInt32(kVK_UpArrow), carbonModifiers: modifiers),
            .moveDown: KeyChord(keyCode: UInt32(kVK_DownArrow), carbonModifiers: modifiers),
            .fullScreen: KeyChord(keyCode: UInt32(kVK_Return), carbonModifiers: modifiers)
        ]
    }

    static func conflictingAction(
        for chord: KeyChord,
        excluding action: HotKeyAction,
        in bindings: [HotKeyAction: KeyChord]
    ) -> HotKeyAction? {
        bindings.first { $0.key != action && $0.value == chord }?.key
    }

    private static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    private static let namedKeys: [UInt32: String] = {
        var names: [UInt32: String] = [
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Space): localized("空格"),
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Grave): "`"
        ]

        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9")
        ]
        for (code, name) in letters {
            names[UInt32(code)] = name
        }
        return names
    }()

    private static func keyName(for keyCode: UInt32) -> String {
        namedKeys[keyCode] ?? "Key\(keyCode)"
    }
}
