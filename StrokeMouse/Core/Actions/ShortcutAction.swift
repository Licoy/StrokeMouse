import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

extension ShortcutModifier {
    var appKitFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    var quartzFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    var standardKeyCode: UInt16 {
        switch self {
        case .command: return UInt16(kVK_Command)
        case .option: return UInt16(kVK_Option)
        case .control: return UInt16(kVK_Control)
        case .shift: return UInt16(kVK_Shift)
        }
    }
}

extension ShortcutChord {
    var legacyKeyCode: UInt16 {
        if let keyCode { return keyCode }
        guard let finalModifier = modifiers.last else {
            preconditionFailure("A shortcut chord must contain a key")
        }
        return finalModifier.standardKeyCode
    }

    var legacyModifiers: UInt {
        let projectedModifiers = keyCode == nil ? modifiers.dropLast() : modifiers[...]
        let flags = projectedModifiers.reduce(into: NSEvent.ModifierFlags()) { result, modifier in
            result.insert(modifier.appKitFlag)
        }
        return UInt(flags.rawValue)
    }
}

extension GestureAction {
    static func shortcut(chord: ShortcutChord) -> GestureAction {
        .shortcut(
            keyCode: chord.legacyKeyCode,
            modifiers: chord.legacyModifiers,
            display: KeyCodeNames.shortcutDisplay(chord: chord),
            orderedChord: chord
        )
    }
}

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

        init(_ modifier: ShortcutModifier) {
            appKitFlag = modifier.appKitFlag
            quartzFlag = modifier.quartzFlag
            keyCode = modifier.standardKeyCode
        }
    }

    private static let modifierKeys = [
        ModifierKey(.control),
        ModifierKey(.option),
        ModifierKey(.shift),
        ModifierKey(.command),
    ]

    static func post(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord? = nil
    ) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ShortcutActionError.eventSourceUnavailable
        }

        let plan = makeEventPlan(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord
        )
        let events = try plan.map { descriptor in
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

    static func makeEventPlan(
        keyCode: UInt16,
        modifiers rawModifiers: UInt,
        orderedChord: ShortcutChord? = nil
    ) -> [ShortcutEventDescriptor] {
        if let orderedChord {
            return makeOrderedEventPlan(orderedChord)
        }

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

    private static func makeOrderedEventPlan(
        _ chord: ShortcutChord
    ) -> [ShortcutEventDescriptor] {
        let modifierKeys = chord.modifiers.map(ModifierKey.init)
        var activeFlags: CGEventFlags = []
        var plan: [ShortcutEventDescriptor] = []

        for modifier in modifierKeys {
            activeFlags.insert(modifier.quartzFlag)
            plan.append(ShortcutEventDescriptor(
                keyCode: modifier.keyCode,
                isKeyDown: true,
                flags: activeFlags
            ))
        }

        if let keyCode = chord.keyCode {
            let targetFlags = activeFlags.union(intrinsicFlags(for: keyCode))
            plan.append(ShortcutEventDescriptor(keyCode: keyCode, isKeyDown: true, flags: targetFlags))
            plan.append(ShortcutEventDescriptor(keyCode: keyCode, isKeyDown: false, flags: targetFlags))
        }

        for modifier in modifierKeys.reversed() {
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
