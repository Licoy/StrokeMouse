import XCTest
@testable import StrokeMouse

final class UpdateInstallEnvironmentTests: XCTestCase {
    func testDevelopmentModeWhenNotAppBundle() {
        let env = UpdateInstallEnvironment(
            bundlePathExtension: "",
            sparklePublicKey: "validlookingkey",
            hasUpdater: true
        )
        XCTAssertEqual(env.readiness, .developmentMode)
    }

    func testSigningKeyMissingForPlaceholder() {
        let env = UpdateInstallEnvironment(
            bundlePathExtension: "app",
            sparklePublicKey: "__REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY__",
            hasUpdater: true
        )
        XCTAssertEqual(env.readiness, .signingKeyMissing)
    }

    func testUpdaterUnavailableAfterValidKey() {
        let env = UpdateInstallEnvironment(
            bundlePathExtension: "app",
            sparklePublicKey: "abcd1234notplaceholder",
            hasUpdater: false
        )
        XCTAssertEqual(env.readiness, .updaterUnavailable)
    }

    func testReadyWhenConfigured() {
        let env = UpdateInstallEnvironment(
            bundlePathExtension: "app",
            sparklePublicKey: "abcd1234notplaceholder",
            hasUpdater: true
        )
        XCTAssertEqual(env.readiness, .ready)
    }

    func testLaunchCheckRequiresReadyAndPreference() {
        let env = UpdateInstallEnvironment(
            bundlePathExtension: "app",
            sparklePublicKey: "abcd1234notplaceholder",
            hasUpdater: true
        )
        XCTAssertTrue(env.shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: true))
        XCTAssertFalse(env.shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: false))
    }
}
