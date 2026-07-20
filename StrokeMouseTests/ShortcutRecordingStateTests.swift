import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import StrokeMouse

final class ShortcutRecordingStateTests: XCTestCase {
    func testFlagsChangedInputUsesFlagsCarriedByTheEvent() throws {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_Command),
            keyDown: true
        ))
        event.flags = [.maskCommand]

        XCTAssertEqual(
            ShortcutRecordingInput(type: .flagsChanged, event: event),
            .flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])
        )
    }

    func testCommandLettersUseFlagsChangedEventStateInsteadOfGlobalKeyState() {
        for primaryKeyCode in [kVK_ANSI_Q, kVK_ANSI_W] {
            var state = ShortcutRecordingState()

            XCTAssertEqual(
                state.handle(.flagsChanged(
                    keyCode: UInt16(kVK_Command),
                    flags: [.maskCommand]
                )),
                .listening
            )
            XCTAssertEqual(
                state.handle(.keyDown(keyCode: UInt16(primaryKeyCode), isRepeat: false)),
                .listening
            )
            XCTAssertEqual(
                state.handle(.keyUp(keyCode: UInt16(primaryKeyCode))),
                .listening
            )
            XCTAssertEqual(
                state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
                .captured(ShortcutChord(
                    modifiers: [.command],
                    keyCode: UInt16(primaryKeyCode)
                ))
            )
        }
    }

    func testModifierOnlyChordCompletesAfterEveryKeyIsReleased() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(
                keyCode: UInt16(kVK_Option),
                flags: [.maskCommand, .maskAlternate]
            )),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
            .captured(ShortcutChord(modifiers: [.command, .option], keyCode: nil))
        )
    }

    func testControlThenOptionModifierOnlyChordIsCaptured() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Control), flags: [.maskControl])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(
                keyCode: UInt16(kVK_Option),
                flags: [.maskControl, .maskAlternate]
            )),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [.maskControl])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Control), flags: [])),
            .captured(ShortcutChord(modifiers: [.control, .option], keyCode: nil))
        )
    }

    func testChordWithPrimaryKeyPreservesModifierPressOrder() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(
                keyCode: UInt16(kVK_Option),
                flags: [.maskCommand, .maskAlternate]
            )),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_ANSI_Q), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
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
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.keyDown(keyCode: UInt16(kVK_Escape), isRepeat: false)),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_Escape))), .listening)
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
            .captured(ShortcutChord(
                modifiers: [.command],
                keyCode: UInt16(kVK_Escape)
            ))
        )
    }

    func testNewPrimaryKeyAfterReleaseInvalidatesTheAttempt() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
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
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
            .listening
        )

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [.maskAlternate])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [])),
            .captured(ShortcutChord(modifiers: [.option], keyCode: nil))
        )
    }

    func testSecondPrimaryKeyBeforeReleaseInvalidatesTheAttempt() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
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
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
            .listening
        )

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [.maskAlternate])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Option), flags: [])),
            .captured(ShortcutChord(modifiers: [.option], keyCode: nil))
        )
    }

    func testFunctionModifierReportsUnsupportedAfterRelease() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(
                keyCode: UInt16(kVK_Function),
                flags: [.maskSecondaryFn]
            )),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Function), flags: [])),
            .unsupportedModifier
        )
    }

    func testCapsLockReportsUnsupportedOnEitherToggleState() {
        for flags: CGEventFlags in [[.maskAlphaShift], []] {
            var state = ShortcutRecordingState()

            XCTAssertEqual(
                state.handle(.flagsChanged(
                    keyCode: UInt16(kVK_CapsLock),
                    flags: flags
                )),
                .unsupportedModifier
            )
        }
    }

    func testCapsLockWaitsForOtherParticipatingKeysToRelease() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(
                keyCode: UInt16(kVK_CapsLock),
                flags: [.maskCommand, .maskAlphaShift]
            )),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskAlphaShift])),
            .unsupportedModifier
        )
    }

    func testEveryRightModifierNormalizesToItsLogicalModifier() {
        let cases: [(keyCode: Int, modifier: ShortcutModifier, flag: CGEventFlags)] = [
            (kVK_RightCommand, .command, .maskCommand),
            (kVK_RightOption, .option, .maskAlternate),
            (kVK_RightControl, .control, .maskControl),
            (kVK_RightShift, .shift, .maskShift),
        ]

        for testCase in cases {
            var state = ShortcutRecordingState()
            XCTAssertEqual(
                state.handle(.flagsChanged(
                    keyCode: UInt16(testCase.keyCode),
                    flags: testCase.flag
                )),
                .listening
            )
            XCTAssertEqual(
                state.handle(.flagsChanged(keyCode: UInt16(testCase.keyCode), flags: [])),
                .captured(ShortcutChord(modifiers: [testCase.modifier], keyCode: nil))
            )
        }
    }

    func testBothPhysicalCommandKeysReleaseIndependently() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_RightCommand), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_RightCommand), flags: [])),
            .captured(ShortcutChord(modifiers: [.command], keyCode: nil))
        )
    }

    func testAutoRepeatDoesNotCreateAnotherPrimaryKey() {
        var state = ShortcutRecordingState()

        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
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
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
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
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [.maskCommand])),
            .listening
        )
        XCTAssertEqual(
            state.handle(.flagsChanged(keyCode: UInt16(kVK_Command), flags: [])),
            .listening
        )
        XCTAssertEqual(state.handle(.keyUp(keyCode: UInt16(kVK_ANSI_Q))), .listening)
    }
}
