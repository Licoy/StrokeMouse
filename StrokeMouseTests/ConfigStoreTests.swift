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

    // MARK: - Import / Export

    func testExportPackageContainsOnlySelectedGestures() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)

        let a = GestureProfile(name: "A", pattern: .freePath(PathTemplates.up), action: .openURL("https://a.example"))
        let b = GestureProfile(name: "B", pattern: .freePath(PathTemplates.down), action: .openURL("https://b.example"))
        let c = GestureProfile(name: "C", pattern: .freePath(PathTemplates.left))
        store.replaceAll([a, b, c])

        let data = try store.exportPackage(ids: [a.id, c.id])
        let package = try JSONDecoder().decode(GestureConfigFile.self, from: data)
        XCTAssertEqual(package.version, Constants.configVersion)
        XCTAssertEqual(package.gestures.map(\.name), ["A", "C"])
        XCTAssertEqual(package.gestures.map(\.id), [a.id, c.id])
    }

    func testExportPackageRejectsEmptySelection() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        store.replaceAll([
            GestureProfile(name: "Only", pattern: .freePath(PathTemplates.up))
        ])

        XCTAssertThrowsError(try store.exportPackage(ids: [])) { error in
            XCTAssertEqual(error as? GestureImportExportError, .emptySelection)
        }
        XCTAssertThrowsError(try store.exportPackage(ids: [UUID()])) { error in
            XCTAssertEqual(error as? GestureImportExportError, .emptySelection)
        }
    }

    func testImportPackageAssignsNewIDsAndMerges() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)

        let existing = GestureProfile(
            name: "Existing",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://existing.example")
        )
        store.replaceAll([existing])
        let existingID = existing.id

        let sourceA = GestureProfile(
            name: "Imported A",
            pattern: .freePath(PathTemplates.down),
            action: .media(.playPause)
        )
        let sourceB = GestureProfile(
            name: "Imported B",
            pattern: .freePath(PathTemplates.left)
        )
        let package = GestureConfigFile(version: Constants.configVersion, gestures: [sourceA, sourceB])
        let data = try JSONEncoder().encode(package)

        let newIDs = try store.importPackage(from: data)
        XCTAssertEqual(newIDs.count, 2)
        XCTAssertEqual(store.gestures.count, 3)
        XCTAssertEqual(store.gestures.first?.id, existingID)
        XCTAssertEqual(store.gestures.first?.name, "Existing")
        XCTAssertFalse(newIDs.contains(sourceA.id))
        XCTAssertFalse(newIDs.contains(sourceB.id))
        XCTAssertEqual(Set(store.gestures.map(\.id)).count, 3)

        let importedNames = Set(store.gestures.map(\.name))
        XCTAssertTrue(importedNames.contains("Imported A"))
        XCTAssertTrue(importedNames.contains("Imported B"))

        // Reloaded from disk keeps merged set.
        let reloaded = ConfigStore(configURL: url)
        XCTAssertEqual(reloaded.gestures.count, 3)
    }

    func testImportPackageRejectsEmptyAndInvalid() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        let seed = GestureProfile(name: "Seed", pattern: .freePath(PathTemplates.up))
        store.replaceAll([seed])
        let before = store.gestures

        let emptyPackage = GestureConfigFile(version: Constants.configVersion, gestures: [])
        let emptyData = try JSONEncoder().encode(emptyPackage)
        XCTAssertThrowsError(try store.importPackage(from: emptyData)) { error in
            XCTAssertEqual(error as? GestureImportExportError, .emptyPackage)
        }
        XCTAssertEqual(store.gestures, before)

        XCTAssertThrowsError(try store.importPackage(from: Data("not-json".utf8)))
        XCTAssertEqual(store.gestures, before)
    }

    func testImportPackageMigratesLegacyDirections() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        store.replaceAll([])

        let legacy = GestureProfile(
            name: "Legacy",
            pattern: .directions([.up, .right]),
            action: .none
        )
        let package = GestureConfigFile(version: Constants.configVersion, gestures: [legacy])
        let data = try JSONEncoder().encode(package)
        _ = try store.importPackage(from: data)

        guard let imported = store.gestures.first else {
            return XCTFail("Expected imported gesture")
        }
        if case .freePath(let points) = imported.pattern {
            XCTAssertGreaterThanOrEqual(points.count, 2)
        } else {
            XCTFail("Expected freePath after migration")
        }
    }

    func testAnalyzeImportDetectsContentDuplicates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        let existing = GestureProfile(
            name: "Same",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        store.replaceAll([existing])

        let duplicate = GestureProfile(
            name: "Same",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        let unique = GestureProfile(
            name: "New",
            pattern: .freePath(PathTemplates.down),
            action: .media(.mute)
        )
        let package = GestureConfigFile(version: Constants.configVersion, gestures: [duplicate, unique])
        let data = try JSONEncoder().encode(package)

        let analysis = try store.analyzeImportPackage(from: data)
        XCTAssertEqual(analysis.duplicates.map(\.name), ["Same"])
        XCTAssertEqual(analysis.unique.map(\.name), ["New"])
        XCTAssertEqual(analysis.ordered.map(\.name), ["Same", "New"])
        XCTAssertTrue(analysis.hasDuplicates)
    }

    func testImportPackageSkipDuplicates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        let existing = GestureProfile(
            name: "Same",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        store.replaceAll([existing])

        let duplicate = GestureProfile(
            name: "Same",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        let unique = GestureProfile(
            name: "New",
            pattern: .freePath(PathTemplates.down)
        )
        let data = try JSONEncoder().encode(
            GestureConfigFile(version: Constants.configVersion, gestures: [duplicate, unique])
        )

        let newIDs = try store.importPackage(from: data, duplicatePolicy: .skipDuplicates)
        XCTAssertEqual(newIDs.count, 1)
        XCTAssertEqual(store.gestures.count, 2)
        XCTAssertEqual(store.gestures.map(\.name).sorted(), ["New", "Same"])
    }

    func testImportPackageForceAllAllowsDuplicatesDisabled() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        let existing = GestureProfile(
            name: "Same",
            isEnabled: true,
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        let unique = GestureProfile(
            name: "Unique",
            isEnabled: true,
            pattern: .freePath(PathTemplates.down)
        )
        store.replaceAll([existing])

        let duplicate = GestureProfile(
            name: "Same",
            isEnabled: true,
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        let data = try JSONEncoder().encode(
            GestureConfigFile(version: Constants.configVersion, gestures: [duplicate, unique])
        )

        let newIDs = try store.importPackage(from: data, duplicatePolicy: .forceAll)
        XCTAssertEqual(newIDs.count, 2)
        XCTAssertEqual(store.gestures.count, 3)

        let forcedDuplicate = store.gestures.first { $0.id == newIDs[0] }
        let forcedUnique = store.gestures.first { $0.id == newIDs[1] }
        XCTAssertEqual(forcedDuplicate?.name, "Same")
        XCTAssertEqual(forcedDuplicate?.isEnabled, false)
        XCTAssertEqual(forcedUnique?.name, "Unique")
        XCTAssertEqual(forcedUnique?.isEnabled, true)
        XCTAssertEqual(store.gestures.first?.isEnabled, true)
    }

    func testProfilesToImportForceDisablesDuplicates() {
        let existing = GestureProfile(name: "Dup", pattern: .freePath(PathTemplates.up))
        let unique = GestureProfile(name: "New", isEnabled: true, pattern: .freePath(PathTemplates.down))
        let analysis = GestureImportAnalysis(
            unique: [unique],
            duplicates: [existing],
            ordered: [existing, unique]
        )
        let forced = analysis.profilesToImport(policy: .forceAll)
        XCTAssertEqual(forced.count, 2)
        XCTAssertFalse(forced[0].isEnabled)
        XCTAssertTrue(forced[1].isEnabled)
        XCTAssertEqual(analysis.profilesToImport(policy: .skipDuplicates).map(\.name), ["New"])
    }

    func testContentEqualityIgnoresID() {
        let a = GestureProfile(
            id: UUID(),
            name: "X",
            pattern: .freePath(PathTemplates.left),
            action: .window(.close)
        )
        let b = GestureProfile(
            id: UUID(),
            name: "X",
            pattern: .freePath(PathTemplates.left),
            action: .window(.close)
        )
        XCTAssertTrue(a.isContentEqual(to: b))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertFalse(a.isContentEqual(to: GestureProfile(name: "Y", pattern: .freePath(PathTemplates.left))))
    }
}
