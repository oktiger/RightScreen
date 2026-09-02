import ApplicationServices
import Testing
@testable import RightScreen

struct WindowCloseResultTests {
    @Test func successfulActionIsAcceptedEvenWhenAnotherModalWindowExists() {
        #expect(
            WindowCloseResult.classify(actionError: .success, hasBlockingModalUI: true)
                == .requested
        )
    }

    @Test func modalDialogExplainsAnOtherwiseUnsupportedCloseAction() {
        #expect(
            WindowCloseResult.classify(
                actionError: .actionUnsupported,
                hasBlockingModalUI: true
            ) == .blockedByModalDialog
        )
    }

    @Test func cannotCompleteWithoutAModalDialogIsRetriable() {
        #expect(
            WindowCloseResult.classify(
                actionError: .cannotComplete,
                hasBlockingModalUI: false
            ) == .temporarilyUnavailable
        )
    }

    @Test func revokedAccessibilityPermissionIsReportedPrecisely() {
        #expect(
            WindowCloseResult.classify(
                actionError: .apiDisabled,
                hasBlockingModalUI: false
            ) == .accessibilityPermissionRequired
        )
    }

    @Test func vanishedWindowDoesNotLookLikeAnUnsupportedApp() {
        #expect(
            WindowCloseResult.classify(
                actionError: .invalidUIElement,
                hasBlockingModalUI: false
            ) == .windowUnavailable
        )
    }
}
