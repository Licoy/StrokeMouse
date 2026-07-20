import Carbon.HIToolbox
import XCTest
@testable import StrokeMouse

final class ShortcutChordTests: XCTestCase {
    func testDisplayPreservesModifierRecordingOrder() {
        let commandThenOption = ShortcutChord(
            modifiers: [.command, .option],
            keyCode: UInt16(kVK_ANSI_Q)
        )
        let optionThenCommand = ShortcutChord(
            modifiers: [.option, .command],
            keyCode: UInt16(kVK_ANSI_Q)
        )

        XCTAssertEqual(KeyCodeNames.shortcutDisplay(chord: commandThenOption), "⌘⌥Q")
        XCTAssertEqual(KeyCodeNames.shortcutDisplay(chord: optionThenCommand), "⌥⌘Q")
        XCTAssertNotEqual(commandThenOption, optionThenCommand)
        XCTAssertEqual(
            KeyCodeNames.shortcutDisplay(
                chord: ShortcutChord(modifiers: [.command, .option], keyCode: nil)
            ),
            "⌘⌥"
        )
    }

    func testOrderedShortcutActionRoundTripsThroughCodable() throws {
        let chords = [
            ShortcutChord(
                modifiers: [.command, .option],
                keyCode: UInt16(kVK_ANSI_Q)
            ),
            ShortcutChord(
                modifiers: [.option, .command],
                keyCode: UInt16(kVK_ANSI_Q)
            ),
        ]

        for chord in chords {
            let action = GestureAction.shortcut(chord: chord)
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(GestureAction.self, from: data)

            XCTAssertEqual(decoded, action)
        }
    }

    func testLegacyShortcutWithoutOrderedChordStillDecodes() throws {
        let data = Data(#"{"shortcut":{"keyCode":12,"modifiers":1572864,"display":"⌥⌘Q"}}"#.utf8)

        let decoded = try JSONDecoder().decode(GestureAction.self, from: data)

        guard case .shortcut(let keyCode, let modifiers, let display, let orderedChord) = decoded else {
            return XCTFail("Expected shortcut action")
        }
        XCTAssertEqual(keyCode, UInt16(kVK_ANSI_Q))
        XCTAssertEqual(modifiers, 1_572_864)
        XCTAssertEqual(display, "⌥⌘Q")
        XCTAssertNil(orderedChord)
    }

    func testNewShortcutCanBeDecodedByLegacyShape() throws {
        let action = GestureAction.shortcut(
            keyCode: UInt16(kVK_ANSI_Q),
            modifiers: 1_572_864,
            display: "⌘⌥Q",
            orderedChord: ShortcutChord(
                modifiers: [.command, .option],
                keyCode: UInt16(kVK_ANSI_Q)
            )
        )

        let data = try JSONEncoder().encode(action)
        let legacy = try JSONDecoder().decode(LegacyAction.self, from: data)

        XCTAssertEqual(
            legacy,
            .shortcut(keyCode: UInt16(kVK_ANSI_Q), modifiers: 1_572_864, display: "⌘⌥Q")
        )
    }

    func testInvalidOrderedChordsAreRejectedDuringDecoding() {
        let invalidJSON = [
            #"{"modifiers":[],"keyCode":null}"#,
            #"{"modifiers":["command","command"],"keyCode":12}"#,
            #"{"modifiers":["command"],"keyCode":55}"#,
        ]

        for json in invalidJSON {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ShortcutChord.self, from: Data(json.utf8)),
                "Expected invalid chord to be rejected: \(json)"
            )
        }
    }
}

private enum LegacyAction: Codable, Equatable {
    case shortcut(keyCode: UInt16, modifiers: UInt, display: String)
}
