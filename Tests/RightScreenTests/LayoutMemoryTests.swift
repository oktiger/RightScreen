import Foundation
import Testing
@testable import RightScreen

@MainActor
struct LayoutMemoryTests {
    @Test func remembersTabLayoutAndGrid() {
        let memory = LayoutMemory(defaults: makeDefaults())
        #expect(memory.current == nil)

        memory.remember(.tabs(.split2))
        #expect(memory.current == .tabs(.split2))

        memory.remember(.grid)
        #expect(memory.current == .grid)
    }

    @Test func forgetClearsRememberedLayout() {
        let memory = LayoutMemory(defaults: makeDefaults())
        memory.remember(.tabs(.split4))
        memory.forget()

        #expect(memory.current == nil)
    }

    @Test func unknownStoredValueIsIgnored() {
        #expect(RememberedLayout(rawValue: "tabs:unknown") == nil)
        #expect(RememberedLayout(rawValue: "") == nil)
        for kind in LayoutKind.allCases {
            #expect(RememberedLayout(rawValue: RememberedLayout.tabs(kind).rawValue) == .tabs(kind))
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LayoutMemoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
