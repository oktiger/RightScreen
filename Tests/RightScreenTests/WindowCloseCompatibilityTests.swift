import Testing
@testable import RightScreen

struct WindowCloseCompatibilityTests {
    @Test func shadowrocketUsesTheDedicatedMenuCloseFallback() {
        #expect(
            WindowCloseCompatibility.strategy(for: "com.liguangming.Shadowrocket")
                == .menuCloseCommand
        )
    }

    @Test func unrelatedAppsNeverReceiveTheCompatibilityFallback() {
        #expect(WindowCloseCompatibility.strategy(for: "com.apple.Safari") == nil)
        #expect(WindowCloseCompatibility.strategy(for: nil) == nil)
    }
}
