import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct ShortcutEventDescriptor: Equatable {
    let keyCode: UInt16
    let isKeyDown: Bool
    let flags: CGEventFlags
}

enum ShortcutActionError: LocalizedError {
    case eventSourceUnavailable
    case eventCreationFailed(keyCode: UInt16)

    var errorDescription: String? {
        L10n.string("action.shortcutExecutionFailed")
    }
}

enum ShortcutAction {
    private struct ModifierKey {
        let appKitFlag: NSEvent.ModifierFlags
        let quartzFlag: CGEventFlags
        let keyCode: UInt16
    }

    private static let modifierKeys = [
        ModifierKey(
            appKitFlag: .control,
            quartzFlag: .maskControl,
            keyCode: UInt16(kVK_Control)
        ),
        ModifierKey(
            appKitFlag: .option,
            quartzFlag: .maskAlternate,
            keyCode: UInt16(kVK_Option)
        ),
        ModifierKey(
            appKitFlag: .shift,
            quartzFlag: .maskShift,
            keyCode: UInt16(kVK_Shift)
        ),
        ModifierKey(
            appKitFlag: .command,
            quartzFlag: .maskCommand,
            keyCode: UInt16(kVK_Command)
        ),
    ]

    static func post(keyCode: UInt16, modifiers: UInt) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ShortcutActionError.eventSourceUnavailable
        }

        let events = try makeEventPlan(keyCode: keyCode, modifiers: modifiers).map { descriptor in
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: descriptor.keyCode,
                keyDown: descriptor.isKeyDown
            ) else {
                throw ShortcutActionError.eventCreationFailed(keyCode: descriptor.keyCode)
            }
            event.flags = descriptor.flags
            return event
        }

        for event in events {
            event.post(tap: .cghidEventTap)
        }
    }

    static func makeEventPlan(keyCode: UInt16, modifiers rawModifiers: UInt) -> [ShortcutEventDescriptor] {
        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
        var activeFlags: CGEventFlags = []
        var plan: [ShortcutEventDescriptor] = []

        for modifier in modifierKeys where modifiers.contains(modifier.appKitFlag) {
            activeFlags.insert(modifier.quartzFlag)
            plan.append(ShortcutEventDescriptor(
                keyCode: modifier.keyCode,
                isKeyDown: true,
                flags: activeFlags
            ))
        }

        let targetFlags = activeFlags.union(intrinsicFlags(for: keyCode))
        plan.append(ShortcutEventDescriptor(keyCode: keyCode, isKeyDown: true, flags: targetFlags))
        plan.append(ShortcutEventDescriptor(keyCode: keyCode, isKeyDown: false, flags: targetFlags))

        for modifier in modifierKeys.reversed() where modifiers.contains(modifier.appKitFlag) {
            activeFlags.remove(modifier.quartzFlag)
            plan.append(ShortcutEventDescriptor(
                keyCode: modifier.keyCode,
                isKeyDown: false,
                flags: activeFlags
            ))
        }

        return plan
    }

    private static func intrinsicFlags(for keyCode: UInt16) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
             kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
             kVK_Help, kVK_ForwardDelete, kVK_Home, kVK_End,
             kVK_PageUp, kVK_PageDown,
             kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow:
            return .maskSecondaryFn

        case kVK_ANSI_KeypadClear, kVK_ANSI_KeypadEquals,
             kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadMultiply,
             kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadPlus,
             kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadDecimal,
             kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2,
             kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
             kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8,
             kVK_ANSI_Keypad9, kVK_JIS_KeypadComma:
            return .maskNumericPad

        default:
            return []
        }
    }
}
