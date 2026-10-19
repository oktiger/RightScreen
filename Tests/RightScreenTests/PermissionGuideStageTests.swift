import Testing
@testable import RightScreen

struct PermissionGuideStageTests {
    @Test func signingIssueWinsOverTrust() {
        let stage = PermissionGuideStage.resolve(signingIssue: "bad", isTrusted: true, secondsSinceSettingsOpened: nil)
        #expect(stage == .signingIssue("bad"))
    }

    @Test func trustedIsGranted() {
        #expect(PermissionGuideStage.resolve(signingIssue: nil, isTrusted: true, secondsSinceSettingsOpened: 30) == .granted)
    }

    @Test func untrustedBeforeOpeningSettingsNeedsGrant() {
        #expect(PermissionGuideStage.resolve(signingIssue: nil, isTrusted: false, secondsSinceSettingsOpened: nil) == .needsGrant)
    }

    @Test func untrustedAfterOpeningSettingsWaitsThenBecomesStuck() {
        #expect(PermissionGuideStage.resolve(signingIssue: nil, isTrusted: false, secondsSinceSettingsOpened: 3) == .waitingForToggle)
        #expect(
            PermissionGuideStage.resolve(
                signingIssue: nil,
                isTrusted: false,
                secondsSinceSettingsOpened: PermissionGuideStage.stuckThreshold
            ) == .stuck
        )
    }
}
