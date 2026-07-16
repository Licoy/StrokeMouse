import AppKit
import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import StrokeMouse

final class ShortcutActionTests: XCTestCase {
    func testLegacyControlArrowBuildsCompleteModifierSequence() {
        let plan = ShortcutAction.makeEventPlan(
            keyCode: UInt16(kVK_UpArrow),
            modifiers: UInt(NSEvent.ModifierFlags.control.rawValue)
        )

        XCTAssertEqual(plan, [
            event(kVK_Control, isKeyDown: true, flags: [.maskControl]),
            event(kVK_UpArrow, isKeyDown: true, flags: [.maskControl, .maskSecondaryFn]),
            event(kVK_UpArrow, isKeyDown: false, flags: [.maskControl, .maskSecondaryFn]),
            event(kVK_Control, isKeyDown: false, flags: []),
        ])
    }

    func testMultipleModifiersPressInOrderAndReleaseInReverse() {
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let plan = ShortcutAction.makeEventPlan(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: UInt(modifiers.rawValue)
        )

        XCTAssertEqual(plan, [
            event(kVK_Control, isKeyDown: true, flags: [.maskControl]),
            event(kVK_Option, isKeyDown: true, flags: [.maskControl, .maskAlternate]),
            event(kVK_Shift, isKeyDown: true, flags: [.maskControl, .maskAlternate, .maskShift]),
            event(kVK_Command, isKeyDown: true, flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand]),
            event(kVK_ANSI_A, isKeyDown: true, flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand]),
            event(kVK_ANSI_A, isKeyDown: false, flags: [.maskControl, .maskAlternate, .maskShift, .maskCommand]),
            event(kVK_Command, isKeyDown: false, flags: [.maskControl, .maskAlternate, .maskShift]),
            event(kVK_Shift, isKeyDown: false, flags: [.maskControl, .maskAlternate]),
            event(kVK_Option, isKeyDown: false, flags: [.maskControl]),
            event(kVK_Control, isKeyDown: false, flags: []),
        ])
    }

    func testFunctionAndNavigationKeysReceiveOnlySecondaryFunctionSemantics() {
        let keyCodes = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
            kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
            kVK_Help, kVK_ForwardDelete, kVK_Home, kVK_End,
            kVK_PageUp, kVK_PageDown,
            kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow,
        ]

        for keyCode in keyCodes {
            let plan = ShortcutAction.makeEventPlan(keyCode: UInt16(keyCode), modifiers: 0)

            XCTAssertEqual(
                plan,
                [
                    event(keyCode, isKeyDown: true, flags: [.maskSecondaryFn]),
                    event(keyCode, isKeyDown: false, flags: [.maskSecondaryFn]),
                ],
                "Unexpected semantics for key code \(keyCode)"
            )
        }
    }

    func testKeypadKeysReceiveOnlyNumericPadSemantics() {
        let keyCodes = [
            kVK_ANSI_KeypadClear, kVK_ANSI_KeypadEquals,
            kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadMultiply,
            kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadPlus,
            kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadDecimal,
            kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2,
            kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
            kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8,
            kVK_ANSI_Keypad9, kVK_JIS_KeypadComma,
        ]

        for keyCode in keyCodes {
            let plan = ShortcutAction.makeEventPlan(keyCode: UInt16(keyCode), modifiers: 0)

            XCTAssertEqual(
                plan,
                [
                    event(keyCode, isKeyDown: true, flags: [.maskNumericPad]),
                    event(keyCode, isKeyDown: false, flags: [.maskNumericPad]),
                ],
                "Unexpected semantics for key code \(keyCode)"
            )
        }
    }

    func testOrdinaryKeyDoesNotReceiveIntrinsicFlags() {
        XCTAssertEqual(
            ShortcutAction.makeEventPlan(keyCode: UInt16(kVK_ANSI_A), modifiers: 0),
            [
                event(kVK_ANSI_A, isKeyDown: true, flags: []),
                event(kVK_ANSI_A, isKeyDown: false, flags: []),
            ]
        )
    }

    func testAllLegacyControlArrowConfigurationsAreNormalizedAtExecution() {
        for keyCode in [kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow] {
            let plan = ShortcutAction.makeEventPlan(
                keyCode: UInt16(keyCode),
                modifiers: UInt(NSEvent.ModifierFlags.control.rawValue)
            )

            XCTAssertEqual(plan.count, 4)
            XCTAssertEqual(plan[1].flags, [.maskControl, .maskSecondaryFn])
            XCTAssertFalse(plan[1].flags.contains(.maskNumericPad))
        }
    }

    private func event(
        _ keyCode: Int,
        isKeyDown: Bool,
        flags: CGEventFlags
    ) -> ShortcutEventDescriptor {
        ShortcutEventDescriptor(
            keyCode: UInt16(keyCode),
            isKeyDown: isKeyDown,
            flags: flags
        )
    }
}
