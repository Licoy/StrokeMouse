import XCTest
@testable import StrokeMouse

@MainActor
final class ConfigStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gestures.json")

        let store = ConfigStore(configURL: url)
        let profile = GestureProfile(
            name: "Test",
            pattern: .freePath(PathTemplates.left),
            action: .openURL("https://example.com")
        )
        store.replaceAll([profile])

        let reloaded = ConfigStore(configURL: url)
        XCTAssertEqual(reloaded.gestures.count, 1)
        XCTAssertEqual(reloaded.gestures.first?.name, "Test")
        if case .freePath(let pts) = reloaded.gestures.first?.pattern {
            XCTAssertGreaterThanOrEqual(pts.count, 2)
        } else {
            XCTFail("Expected freePath pattern")
        }

        try? FileManager.default.removeItem(at: dir)
    }

    func testEnabledGesturesRespectsScope() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)

        let global = GestureProfile(
            name: "Global",
            pattern: .freePath(PathTemplates.up),
            scope: .global
        )
        let safariOnly = GestureProfile(
            name: "Safari",
            pattern: .freePath(PathTemplates.down),
            scope: .apps(["com.apple.Safari"])
        )
        store.replaceAll([global, safariOnly])

        let all = store.enabledGestures(frontmostBundleId: "com.apple.Safari", button: .right)
        XCTAssertEqual(all.count, 2)

        let onlyGlobal = store.enabledGestures(frontmostBundleId: "com.apple.finder", button: .right)
        XCTAssertEqual(onlyGlobal.count, 1)
        XCTAssertEqual(onlyGlobal.first?.name, "Global")

        // Middle button has no matching profiles.
        let middle = store.enabledGestures(frontmostBundleId: "com.apple.Safari", button: .middle)
        XCTAssertTrue(middle.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    func testEnabledGesturesFiltersByTriggerButton() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)

        let right = GestureProfile(
            name: "Right",
            trigger: GestureTrigger(button: .right),
            pattern: .freePath(PathTemplates.up)
        )
        let middle = GestureProfile(
            name: "Middle",
            trigger: GestureTrigger(button: .middle),
            pattern: .freePath(PathTemplates.up)
        )
        store.replaceAll([right, middle])

        let r = store.enabledGestures(frontmostBundleId: nil, button: .right)
        XCTAssertEqual(r.map(\.name), ["Right"])

        let m = store.enabledGestures(frontmostBundleId: nil, button: .middle)
        XCTAssertEqual(m.map(\.name), ["Middle"])

        XCTAssertEqual(store.enabledTriggerButtons(), Set([.right, .middle]))

        try? FileManager.default.removeItem(at: dir)
    }
}
