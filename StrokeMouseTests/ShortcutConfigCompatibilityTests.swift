import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import StrokeMouse

@MainActor
final class ShortcutConfigCompatibilityTests: XCTestCase {
    func testOrderedShortcutSurvivesExportImportAndReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseShortcutTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let chord = ShortcutChord(
            modifiers: [.command, .option],
            keyCode: UInt16(kVK_ANSI_Q)
        )
        let action = GestureAction.shortcut(
            keyCode: UInt16(kVK_ANSI_Q),
            modifiers: 0,
            display: "⌘⌥Q",
            orderedChord: chord
        )
        let profile = GestureProfile(
            name: "Ordered Shortcut",
            pattern: .freePath(PathTemplates.up),
            action: action
        )

        let source = ConfigStore(configURL: directory.appendingPathComponent("source.json"))
        source.replaceAll([profile])
        let package = try source.exportPackage(ids: [profile.id])

        let exported = try JSONDecoder().decode(GestureConfigFile.self, from: package)
        XCTAssertEqual(exported.gestures.first?.action, action)

        let destinationURL = directory.appendingPathComponent("destination.json")
        let destination = ConfigStore(configURL: destinationURL)
        destination.replaceAll([])
        _ = try destination.importPackage(from: package)
        XCTAssertEqual(destination.gestures.first?.action, action)

        let reloaded = ConfigStore(configURL: destinationURL)
        XCTAssertEqual(reloaded.gestures.first?.action, action)
    }

    func testDefaultShortcutsRemainLegacyActions() {
        var shortcutChords: [ShortcutChord?] = []
        for profile in DefaultGestures.make() {
            guard case .shortcut(_, _, _, let orderedChord) = profile.action else { continue }
            shortcutChords.append(orderedChord)
        }

        XCTAssertFalse(shortcutChords.isEmpty)
        XCTAssertTrue(shortcutChords.allSatisfy { $0 == nil })
    }

    func testApplicationSwitchActionsSurviveExportImportAndReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseAppSwitchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profiles = ApplicationSwitchCommand.allCases.map { command in
            GestureProfile(
                name: command.rawValue,
                pattern: .freePath(PathTemplates.up),
                action: .applicationSwitch(command)
            )
        }
        let source = ConfigStore(
            configURL: directory.appendingPathComponent("source.json")
        )
        source.replaceAll(profiles)
        let package = try source.exportPackage(ids: Set(profiles.map(\.id)))

        let v018File = try JSONDecoder().decode(
            V018GestureConfigFile.self,
            from: package
        )
        XCTAssertEqual(v018File.version, 2)
        XCTAssertEqual(v018File.gestures.count, profiles.count)

        let exported = try JSONDecoder().decode(GestureConfigFile.self, from: package)
        XCTAssertEqual(exported.version, 2)
        XCTAssertEqual(exported.gestures.map(\.action), profiles.map(\.action))

        let destinationURL = directory.appendingPathComponent("destination.json")
        let destination = ConfigStore(configURL: destinationURL)
        destination.replaceAll([])
        _ = try destination.importPackage(from: package)

        XCTAssertEqual(destination.gestures.map(\.action), profiles.map(\.action))

        let reloaded = ConfigStore(configURL: destinationURL)
        XCTAssertEqual(reloaded.gestures.map(\.action), profiles.map(\.action))
    }

    func testNativeApplicationSwitchStorageIsRewrittenOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseAppSwitchMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = GestureProfile(
            name: "Application Switch",
            pattern: .freePath(PathTemplates.up),
            action: .applicationSwitch(.commandTab)
        )
        let sourceURL = directory.appendingPathComponent("source.json")
        let source = ConfigStore(configURL: sourceURL)
        source.replaceAll([profile])

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: sourceURL))
                as? [String: Any]
        )
        var gestures = try XCTUnwrap(root["gestures"] as? [[String: Any]])
        gestures[0]["action"] = [
            "applicationSwitch": ["_0": "commandTab"]
        ]
        root["gestures"] = gestures

        let destinationURL = directory.appendingPathComponent("destination.json")
        try JSONSerialization.data(withJSONObject: root).write(to: destinationURL)

        let migrated = ConfigStore(configURL: destinationURL)

        XCTAssertFalse(migrated.requiresRecovery)
        XCTAssertEqual(migrated.gestures.map(\.action), [.applicationSwitch(.commandTab)])
        XCTAssertNoThrow(try JSONDecoder().decode(
            V018GestureConfigFile.self,
            from: Data(contentsOf: destinationURL)
        ))
    }

    func testShortcutSequenceSurvivesExportImportAndReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseShortcutSequence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let paste = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_V))
        let send = ShortcutChord(modifiers: [], keyCode: UInt16(kVK_Return))
        let action = GestureAction.shortcut(chords: [paste, send])
        XCTAssertEqual(action, .shortcutSequence([paste, send]))
        XCTAssertTrue(action.requiresCapturedTarget)
        XCTAssertEqual(
            action.detail,
            "\(KeyCodeNames.shortcutDisplay(chord: paste)) → \(KeyCodeNames.shortcutDisplay(chord: send))"
        )

        let profile = GestureProfile(
            name: "Paste and Send",
            pattern: .freePath(PathTemplates.up),
            action: action
        )
        let source = ConfigStore(configURL: directory.appendingPathComponent("source.json"))
        source.replaceAll([profile])
        let package = try source.exportPackage(ids: [profile.id])

        // Older versions decode the first chord as a plain ordered shortcut.
        let v018File = try JSONDecoder().decode(V018GestureConfigFile.self, from: package)
        guard case .shortcut(let keyCode, _, let display) = v018File.gestures.first?.action else {
            return XCTFail("Expected a v0.0.18-readable shortcut")
        }
        XCTAssertEqual(keyCode, UInt16(kVK_ANSI_V))
        XCTAssertEqual(display, KeyCodeNames.shortcutDisplay(chord: paste))
        let v031File = try JSONDecoder().decode(V031GestureConfigFile.self, from: package)
        guard case .shortcut(_, _, _, let orderedChord) = v031File.gestures.first?.action else {
            return XCTFail("Expected a v0.0.31-readable shortcut")
        }
        XCTAssertEqual(orderedChord, paste)

        let destinationURL = directory.appendingPathComponent("destination.json")
        let destination = ConfigStore(configURL: destinationURL)
        destination.replaceAll([])
        _ = try destination.importPackage(from: package)
        XCTAssertEqual(destination.gestures.first?.action, action)

        let reloaded = ConfigStore(configURL: destinationURL)
        XCTAssertEqual(reloaded.gestures.first?.action, action)
    }

    func testSingleChordShortcutKeepsPlainShortcutBytes() throws {
        let chord = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_V))
        let action = GestureAction.shortcut(chords: [chord])

        XCTAssertEqual(action, .shortcut(chord: chord))
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(action), encoding: .utf8))
        XCTAssertFalse(json.contains("followingChords"))
    }

    func testSequenceStartingWithApplicationSwitchChordStaysASequence() throws {
        let commandTab = ApplicationSwitchCommand.commandTab.shortcutChord
        let send = ShortcutChord(modifiers: [], keyCode: UInt16(kVK_Return))
        let action = GestureAction.shortcut(chords: [commandTab, send])

        let decoded = try JSONDecoder().decode(
            GestureAction.self,
            from: JSONEncoder().encode(action)
        )

        XCTAssertEqual(decoded, .shortcutSequence([commandTab, send]))
    }

    func testFnVersionCoversPrimarySecondaryAndEverySequenceChord() throws {
        let fn = ShortcutChord(modifiers: [.function], keyCode: nil)
        let letter = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_V))
        let actions: [GestureAction] = [
            .shortcut(chord: fn),
            .shortcut(chord: ShortcutChord(modifiers: [.function, .control], keyCode: UInt16(kVK_LeftArrow))),
            .shortcutSequence([fn, letter]),
            .shortcutSequence([letter, fn]),
            .shortcut(keyCode: UInt16(kVK_ANSI_Q), modifiers: UInt(CGEventFlags.maskSecondaryFn.rawValue), display: "fnQ"),
            .shortcut(keyCode: UInt16(kVK_Function), modifiers: 0, display: "fn")
        ]
        for action in actions {
            for secondary in [false, true] {
                var profile = GestureProfile(
                    name: "Fn", pattern: .freePath(PathTemplates.up),
                    action: secondary ? .none : action
                )
                profile.secondaryAction = secondary ? action : nil
                XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 3)
                XCTAssertFalse(GestureConfigFile(version: 2, gestures: [profile]).hasSupportedVersion)
                XCTAssertTrue(GestureConfigFile(version: 3, gestures: [profile]).hasSupportedVersion)
            }
        }
    }

    func testFnSurvivesSaveExportImportBackupRestoreAndReload() throws {
        try withTemporaryDirectory { directory in
            let letter = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_V))
            let fn = ShortcutChord(modifiers: [.function], keyCode: nil)
            var profile = GestureProfile(
                name: "Fn Sequence", pattern: .freePath(PathTemplates.up),
                action: .shortcutSequence([letter, fn])
            )
            profile.secondaryAction = .shortcut(chord: fn)
            let regular = GestureProfile(name: "Regular", pattern: .freePath(PathTemplates.down))
            let sourceURL = directory.appendingPathComponent("source.json")
            let source = ConfigStore(configURL: sourceURL)
            source.replaceAll([profile, regular])
            XCTAssertNil(source.lastFailure)
            XCTAssertEqual(try JSONDecoder().decode(GestureConfigFile.self, from: Data(contentsOf: sourceURL)).version, 3)
            let package = try source.exportPackage(ids: [profile.id])
            XCTAssertEqual(try JSONDecoder().decode(GestureConfigFile.self, from: package).version, 3)
            let regularPackage = try source.exportPackage(ids: [regular.id])
            XCTAssertEqual(try JSONDecoder().decode(GestureConfigFile.self, from: regularPackage).version, 2)

            let destinationURL = directory.appendingPathComponent("destination.json")
            let destination = ConfigStore(configURL: destinationURL)
            destination.replaceAll([])
            let importedIDs = try destination.importPackage(from: package)
            XCTAssertEqual(destination.gestures.map(\.id), importedIDs)
            XCTAssertTrue(try XCTUnwrap(destination.gestures.first).isContentEqual(to: profile))
            let backup = try source.makeBackupGestureFile()
            XCTAssertEqual(backup.version, 3)
            try destination.replaceFromBackup(backup)
            XCTAssertEqual(ConfigStore(configURL: destinationURL).gestures, [profile, regular])

            source.replaceAll([regular])
            XCTAssertEqual(source.library.version, 2)
            XCTAssertEqual(try JSONDecoder().decode(GestureConfigFile.self, from: Data(contentsOf: sourceURL)).version, 2)
        }
    }

    func testUnknownVersionAndFnMislabeledAsV2AreRejectedWithoutOverwriting() throws {
        try withTemporaryDirectory { directory in
            let profile = GestureProfile(
                name: "Fn", pattern: .freePath(PathTemplates.up),
                action: .shortcut(chord: ShortcutChord(modifiers: [.function], keyCode: nil))
            )
            for version in [2, 99] {
                let file = GestureConfigFile(version: version, gestures: [profile])
                let data = try JSONEncoder().encode(file)
                let url = directory.appendingPathComponent("invalid-\(version).json")
                try data.write(to: url)
                let store = ConfigStore(configURL: url)
                XCTAssertTrue(store.requiresRecovery)
                XCTAssertEqual(store.lastFailure, .unsupportedVersion(version))
                XCTAssertEqual(try Data(contentsOf: url), data)
                XCTAssertFalse(store.save())
                XCTAssertThrowsError(try store.analyzeImportPackage(from: data))
                XCTAssertThrowsError(try store.validateBackupGestureFile(file))
            }
        }
    }

    func testLegacyNavigationFlagsDoNotRequireFnFormat() {
        let actions: [GestureAction] = [
            .shortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: UInt(CGEventFlags.maskNumericPad.rawValue), display: "←"),
            .shortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: UInt(CGEventFlags.maskSecondaryFn.rawValue), display: "←",
                      orderedChord: ShortcutChord(modifiers: [], keyCode: UInt16(kVK_LeftArrow)))
        ]
        for action in actions {
            let profile = GestureProfile(name: "Arrow", pattern: .freePath(PathTemplates.up), action: action)
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 2)
        }
    }

    func testSystemActionsRequireV4AndSurviveExportBackupAndReload() throws {
        try withTemporaryDirectory { directory in
            let fn = ShortcutChord(modifiers: [.function], keyCode: nil)
            for secondary in [false, true] {
                for command in SystemCommand.allCases {
                    let action = GestureAction.system(SystemAction(command: command, shortcutOverride: fn))
                    var profile = GestureProfile(name: "System", pattern: .freePath(PathTemplates.up),
                                                 action: secondary ? .none : action)
                    profile.secondaryAction = secondary ? action : nil
                    XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 4)
                    for version in [2, 3] {
                        XCTAssertFalse(GestureConfigFile(version: version, gestures: [profile]).hasSupportedVersion)
                    }
                    let url = directory.appendingPathComponent("source.json")
                    let source = ConfigStore(configURL: url)
                    source.replaceAll([profile])
                    XCTAssertNil(source.lastFailure)
                    let package = try source.exportPackage(ids: [profile.id])
                    let file = try JSONDecoder().decode(GestureConfigFile.self, from: package)
                    XCTAssertEqual(file.version, 4)
                    XCTAssertEqual(file.gestures, [profile])
                    XCTAssertEqual(ConfigStore(configURL: url).gestures, [profile])
                    let destination = ConfigStore(configURL: directory.appendingPathComponent("destination.json"))
                    destination.replaceAll([])
                    let importedIDs = try destination.importPackage(from: package)
                    XCTAssertEqual(destination.gestures.map(\.id), importedIDs)
                    XCTAssertEqual(destination.gestures.count, 1)
                    XCTAssertTrue(try XCTUnwrap(destination.gestures.first).isContentEqual(to: profile))
                    let backup = try source.makeBackupGestureFile()
                    XCTAssertEqual(backup.version, 4)
                    try destination.replaceFromBackup(backup)
                    XCTAssertEqual(destination.gestures, [profile])
                }
            }
        }
    }

    func testSystemDefaultChordsAndMissingOverrideDecode() throws {
        XCTAssertEqual(SystemCommand.allCases.map { $0.defaultChord.keyCode }, [126, 125, 123, 124])
        for command in SystemCommand.allCases {
            let data = Data("{\"command\":\"\(command.rawValue)\"}".utf8)
            let action = try JSONDecoder().decode(SystemAction.self, from: data)
            XCTAssertNil(action.shortcutOverride)
            XCTAssertEqual(action.effectiveChord, command.defaultChord)
            XCTAssertEqual(action.effectiveChord.modifiers, [.control])
        }
    }

    func testDragScrollRequiresV4AndRejectsInvalidProfiles() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(configURL: directory.appendingPathComponent("source.json"))
            let valid = GestureProfile(name: "Drag scroll", input: .mouseCombination(.init(action: .dragScroll)),
                                       action: .none, targetPolicy: .windowUnderPointer)
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [valid]), 4)
            let file = GestureConfigFile(version: 4, gestures: [valid])
            XCTAssertNoThrow(try store.validateBackupGestureFile(file))
            let encoded = try JSONEncoder().encode(file)
            XCTAssertEqual(try JSONDecoder().decode(GestureConfigFile.self, from: encoded), file)
            var invalidProfiles: [GestureProfile] = []
            var profile = valid
            profile.targetPolicy = .frontmostWindow
            invalidProfiles.append(profile)
            profile = valid
            profile.action = .media(.playPause)
            invalidProfiles.append(profile)
            profile = valid
            profile.input = .mouseCombination(.init(edge: .top, action: .dragScroll))
            invalidProfiles.append(profile)
            for sensitivity in [Double.nan, .infinity, 0, 4.1] {
                profile = valid
                profile.input = .mouseCombination(.init(action: .dragScroll,
                    dragScroll: .init(sensitivity: sensitivity)))
                invalidProfiles.append(profile)
            }
            for profile in invalidProfiles {
                XCTAssertThrowsError(try store.validateBackupGestureFile(.init(version: 4, gestures: [profile]))) {
                    XCTAssertEqual($0 as? ConfigStoreFailure,
                                   .invalidConfiguration(.invalidMouseCombination(profile.id)))
                }
            }
        }
    }

    func testV4BackupCodecAndMergePreserveSystemOverridesAndDragScroll() throws {
        let fn = ShortcutChord(modifiers: [.function, .control], keyCode: 123)
        var system = GestureProfile(name: "System", pattern: .freePath(PathTemplates.up),
                                    action: .system(.init(command: .spaceLeft, shortcutOverride: fn)))
        system.secondaryAction = .system(.init(command: .applicationWindows))
        let drag = GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll,
            dragScroll: .init(sensitivity: 2.5, reversesDirection: true))), targetPolicy: .windowUnderPointer)
        let file = GestureConfigFile(version: 4, gestures: [system, drag])
        let payload = BackupPayloadV1(gestures: file, settings: nil, restoredFromSnapshotID: nil)
        let metadata = BackupMetadataV1(snapshotID: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .manual, deviceID: UUID(), deviceName: "Test Mac", appVersion: "1", appBuild: "1", scope: .gesturesOnly)
        let plain = try BackupCodec.encodePlaintext(payload: payload, metadata: metadata)
        let encrypted = try BackupCodec.encodeEncrypted(payload: payload, metadata: metadata,
                                                       password: "system and drag backup")
        let decodedFiles = [
            try BackupCodec.decode(plain.data).payload.gestures,
            try BackupCodec.decode(encrypted.data, derivedKey: XCTUnwrap(encrypted.derivedKey)).payload.gestures,
        ]
        for decoded in decodedFiles {
            XCTAssertEqual(decoded, file)
            let plan: BackupMergePlan<String> = try BackupMergePlanner.plan(
                local: .empty, backup: decoded, localSettings: [:], backupSettings: [:])
            XCTAssertEqual(try plan.resolve().gestureFile, file)
        }
        for version in [2, 3] {
            var mislabeled = payload
            mislabeled.gestures.version = version
            XCTAssertThrowsError(try BackupCodec.encodePlaintext(payload: mislabeled, metadata: metadata)) {
                XCTAssertEqual($0 as? BackupCodecError, .unsupportedGestureConfigVersion(version))
            }
            XCTAssertThrowsError(try BackupMergePlanner.plan(local: .empty, backup: mislabeled.gestures,
                localSettings: [String: String](), backupSettings: [:])) {
                XCTAssertEqual($0 as? BackupMergePlannerError,
                               .unsupportedConfigVersion(side: .backup, version: version))
            }
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrokeMouseFnCompatibility-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private struct V018GestureConfigFile: Decodable {
    let version: Int
    let gestures: [V018GestureProfile]
}

private struct V018GestureProfile: Decodable {
    let action: V018GestureAction
}

private enum V018GestureAction: Decodable {
    case shortcut(keyCode: UInt16, modifiers: UInt, display: String)
}

private struct V031GestureConfigFile: Decodable {
    let gestures: [V031GestureProfile]
}

private struct V031GestureProfile: Decodable {
    let action: V031GestureAction
}

private enum V031GestureAction: Decodable {
    case shortcut(
        keyCode: UInt16,
        modifiers: UInt,
        display: String,
        orderedChord: ShortcutChord?
    )
}
