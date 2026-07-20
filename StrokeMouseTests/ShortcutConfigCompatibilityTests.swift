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
}
