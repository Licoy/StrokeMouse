import XCTest
@testable import StrokeMouse

final class BackupMergePlannerTests: XCTestCase {
    func testMergePreservesLocalAndAppendsBackupOnlyInBackupOrder() throws {
        let localA = profile(name: "Local A", points: PathTemplates.up)
        let localB = profile(name: "Local B", points: PathTemplates.down)
        let backupA = profile(name: "Backup A", points: PathTemplates.left)
        let contentDuplicate = copy(localB, id: UUID())
        let backupB = profile(name: "Backup B", points: PathTemplates.right)

        let plan = try makePlan(
            local: [localA, localB],
            backup: [backupA, contentDuplicate, backupB]
        )
        let result = try plan.resolve()

        XCTAssertTrue(plan.gestureConflicts.isEmpty)
        XCTAssertEqual(
            result.gestureFile.gestures.map(\.id),
            [localA.id, localB.id, backupA.id, backupB.id]
        )
    }

    func testDifferentContentWithSameIDRequiresDecision() throws {
        let sharedID = UUID()
        let local = profile(
            id: sharedID,
            name: "Local",
            points: PathTemplates.up
        )
        let backup = profile(
            id: sharedID,
            name: "Backup",
            points: PathTemplates.down
        )
        let plan = try makePlan(local: [local], backup: [backup])

        XCTAssertEqual(
            plan.gestureConflicts,
            [BackupGestureConflict(id: sharedID, local: local, backup: backup)]
        )
        XCTAssertThrowsError(try plan.resolve()) { error in
            XCTAssertEqual(
                error as? BackupMergePlannerError,
                .unresolvedGestureConflicts([sharedID])
            )
        }
    }

    func testSameIDConflictCanKeepLocalOrUseBackupWithoutDeletingOthers()
        throws
    {
        let sharedID = UUID()
        let untouched = profile(name: "Untouched", points: PathTemplates.left)
        let local = profile(
            id: sharedID,
            name: "Local",
            points: PathTemplates.up
        )
        let backup = profile(
            id: sharedID,
            name: "Backup",
            points: PathTemplates.down
        )
        let appended = profile(name: "Appended", points: PathTemplates.right)
        let plan = try makePlan(
            local: [untouched, local],
            backup: [backup, appended]
        )

        let keepLocal = try plan.resolve(decisions: .init(
            gestures: [sharedID: .keepLocal]
        ))
        XCTAssertEqual(
            keepLocal.gestureFile.gestures,
            [untouched, local, appended]
        )

        let useBackup = try plan.resolve(decisions: .init(
            gestures: [sharedID: .useBackup]
        ))
        XCTAssertEqual(
            useBackup.gestureFile.gestures,
            [untouched, backup, appended]
        )
    }

    func testKeepBothCreatesDisabledCopyWithNewIDInBackupOrder() throws {
        let sharedID = UUID()
        let generatedID = UUID()
        let local = profile(
            id: sharedID,
            name: "Local",
            points: PathTemplates.up
        )
        let backup = profile(
            id: sharedID,
            name: "Backup",
            points: PathTemplates.down
        )
        let appended = profile(name: "Appended", points: PathTemplates.left)
        let plan = try makePlan(
            local: [local],
            backup: [backup, appended]
        )

        let result = try plan.resolve(
            decisions: .init(gestures: [sharedID: .keepBoth]),
            makeUUID: { generatedID }
        )

        XCTAssertEqual(
            result.gestureFile.gestures.map(\.id),
            [sharedID, generatedID, appended.id]
        )
        XCTAssertEqual(result.gestureFile.gestures[1].name, "Backup")
        XCTAssertFalse(result.gestureFile.gestures[1].isEnabled)
    }

    func testContentDuplicateCanBeKeptAsDisabledNewIDCopy() throws {
        let generatedID = UUID()
        let local = profile(name: "Same", points: PathTemplates.up)
        let backup = copy(local, id: UUID())
        let plan = try makePlan(local: [local], backup: [backup])

        let skipped = try plan.resolve()
        XCTAssertEqual(skipped.gestureFile.gestures, [local])

        let copied = try plan.resolve(
            duplicatePolicy: .keepDisabledCopy,
            makeUUID: { generatedID }
        )
        XCTAssertEqual(copied.gestureFile.gestures.map(\.id), [local.id, generatedID])
        XCTAssertFalse(copied.gestureFile.gestures[1].isEnabled)
    }

    func testContentDuplicatePolicyCanBeChosenPerBackupGesture() throws {
        let generatedID = UUID()
        let localA = profile(name: "Same A", points: PathTemplates.up)
        let localB = profile(name: "Same B", points: PathTemplates.down)
        let backupA = copy(localA, id: UUID())
        let backupB = copy(localB, id: UUID())
        let plan = try makePlan(
            local: [localA, localB],
            backup: [backupA, backupB]
        )

        let result = try plan.resolve(
            decisions: .init(contentDuplicates: [
                backupA.id: .skip,
                backupB.id: .keepDisabledCopy,
            ]),
            duplicatePolicy: .keepDisabledCopy,
            makeUUID: { generatedID }
        )

        XCTAssertEqual(
            result.gestureFile.gestures.map(\.id),
            [localA.id, localB.id, generatedID]
        )
        XCTAssertEqual(result.gestureFile.gestures.last?.name, "Same B")
        XCTAssertFalse(try XCTUnwrap(result.gestureFile.gestures.last).isEnabled)
    }

    func testSettingsMergeAddsBackupOnlyAndRequiresPerKeyChoices()
        throws
    {
        let plan = try BackupMergePlanner.plan(
            local: file([]),
            backup: file([]),
            localSettings: [
                "same": "value",
                "localOnly": "local",
                "conflict": "local",
            ],
            backupSettings: [
                "same": "value",
                "backupOnly": "backup",
                "conflict": "backup",
            ]
        )

        XCTAssertEqual(
            plan.settingConflicts,
            [BackupSettingConflict(
                key: "conflict",
                local: "local",
                backup: "backup"
            )]
        )
        XCTAssertThrowsError(try plan.resolve()) { error in
            XCTAssertEqual(
                error as? BackupMergePlannerError,
                .unresolvedSettingConflicts(["conflict"])
            )
        }

        let result = try plan.resolve(decisions: .init(settings: [
            "conflict": .useBackup,
        ]))
        XCTAssertEqual(result.settings, [
            "same": "value",
            "localOnly": "local",
            "backupOnly": "backup",
            "conflict": "backup",
        ])
    }

    func testAmbiguityResolutionMergeHandlesLegacyAndCurrentBackups() throws {
        let localDefaults = UserDefaults(
            suiteName: "BackupMergePlannerTests-\(UUID().uuidString)"
        )!
        let destination = UserDefaults(
            suiteName: "BackupMergePlannerTests-\(UUID().uuidString)"
        )!
        defer {
            for key in localDefaults.dictionaryRepresentation().keys {
                localDefaults.removeObject(forKey: key)
            }
            for key in destination.dictionaryRepresentation().keys {
                destination.removeObject(forKey: key)
            }
        }
        localDefaults.set(
            GestureAmbiguityResolution.chooseBest.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        let local = PortableSettingsV1.capture(from: localDefaults)
        var currentBackup = local
        currentBackup.ambiguityResolution = GestureAmbiguityResolution.reject.rawValue
        let legacyBackup = try removingAmbiguityResolution(from: currentBackup)

        let legacyPlan = try BackupMergePlanner.plan(
            local: file([]),
            backup: file([]),
            localSettings: local.mergeValues,
            backupSettings: legacyBackup.mergeValues
        )
        XCTAssertFalse(legacyBackup.mergeValues.keys.contains(
            "ambiguityResolution"
        ))
        XCTAssertTrue(legacyPlan.settingConflicts.isEmpty)
        let legacyResolved = try local.replacingMergeValues(
            legacyPlan.resolve().settings
        )
        try legacyResolved.apply(to: destination)
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.chooseBest.rawValue
        )

        let currentPlan = try BackupMergePlanner.plan(
            local: file([]),
            backup: file([]),
            localSettings: local.mergeValues,
            backupSettings: currentBackup.mergeValues
        )
        XCTAssertEqual(
            currentPlan.settingConflicts.map(\.key),
            ["ambiguityResolution"]
        )

        let kept = try currentPlan.resolve(decisions: .init(settings: [
            "ambiguityResolution": .keepLocal,
        ]))
        try local.replacingMergeValues(kept.settings).apply(to: destination)
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.chooseBest.rawValue
        )

        let replaced = try currentPlan.resolve(decisions: .init(settings: [
            "ambiguityResolution": .useBackup,
        ]))
        try local.replacingMergeValues(replaced.settings).apply(to: destination)
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.reject.rawValue
        )
    }

    func testUnsupportedVersionAndDuplicateIDsAreRejected() {
        XCTAssertThrowsError(try BackupMergePlanner.plan(
            local: GestureConfigFile(version: 99, gestures: []),
            backup: file([]),
            localSettings: [String: String](),
            backupSettings: [:]
        )) { error in
            XCTAssertEqual(
                error as? BackupMergePlannerError,
                .unsupportedConfigVersion(side: .local, version: 99)
            )
        }

        let duplicate = profile(name: "Duplicate", points: PathTemplates.up)
        XCTAssertThrowsError(try BackupMergePlanner.plan(
            local: file([]),
            backup: file([duplicate, duplicate]),
            localSettings: [String: String](),
            backupSettings: [:]
        )) { error in
            XCTAssertEqual(
                error as? BackupMergePlannerError,
                .duplicateGestureID(side: .backup, id: duplicate.id)
            )
        }
    }

    func testGeneratedIDCollisionFailsExplicitly() throws {
        let local = profile(name: "Same", points: PathTemplates.up)
        let backup = copy(local, id: UUID())
        let plan = try makePlan(local: [local], backup: [backup])

        XCTAssertThrowsError(try plan.resolve(
            duplicatePolicy: .keepDisabledCopy,
            makeUUID: { local.id }
        )) { error in
            XCTAssertEqual(
                error as? BackupMergePlannerError,
                .generatedDuplicateGestureID(local.id)
            )
        }
    }

    private func makePlan(
        local: [GestureProfile],
        backup: [GestureProfile]
    ) throws -> BackupMergePlan<String> {
        try BackupMergePlanner.plan(
            local: file(local),
            backup: file(backup),
            localSettings: [:],
            backupSettings: [:]
        )
    }

    private func file(_ gestures: [GestureProfile]) -> GestureConfigFile {
        GestureConfigFile(
            version: Constants.configVersion,
            gestures: gestures
        )
    }

    private func removingAmbiguityResolution(
        from settings: PortableSettingsV1
    ) throws -> PortableSettingsV1 {
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "ambiguityResolution")
        return try JSONDecoder().decode(
            PortableSettingsV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func profile(
        id: UUID = UUID(),
        name: String,
        points: [CodablePoint]
    ) -> GestureProfile {
        GestureProfile(
            id: id,
            name: name,
            pattern: .freePath(points)
        )
    }

    private func copy(
        _ profile: GestureProfile,
        id: UUID
    ) -> GestureProfile {
        var result = profile
        result.id = id
        return result
    }
}
