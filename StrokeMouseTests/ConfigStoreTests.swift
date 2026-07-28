import XCTest
@testable import StrokeMouse

@MainActor
final class ConfigStoreTests: XCTestCase {
    func testV2ProfileEncodingUsesTaggedInputWithoutLegacyFields() throws {
        let profile = GestureProfile(
            name: "Fn Drawing",
            input: .drawn(
                DrawnGesture(
                    activation: .modifier(.function),
                    points: [
                        CodablePoint(x: 0, y: 0),
                        CodablePoint(x: 1, y: 0),
                    ]
                )
            )
        )

        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["trigger"])
        XCTAssertNil(object["pattern"])

        let input = try XCTUnwrap(object["input"] as? [String: Any])
        XCTAssertEqual(input["type"] as? String, "drawn")
        let value = try XCTUnwrap(input["value"] as? [String: Any])
        let activation = try XCTUnwrap(value["activation"] as? [String: Any])
        XCTAssertEqual(activation["type"] as? String, "modifier")
        XCTAssertEqual(activation["key"] as? String, "function")
        XCTAssertEqual((value["points"] as? [[String: Any]])?.count, 2)
    }

    func testGestureProfileDirectDecodeRejectsLegacyFields() throws {
        let data = Data(
            """
            {
              "id": "F6702898-C292-48C9-AE64-FF528BAFAC8A",
              "name": "Legacy profile",
              "trigger": {"button": "middle"},
              "pattern": {"directions": {"_0": ["left", "down"]}}
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(
            GestureProfile.self,
            from: data
        ))
    }

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
        if case .drawn(let drawn) = reloaded.gestures.first?.input {
            let pts = drawn.points
            XCTAssertGreaterThanOrEqual(pts.count, 2)
        } else {
            XCTFail("Expected freePath pattern")
        }

        try? FileManager.default.removeItem(at: dir)
    }

    func testLoadingV1MigratesToV2AndPreservesOriginalBackup() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let legacyData = Data(
            """
            {
              "version": 1,
              "gestures": [{
                "id": "C49B3DF7-5ED2-433C-AFA3-E44E3EFCA08B",
                "name": "Legacy Directions",
                "pattern": {"directions": {"_0": ["up", "right"]}},
                "notes": "v1"
              }]
            }
            """.utf8
        )
        try legacyData.write(to: url)

        let store = ConfigStore(configURL: url)

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.gestures.map(\.name), ["Legacy Directions"])
        if case .drawn(let drawn) = store.gestures.first?.input,
           case .mouse(let trigger) = drawn.activation
        {
            XCTAssertEqual(trigger.button, .right)
            let points = drawn.points
            XCTAssertGreaterThanOrEqual(points.count, 2)
        } else {
            XCTFail("Expected migrated free-path points")
        }

        let backupURL = dir.appendingPathComponent("gestures.json.v1.bak")
        XCTAssertEqual(try Data(contentsOf: backupURL), legacyData)

        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(migratedObject["version"] as? Int, 2)
        let profiles = try XCTUnwrap(migratedObject["gestures"] as? [[String: Any]])
        XCTAssertNotNil(profiles.first?["input"])
        XCTAssertNil(profiles.first?["trigger"])
        XCTAssertNil(profiles.first?["pattern"])
    }

    func testExistingV1BackupIsNeverOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StrokeMouseTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("gestures.json")
        let backupURL = dir.appendingPathComponent("gestures.json.v1.bak")
        let existingBackup = Data("existing-backup".utf8)
        try existingBackup.write(to: backupURL)
        try legacyConfigData().write(to: url)

        let store = ConfigStore(configURL: url)

        XCTAssertNil(store.lastFailure)
        XCTAssertEqual(try Data(contentsOf: backupURL), existingBackup)
    }

    func testMigrationReplaceFailureKeepsV1FileAndBackup() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StrokeMouseTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("gestures.json")
        let original = legacyConfigData()
        try original.write(to: url)

        let store = ConfigStore(
            configURL: url,
            replaceItem: { _, _ in
                throw CocoaError(.fileWriteUnknown)
            }
        )

        XCTAssertTrue(store.gestures.isEmpty)
        guard case .persistenceFailed = store.lastFailure else {
            return XCTFail("Expected replacement failure")
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(
            try Data(contentsOf: dir.appendingPathComponent(
                "gestures.json.v1.bak"
            )),
            original
        )
    }

    func testInvalidV2FileIsNotRewritten() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StrokeMouseTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("gestures.json")
        let invalid = GestureProfile(
            name: "Invalid",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: [CodablePoint(x: 0, y: 0)]
            ))
        )
        let bytes = try JSONEncoder().encode(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [invalid]
        ))
        try bytes.write(to: url)

        let store = ConfigStore(configURL: url)

        XCTAssertTrue(store.gestures.isEmpty)
        guard case .invalidConfiguration = store.lastFailure else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testV1MigrationPreservesProfileFieldsAndOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let data = Data(
            """
            {
              "version": 1,
              "gestures": [{
                "id": "62BB5B6B-D101-4A78-BABE-E4F8B39BB299",
                "name": "First",
                "isEnabled": false,
                "trigger": {"button": "sideBack", "requireFlags": 123},
                "pattern": {"freePath": {"_0": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]}},
                "action": {"openURL": {"_0": "https://example.com"}},
                "scope": {"apps": {"_0": ["com.apple.Safari"]}},
                "targetPolicy": "windowUnderPointer",
                "notes": "preserved"
              }, {
                "id": "6553222D-63CD-4925-86F8-D3C3B9C3F298",
                "name": "Second",
                "pattern": {"freePath": {"_0": [{"x": 1, "y": 0}, {"x": 0, "y": 1}]}}
              }]
            }
            """.utf8
        )
        try data.write(to: url)

        let store = ConfigStore(configURL: url)
        let first = try XCTUnwrap(store.gestures.first)

        XCTAssertEqual(store.gestures.map(\.name), ["First", "Second"])
        XCTAssertFalse(first.isEnabled)
        guard case .drawn(let drawn) = first.input,
              case .mouse(let trigger) = drawn.activation
        else {
            return XCTFail("Expected migrated mouse-drawn input")
        }
        XCTAssertEqual(
            trigger,
            GestureTrigger(button: .sideBack, requireFlags: 123)
        )
        XCTAssertEqual(first.action, .openURL("https://example.com"))
        XCTAssertEqual(first.scope, .apps(["com.apple.Safari"]))
        XCTAssertEqual(first.targetPolicy, .windowUnderPointer)
        XCTAssertEqual(first.notes, "preserved")
    }

    func testInvalidDrawnPointsDoNotChangeMemoryOrPersistedConfig() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)
        let beforeProfiles = store.gestures
        let beforeData = try Data(contentsOf: url)
        let invalid = GestureProfile(
            name: "Too Short",
            input: .drawn(
                DrawnGesture(
                    activation: .modifier(.function),
                    points: [CodablePoint(x: 0, y: 0)]
                )
            )
        )

        store.replaceAll([invalid])

        XCTAssertEqual(store.gestures, beforeProfiles)
        XCTAssertEqual(try Data(contentsOf: url), beforeData)
        guard case .invalidConfiguration = store.lastFailure else {
            return XCTFail("Expected a typed invalid-configuration failure")
        }
    }

    func testNonFiniteDrawnPointDoesNotChangeMemoryOrPersistedConfig() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)
        let beforeProfiles = store.gestures
        let beforeData = try Data(contentsOf: url)
        let invalid = GestureProfile(
            name: "Non-finite",
            input: .drawn(
                DrawnGesture(
                    activation: .modifier(.option),
                    points: [
                        CodablePoint(x: 0, y: 0),
                        CodablePoint(x: .infinity, y: 1),
                    ]
                )
            )
        )

        store.replaceAll([invalid])

        XCTAssertEqual(store.gestures, beforeProfiles)
        XCTAssertEqual(try Data(contentsOf: url), beforeData)
        guard case .invalidConfiguration = store.lastFailure else {
            return XCTFail("Expected a typed invalid-configuration failure")
        }
    }

    func testAllThirtyFourTrackpadGesturesRoundTripInV2Config() throws {
        var gestures: [DirectTrackpadGesture] = []
        for fingers in StandardFingerCount.allCases {
            gestures += TapCount.allCases.map { .tap(fingers, $0) }
            gestures += CardinalDirection.allCases.map { .swipe(fingers, $0) }
        }
        for fingers in TransformFingerCount.allCases {
            gestures += PinchDirection.allCases.map { .pinch(fingers, $0) }
            gestures += RotationDirection.allCases.map { .rotate(fingers, $0) }
        }
        XCTAssertEqual(gestures.count, 34)

        let profiles = gestures.enumerated().map { index, gesture in
            GestureProfile(
                name: "Trackpad \(index)",
                input: .trackpad(gesture)
            )
        }
        let source = GestureConfigFile(version: 2, gestures: profiles)
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(GestureConfigFile.self, from: data)

        XCTAssertEqual(decoded, source)
    }

    func testFutureVersionIsRejectedWithoutRewritingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let data = Data(#"{"version":99,"gestures":[]}"#.utf8)
        try data.write(to: url)

        let store = ConfigStore(configURL: url)

        XCTAssertTrue(store.gestures.isEmpty)
        XCTAssertEqual(store.lastFailure, .unsupportedVersion(99))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testCorruptExistingFileIsNotReplacedByDefaults() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let data = Data("not-json".utf8)
        try data.write(to: url)

        let store = ConfigStore(configURL: url)

        XCTAssertTrue(store.gestures.isEmpty)
        guard case .decodeFailed = store.lastFailure else {
            return XCTFail("Expected a typed decode failure")
        }
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testV2RootRejectsLegacyProfileShapeWithoutRewritingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StrokeMouseTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("gestures.json")
        let data = Data(
            """
            {
              "version": 2,
              "gestures": [{
                "id": "F6702898-C292-48C9-AE64-FF528BAFAC8A",
                "name": "Wrong schema",
                "trigger": {"button": "middle"},
                "pattern": {"directions": {"_0": ["left"]}}
              }]
            }
            """.utf8
        )
        try data.write(to: url)

        let store = ConfigStore(configURL: url)

        guard case .decodeFailed = store.lastFailure else {
            return XCTFail("Expected a typed decode failure")
        }
        XCTAssertTrue(store.requiresRecovery)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testRecoveryBlocksMutationAndPreservesOriginalBeforeReset()
        throws
    {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "StrokeMouseTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("gestures.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: url)
        let store = ConfigStore(configURL: url)

        store.add(GestureProfile(
            name: "Must not overwrite",
            pattern: .freePath(PathTemplates.up)
        ))

        XCTAssertTrue(store.requiresRecovery)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)

        let backupURL = try XCTUnwrap(
            store.recoverWithDefaults()
        )

        XCTAssertEqual(try Data(contentsOf: backupURL), corrupt)
        XCTAssertFalse(store.requiresRecovery)
        XCTAssertFalse(store.gestures.isEmpty)
        let recovered = try JSONDecoder().decode(
            GestureConfigFile.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(recovered.version, Constants.configVersion)
        XCTAssertEqual(recovered.gestures, store.gestures)
    }

    func testDuplicateProfileIDsDoNotChangeMemoryOrPersistedConfig() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("gestures.json")
        let store = ConfigStore(configURL: url)
        let beforeProfiles = store.gestures
        let beforeData = try Data(contentsOf: url)
        let duplicate = GestureProfile(
            name: "Duplicate",
            pattern: .freePath(PathTemplates.up)
        )

        store.replaceAll([duplicate, duplicate])

        XCTAssertEqual(store.gestures, beforeProfiles)
        XCTAssertEqual(try Data(contentsOf: url), beforeData)
        guard case .invalidConfiguration = store.lastFailure else {
            return XCTFail("Expected a typed invalid-configuration failure")
        }
    }

    func testPersistenceFailureDoesNotPublishCandidate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ConfigStore(configURL: configDirectory.appendingPathComponent("gestures.json"))
        let before = store.gestures
        let movedDirectory = root.appendingPathComponent("moved-config", isDirectory: true)
        try FileManager.default.moveItem(at: configDirectory, to: movedDirectory)
        try Data("blocks-directory-creation".utf8).write(to: configDirectory)

        store.replaceAll([
            GestureProfile(name: "Candidate", pattern: .freePath(PathTemplates.left)),
        ])

        XCTAssertEqual(store.gestures, before)
        guard case .persistenceFailed = store.lastFailure else {
            return XCTFail("Expected a typed persistence failure")
        }
    }

    func testLegacyProfileWithoutTargetPolicyDefaultsToFrontmostWindow() throws {
        let profile = GestureProfile(
            name: "Legacy",
            pattern: .freePath(PathTemplates.up)
        )
        let encoded = try JSONEncoder().encode(profile)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "targetPolicy")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(GestureProfile.self, from: legacyData)

        XCTAssertEqual(decoded.targetPolicy, .frontmostWindow)
    }

    func testTargetPolicyRoundTrips() throws {
        let profile = GestureProfile(
            name: "Hover",
            pattern: .freePath(PathTemplates.down),
            targetPolicy: .windowUnderPointer
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GestureProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
    }

    func testExistingDefaultGesturesKeepFrontmostTargetPolicy() {
        let defaults = DefaultGestures.make()
        XCTAssertEqual(defaults.count, 7)
        XCTAssertTrue(defaults.allSatisfy {
            $0.targetPolicy == .frontmostWindow
        })
        XCTAssertTrue(defaults.allSatisfy {
            guard case .drawn(let drawn) = $0.input,
                  case .mouse(let trigger) = drawn.activation
            else {
                return false
            }
            return trigger.button == .right
        })
    }

    func testEnabledGesturesOnlyFiltersEnabledStateAndTrigger() {
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
        let disabled = GestureProfile(
            name: "Disabled",
            isEnabled: false,
            pattern: .freePath(PathTemplates.left)
        )
        store.replaceAll([global, safariOnly, disabled])

        let right = store.enabledGestures(button: .right)
        XCTAssertEqual(right.map(\.name), ["Global", "Safari"])

        // Middle button has no matching profiles.
        let middle = store.enabledGestures(button: .middle)
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

        let r = store.enabledGestures(button: .right)
        XCTAssertEqual(r.map(\.name), ["Right"])

        let m = store.enabledGestures(button: .middle)
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

    func testWindowUnderPointerPolicySurvivesExportAnalysisAndImport() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = ConfigStore(configURL: dir.appendingPathComponent("source.json"))
        let profile = GestureProfile(
            name: "Pointer Target",
            pattern: .freePath(PathTemplates.downRight),
            scope: .apps(["com.apple.Safari"]),
            targetPolicy: .windowUnderPointer
        )
        source.replaceAll([profile])
        let package = try source.exportPackage(ids: [profile.id])

        let destinationURL = dir.appendingPathComponent("destination.json")
        let destination = ConfigStore(configURL: destinationURL)
        destination.replaceAll([])
        let analysis = try destination.analyzeImportPackage(from: package)
        XCTAssertEqual(analysis.unique.map(\.targetPolicy), [.windowUnderPointer])

        let importedIDs = try destination.importPackage(from: package)
        let imported = try XCTUnwrap(
            destination.gestures.first { importedIDs.contains($0.id) }
        )
        XCTAssertEqual(imported.targetPolicy, .windowUnderPointer)
        XCTAssertEqual(imported.scope, .apps(["com.apple.Safari"]))

        let reloaded = ConfigStore(configURL: destinationURL)
        XCTAssertEqual(reloaded.gestures.first?.targetPolicy, .windowUnderPointer)
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
        if case .drawn(let drawn) = imported.input {
            let points = drawn.points
            XCTAssertGreaterThanOrEqual(points.count, 2)
        } else {
            XCTFail("Expected freePath after migration")
        }
    }

    func testImportPackageAcceptsActualV1Shape() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigStore(configURL: dir.appendingPathComponent("gestures.json"))
        store.replaceAll([])
        let data = Data(
            """
            {
              "version": 1,
              "gestures": [{
                "id": "F6702898-C292-48C9-AE64-FF528BAFAC8A",
                "name": "Imported v1",
                "trigger": {"button": "middle"},
                "pattern": {"directions": {"_0": ["left", "down"]}}
              }]
            }
            """.utf8
        )

        let importedIDs = try store.importPackage(from: data)
        let imported = try XCTUnwrap(
            store.gestures.first { importedIDs.contains($0.id) }
        )

        guard case .drawn(let drawn) = imported.input,
              case .mouse(let trigger) = drawn.activation
        else {
            return XCTFail("Expected a migrated mouse-drawn gesture")
        }
        XCTAssertEqual(trigger, GestureTrigger(button: .middle))
        XCTAssertGreaterThanOrEqual(drawn.points.count, 2)
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

        var differentTarget = b
        differentTarget.targetPolicy = .windowUnderPointer
        XCTAssertFalse(a.isContentEqual(to: differentTarget))
    }

    private func legacyConfigData() -> Data {
        Data(
            """
            {
              "version": 1,
              "gestures": [{
                "id": "C49B3DF7-5ED2-433C-AFA3-E44E3EFCA08B",
                "name": "Legacy",
                "pattern": {"directions": {"_0": ["up"]}}
              }]
            }
            """.utf8
        )
    }
}
