import Carbon.HIToolbox
import XCTest
@testable import StrokeMouse

final class ShortcutRecordingStateTests: XCTestCase {
    func testModifierOnlyChordCompletesAfterEveryKeyIsReleased() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .captured(ShortcutChord(modifiers: [.command, .option], keyCode: nil))
        )
    }

    func testControlThenOptionModifierOnlyChordIsCaptured() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Control), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Control), isDown: false)),
            .captured(ShortcutChord(modifiers: [.control, .option], keyCode: nil))
        )
    }

    func testChordWithPrimaryKeyPreservesModifierPressOrder() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .captured(ShortcutChord(
                modifiers: [.command, .option],
                keyCode: UInt16(kVK_ANSI_Q)
            ))
        )
    }

    func testBareEscapeCancelsRecording() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_Escape), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyUp(keyCode: UInt16(kVK_Escape))),
            .cancelled
        )
    }

    func testModifiedEscapeIsCapturedAsThePrimaryKey() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_Escape), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_Escape))), .listening)
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .captured(ShortcutChord(
                modifiers: [.command],
                keyCode: UInt16(kVK_Escape)
            ))
        )
    }

    func testNewPrimaryKeyAfterReleaseInvalidatesTheAttempt() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_W), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_W))), .listening)
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .listening
        )

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: false)),
            .captured(ShortcutChord(modifiers: [.option], keyCode: nil))
        )
    }

    func testSecondPrimaryKeyBeforeReleaseInvalidatesTheAttempt() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_W), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_W))), .listening)
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .listening
        )

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Option), isDown: false)),
            .captured(ShortcutChord(modifiers: [.option], keyCode: nil))
        )
    }

    func testUnsupportedModifiersReportAfterRelease() {
        for keyCode in [kVK_Function, kVK_CapsLock] {
            var state = ShortcutRecordingState()

            XCTAssertEqual(
                state.handle(.modifierChanged(keyCode: UInt16(keyCode), isDown: true)),
                .listening
            )
            XCTAssertEqual(
                state.handle(.modifierChanged(keyCode: UInt16(keyCode), isDown: false)),
                .unsupportedModifier
            )
        }
    }

    func testEveryRightModifierNormalizesToItsLogicalModifier() {
        let cases: [(Int, ShortcutModifier)] = [
            (kVK_RightCommand, .command),
            (kVK_RightOption, .option),
            (kVK_RightControl, .control),
            (kVK_RightShift, .shift),
        ]

        for (keyCode, modifier) in cases {
            var state = ShortcutRecordingState()
            XCTAssertEqual(
                state.handle(.modifierChanged(keyCode: UInt16(keyCode), isDown: true)),
                .listening
            )
            XCTAssertEqual(
                state.handle(.modifierChanged(keyCode: UInt16(keyCode), isDown: false)),
                .captured(ShortcutChord(modifiers: [modifier], keyCode: nil))
            )
        }
    }

    func testAutoRepeatDoesNotCreateAnotherPrimaryKey() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: true)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .captured(ShortcutChord(
                modifiers: [.command],
                keyCode: UInt16(kVK_ANSI_Q)
            ))
        )
    }

    func testPrimaryKeyMustBePressedAfterModifiers() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: true)),
            .listening
        )
        XCTAssertEqual(
            state.handle(.modifierChanged(keyCode: UInt16(kVK_Command), isDown: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
    }
}
