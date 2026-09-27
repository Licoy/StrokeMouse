import XCTest
@testable import StrokeMouse

@MainActor
final class ConfigStoreAppRulesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPoliciesGroupsAndGroupScopedGesturesPersist() throws {
        let store = makeStore()
        let group = AppGroup(
            name: "Adobe",
            matchers: [.bundleIdentifierPattern("com.adobe.*")],
            suppressedGlobalInputs: .all
        )
        store.setSuppressedGlobalInputs(.all, forBundleIdentifier: "  com.blender.Blender ")
        store.addAppGroup(group)
        store.replaceAll([
            GestureProfile(
                name: "Undo",
                pattern: .freePath(PathTemplates.left),
                scope: .group(group.id)
            ),
        ])

        let reloaded = makeStore()

        XCTAssertNil(reloaded.lastFailure)
        XCTAssertEqual(reloaded.appGroups, [group])
        XCTAssertEqual(reloaded.appPolicies, [
            AppGesturePolicy(bundleIdentifier: "com.blender.Blender"),
        ])
        XCTAssertEqual(reloaded.gestures.first?.scope, .group(group.id))
        XCTAssertEqual(
            reloaded.appPolicy(forBundleIdentifier: "COM.BLENDER.BLENDER")?
                .suppressedGlobalInputs,
            .all
        )
    }

    func testEmptySuppressionRemovesThePolicy() {
        let store = makeStore()
        store.setSuppressedGlobalInputs(.all, forBundleIdentifier: "com.blender.Blender")
        store.setSuppressedGlobalInputs(
            SuppressedGlobalInputs(kinds: [.mouseDrawing]),
            forBundleIdentifier: "com.blender.blender"
        )

        XCTAssertEqual(store.appPolicies.count, 1)
        XCTAssertEqual(store.appPolicies.first?.suppressedGlobalInputs.kinds, [.mouseDrawing])

        store.removeAppPolicy(forBundleIdentifier: "com.blender.Blender")
        XCTAssertTrue(store.appPolicies.isEmpty)
    }

    func testGestureReferencingMissingGroupIsRejected() throws {
        let store = makeStore()
        let before = store.gestures
        let missing = UUID()

        store.add(GestureProfile(
            name: "Orphan",
            pattern: .freePath(PathTemplates.up),
            scope: .group(missing)
        ))

        XCTAssertEqual(
            store.lastFailure,
            .invalidConfiguration(.missingAppGroup(missing))
        )
        XCTAssertEqual(store.gestures, before)
        XCTAssertEqual(makeStore().gestures, before)
    }

    func testDeletingGroupDeletesOrGlobalizesItsGestures() {
        let store = makeStore()
        let kept = AppGroup(name: "Kept")
        let removed = AppGroup(name: "Removed")
        store.addAppGroup(kept)
        store.addAppGroup(removed)
        let inKept = GestureProfile(name: "A", pattern: .freePath(PathTemplates.up), scope: .group(kept.id))
        let inRemoved = GestureProfile(name: "B", pattern: .freePath(PathTemplates.down), scope: .group(removed.id))
        store.replaceAll([inKept, inRemoved])

        store.deleteAppGroup(id: removed.id, gestures: .makeGlobal)
        XCTAssertEqual(store.appGroups, [kept])
        XCTAssertEqual(store.gestures.map(\.scope), [.group(kept.id), .global])

        store.deleteAppGroup(id: kept.id, gestures: .delete)
        XCTAssertTrue(store.appGroups.isEmpty)
        XCTAssertEqual(store.gestures.map(\.id), [inRemoved.id])
    }

    func testSetScopeMovesSelectedGestures() {
        let store = makeStore()
        let group = AppGroup(name: "Games")
        store.addAppGroup(group)
        let a = GestureProfile(name: "A", pattern: .freePath(PathTemplates.up))
        let b = GestureProfile(name: "B", pattern: .freePath(PathTemplates.down))
        store.replaceAll([a, b])

        store.setScope(.group(group.id), forGestureIDs: [a.id])

        XCTAssertEqual(store.gestures.map(\.scope), [.group(group.id), .global])
    }

    func testExportCarriesGroupsAndImportAddsOrReusesThem() throws {
        let source = makeStore(named: "source.json")
        let group = AppGroup(name: "Unity", matchers: [.bundleIdentifierPattern("unity.*")])
        source.addAppGroup(group)
        let profile = GestureProfile(
            name: "Grouped",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )
        source.replaceAll([profile])
        let package = try source.exportPackage(ids: [profile.id])

        let fresh = makeStore(named: "fresh.json")
        fresh.replaceAll([])
        let freshIDs = try fresh.importPackage(from: package)
        XCTAssertEqual(fresh.appGroups, [group])
        XCTAssertEqual(
            fresh.gestures.first { freshIDs.contains($0.id) }?.scope,
            .group(group.id)
        )

        let existing = makeStore(named: "existing.json")
        let sameContent = AppGroup(name: "Unity", matchers: [.bundleIdentifierPattern("unity.*")])
        existing.replaceAll([])
        existing.addAppGroup(sameContent)
        let existingIDs = try existing.importPackage(from: package)
        XCTAssertEqual(existing.appGroups, [sameContent])
        XCTAssertEqual(
            existing.gestures.first { existingIDs.contains($0.id) }?.scope,
            .group(sameContent.id)
        )
    }

    func testImportDuplicateDetectionUsesRemappedGroup() throws {
        let source = makeStore(named: "source.json")
        let group = AppGroup(name: "Games", matchers: [.directory("/Games")])
        source.addAppGroup(group)
        let profile = GestureProfile(
            name: "Grouped",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )
        source.replaceAll([profile])
        let package = try source.exportPackage(ids: [profile.id])

        let destination = makeStore(named: "destination.json")
        let local = AppGroup(name: "Games", matchers: [.directory("/Games")])
        destination.addAppGroup(local)
        var localCopy = profile
        localCopy.id = UUID()
        localCopy.scope = .group(local.id)
        destination.replaceAll([localCopy])

        let analysis = try destination.analyzeImportPackage(from: package)
        XCTAssertEqual(analysis.duplicates.count, 1)
        XCTAssertTrue(analysis.groups.isEmpty)
    }

    func testBackupFileAndResetIncludeAppRules() throws {
        let store = makeStore()
        let group = AppGroup(name: "Games")
        store.addAppGroup(group)
        store.setSuppressedGlobalInputs(.all, forBundleIdentifier: "com.valvesoftware.steam")

        let backup = try store.makeBackupGestureFile()
        XCTAssertEqual(backup.appGroups, [group])
        XCTAssertEqual(backup.appPolicies.map(\.bundleIdentifier), ["com.valvesoftware.steam"])

        store.resetToDefaults()
        XCTAssertTrue(store.appGroups.isEmpty)
        XCTAssertTrue(store.appPolicies.isEmpty)

        try store.replaceFromBackup(backup)
        XCTAssertEqual(store.appGroups, [group])
    }

    func testPlainLibraryFileBytesAreUnchangedWithoutRules() throws {
        let store = makeStore()
        store.replaceAll([GestureProfile(name: "Up", pattern: .freePath(PathTemplates.up))])

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("gestures.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["version", "gestures"])
    }

    // MARK: - Backup merge

    func testMergeAddsBackupOnlyRulesAndKeepsLocalOnConflict() throws {
        let sharedID = UUID()
        let localGroup = AppGroup(id: sharedID, name: "Local")
        let backupSameID = AppGroup(id: sharedID, name: "Backup")
        let backupOnly = AppGroup(name: "Backup Only")
        let localPolicy = AppGesturePolicy(
            bundleIdentifier: "com.blender.Blender",
            suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.mouseDrawing])
        )
        let backupPolicy = AppGesturePolicy(bundleIdentifier: "com.blender.blender")
        let backupOnlyPolicy = AppGesturePolicy(bundleIdentifier: "com.adobe.Photoshop")
        let backupGesture = GestureProfile(
            name: "Backup",
            pattern: .freePath(PathTemplates.up),
            scope: .group(backupOnly.id)
        )

        let plan = try BackupMergePlanner.plan(
            local: GestureConfigFile(
                version: Constants.configVersion,
                gestures: [],
                appPolicies: [localPolicy],
                appGroups: [localGroup]
            ),
            backup: GestureConfigFile(
                version: Constants.configVersion,
                gestures: [backupGesture],
                appPolicies: [backupPolicy, backupOnlyPolicy],
                appGroups: [backupSameID, backupOnly]
            ),
            localSettings: [String: String](),
            backupSettings: [:]
        )
        let merged = try plan.resolve().gestureFile

        XCTAssertEqual(merged.appGroups, [localGroup, backupOnly])
        XCTAssertEqual(merged.appPolicies, [localPolicy, backupOnlyPolicy])
        XCTAssertEqual(merged.gestures.map(\.scope), [.group(backupOnly.id)])
        try makeStore().validateBackupGestureFile(merged)
    }

    // MARK: - Sidebar

    func testSidebarIncludesPolicyAppsAndGroupNodes() {
        let group = AppGroup(name: "Games")
        let grouped = GestureProfile(
            name: "G",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )
        let global = GestureProfile(name: "Global", pattern: .freePath(PathTemplates.down))

        XCTAssertEqual(
            GestureSidebarCatalog.sidebarAppBundleIds(
                gestures: [grouped, global],
                pinnedBundleIds: ["com.apple.Safari"],
                policyBundleIds: ["com.blender.Blender", " "]
            ),
            ["com.apple.Safari", "com.blender.Blender"]
        )
        XCTAssertEqual(
            GestureSidebarCatalog.gestures(in: .group(group.id), from: [grouped, global]).map(\.id),
            [grouped.id]
        )
        XCTAssertEqual(
            GestureSidebarCatalog.gestures(in: .global, from: [grouped, global]).map(\.id),
            [global.id]
        )
        XCTAssertEqual(GestureSidebarCatalog.defaultScope(for: .group(group.id)), .group(group.id))
        XCTAssertEqual(
            GestureSidebarCatalog.preferredSidebarItem(for: .group(group.id)),
            .group(group.id)
        )
    }

    // MARK: - Helpers

    private func makeStore(named name: String = "gestures.json") -> ConfigStore {
        ConfigStore(configURL: directory.appendingPathComponent(name))
    }
}
