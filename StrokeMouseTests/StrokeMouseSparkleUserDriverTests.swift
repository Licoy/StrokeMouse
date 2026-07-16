import Foundation
import XCTest
@testable import StrokeMouse

@MainActor
final class StrokeMouseSparkleUserDriverTests: XCTestCase {
    func testAutomaticChecksAreEnabledByDefault() {
        XCTAssertTrue(UpdaterService.defaultAutomaticallyChecksForUpdates)
    }

    func testNetworkErrorsIncludeProxyHint() {
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        let sparkleError = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Download failed",
                NSUnderlyingErrorKey: networkError,
            ]
        )

        let message = StrokeMouseSparkleUserDriver.errorMessage(
            for: sparkleError,
            proxyHint: "Proxy hint"
        )

        XCTAssertTrue(message.contains("Download failed"))
        XCTAssertTrue(message.contains("Proxy hint"))
    }

    func testNonNetworkErrorsKeepOriginalMessage() {
        let error = NSError(
            domain: "SUSparkleErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Bad feed"]
        )

        XCTAssertEqual(
            StrokeMouseSparkleUserDriver.errorMessage(for: error, proxyHint: "Proxy hint"),
            "Bad feed"
        )
    }

    func testUpdateLocalizationKeysExist() {
        let keys = [
            "update.available",
            "update.noUpdate",
            "update.noUpdateMessage",
            "update.versionAvailable",
            "update.downloadAndInstall",
            "update.installAndRelaunch",
            "update.installLater",
            "update.skipVersion",
            "update.downloading",
            "update.extracting",
            "update.readyToInstall",
            "update.installing",
            "update.installed",
            "update.installedMessage",
            "update.learnMore",
            "update.networkProxyHint",
            "update.updaterUnavailable",
        ]

        for key in keys {
            XCTAssertNotEqual(L10n.string(key), key, "Missing localization for \(key)")
        }
    }
}
