import Carbon.HIToolbox
import Foundation
import Testing
@testable import RightScreen

struct HotKeyTests {
    @Test func moveActionsMapToPaneDirectionsAndFullScreenDoesNot() {
        #expect(HotKeyAction.moveLeft.paneMoveDirection == .left)
        #expect(HotKeyAction.moveRight.paneMoveDirection == .right)
        #expect(HotKeyAction.moveUp.paneMoveDirection == .up)
        #expect(HotKeyAction.moveDown.paneMoveDirection == .down)
        #expect(HotKeyAction.fullScreen.paneMoveDirection == nil)
    }

    @Test func defaultBindingsUseControlOptionArrowsAndReturn() {
        let bindings = KeyChord.defaultBindings()
        let modifiers = UInt32(controlKey | optionKey)

        #expect(bindings[.moveLeft] == KeyChord(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: modifiers))
        #expect(bindings[.moveRight] == KeyChord(keyCode: UInt32(kVK_RightArrow), carbonModifiers: modifiers))
        #expect(bindings[.moveUp] == KeyChord(keyCode: UInt32(kVK_UpArrow), carbonModifiers: modifiers))
        #expect(bindings[.moveDown] == KeyChord(keyCode: UInt32(kVK_DownArrow), carbonModifiers: modifiers))
        #expect(bindings[.fullScreen] == KeyChord(keyCode: UInt32(kVK_Return), carbonModifiers: modifiers))
        #expect(bindings[.moveLeft]?.displayString == "⌃⌥←")
        #expect(bindings[.fullScreen]?.displayString == "⌃⌥↩")
    }

    @Test func keyChordRoundTripsThroughCodable() throws {
        let original = KeyChord(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: UInt32(controlKey | optionKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyChord.self, from: data)

        #expect(decoded == original)
        #expect(decoded.displayString == "⌃⌥L")
    }

    @Test func conflictingActionFindsTheOtherBinding() {
        let chord = KeyChord(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(controlKey | optionKey))
        let bindings: [HotKeyAction: KeyChord] = [
            .moveLeft: chord,
            .moveRight: KeyChord(keyCode: UInt32(kVK_RightArrow), carbonModifiers: UInt32(controlKey | optionKey))
        ]

        #expect(KeyChord.conflictingAction(for: chord, excluding: .moveLeft, in: bindings) == nil)
        #expect(KeyChord.conflictingAction(for: chord, excluding: .moveRight, in: bindings) == .moveLeft)
    }

    @Test @MainActor func settingsStorePersistsBindingsAndTreatsClearedActionsAsUnbound() {
        let suiteName = "RightScreen.HotKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HotKeySettingsStore(defaults: defaults)
        #expect(store.chord(for: .moveRight)?.displayString == "⌃⌥→")

        let replacement = KeyChord(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: UInt32(controlKey | optionKey))
        #expect(store.setChord(replacement, for: .moveRight) == nil)
        #expect(store.setChord(nil, for: .fullScreen) == nil)

        let reloaded = HotKeySettingsStore(defaults: defaults)
        #expect(reloaded.chord(for: .moveRight) == replacement)
        #expect(reloaded.chord(for: .fullScreen) == nil)
        #expect(reloaded.chord(for: .moveLeft)?.displayString == "⌃⌥←")
    }

    @Test @MainActor func settingsStoreRejectsConflictingChords() {
        let suiteName = "RightScreen.HotKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HotKeySettingsStore(defaults: defaults)
        let left = store.chord(for: .moveLeft)!
        #expect(store.setChord(left, for: .moveRight) == "快捷键已被「移到左侧」占用")
        #expect(store.chord(for: .moveRight)?.displayString == "⌃⌥→")
    }
}
