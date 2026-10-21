import Carbon.HIToolbox
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
