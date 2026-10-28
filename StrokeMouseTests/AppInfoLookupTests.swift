import AppKit
import XCTest
@testable import StrokeMouse

final class AppInfoLookupTests: XCTestCase {
    func testSortedByNameResolvesEachBundleIdOnce() {
        let names = ["b": "Beta", "a": "alpha", "c": "Gamma"]
        var lookups: [String] = []

        let sorted = AppInfoLookup.sortedByName(["c", "b", "a"]) { id in
            lookups.append(id)
            return names[id] ?? id
        }

        XCTAssertEqual(sorted, ["a", "b", "c"])
        XCTAssertEqual(lookups.sorted(), ["a", "b", "c"])
    }

    func testMissingApplicationFallsBackToBundleId() {
        let bundleId = "invalid.strokemouse.tests.\(UUID().uuidString)"
        let expected = AppInfoLookup.Info(bundleId: bundleId, name: bundleId, path: "")

        XCTAssertEqual(AppInfoLookup.info(forBundleId: " \(bundleId)\n"), expected)
        XCTAssertEqual(AppInfoLookup.info(forBundleId: bundleId), expected)
        AppInfoLookup.invalidateCache()
        XCTAssertEqual(AppInfoLookup.info(forBundleId: bundleId), expected)
    }

    func testIconIsReusedForTheSamePath() {
        let path = Bundle.main.bundlePath

        XCTAssertTrue(AppInfoLookup.icon(for: path) === AppInfoLookup.icon(for: path))
        XCTAssertTrue(AppInfoLookup.icon(for: "") === AppInfoLookup.icon(for: ""))
    }
}
