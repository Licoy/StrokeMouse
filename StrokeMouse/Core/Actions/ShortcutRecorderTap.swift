import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum ShortcutRecordingInput: Equatable {
    case flagsChanged(keyCode: UInt16, flags: CGEventFlags)
    case keyDown(keyCode: UInt16, isRepeat: Bool, flags: CGEventFlags)
    case keyUp(keyCode: UInt16)

    init?(type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            self = .keyDown(keyCode: keyCode, isRepeat: isRepeat, flags: event.flags)
        case .keyUp:
            self = .keyUp(keyCode: keyCode)
        case .flagsChanged:
            // A swallowed head-tap event may not reach the session key-state table.
            // Its own flags already describe the modifier state for this transition.
            self = .flagsChanged(keyCode: keyCode, flags: event.flags)
        default:
            return nil
        }
    }
}

enum ShortcutRecordingResult: Equatable {
    case listening
    case captured(ShortcutChord)
    case cancelled
    case unsupportedModifier
}

struct ShortcutRecordingState {
    private var modifierOrder: [ShortcutModifier] = []
    private var pressedModifiers: [UInt16: ShortcutModifier] = [:]
    private var primaryKeyCode: UInt16?
    private var pressedKeyCodes: Set<UInt16> = []
    private var unsupportedModifierKeys: Set<UInt16> = []
    private var hasStartedRelease = false
    private var hasUnsupportedModifier = false
    private var isInvalidAttempt = false
    private var isCancelling = false
    /// Snapshot taken on primary keyDown so a lost keyUp still yields a chord
    /// once every participating key has been released (safe to stop the tap).
    private var committedChord: ShortcutChord?

    mutating func handle(_ input: ShortcutRecordingInput) -> ShortcutRecordingResult {
        switch input {
        case .flagsChanged(let keyCode, let flags):
            return handleFlagsChanged(keyCode: keyCode, flags: flags)

        case .keyDown(let keyCode, let isRepeat, let flags):
            return handleKeyDown(keyCode: keyCode, isRepeat: isRepeat, flags: flags)

        case .keyUp(let keyCode):
            guard pressedKeyCodes.remove(keyCode) != nil else { return .listening }
            hasStartedRelease = true
            return finishIfReleased()
        }
    }

    private mutating func handleFlagsChanged(
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> ShortcutRecordingResult {
        if Int(keyCode) == kVK_Function {
            let isDown = !unsupportedModifierKeys.contains(keyCode)
            guard !isDown || Self.flagsIndicate(.maskSecondaryFn, in: flags) else {
                return .listening
            }
            return handleUnsupportedModifier(keyCode: keyCode, isDown: isDown)
        }

        // Track each physical key so releasing one side remains distinguishable
        // while the other side still keeps the aggregate event flag set.
        if pressedModifiers[keyCode] != nil {
            return handleSupportedModifier(keyCode: keyCode, isDown: false)
        }

        if let modifier = resolveLogicalModifier(keyCode: keyCode, flags: flags) {
            return handleSupportedModifier(keyCode: keyCode, modifier: modifier, isDown: true)
        }

        // True Caps Lock (not remapped to a standard modifier).
        if Int(keyCode) == kVK_CapsLock {
            hasUnsupportedModifier = true
            return finishIfReleased()
        }

        return .listening
    }

    /// Maps a physical flags-changed key to the logical modifier it currently produces.
    /// Supports System Settings remaps (e.g. Caps Lock → Control) where the keyCode
    /// stays physical while `flags` carry the effective modifier.
    private func resolveLogicalModifier(
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> ShortcutModifier? {
        if let defaultModifier = Self.modifier(for: keyCode) {
            if Self.flagsIndicate(Self.eventFlag(for: defaultModifier), in: flags) {
                return defaultModifier
            }
            // Physical modifier key remapped to a different standard modifier.
            return unexplainedStandardModifier(in: flags)
        }

        if Int(keyCode) == kVK_CapsLock {
            // Caps Lock remapped to Control/Option/Command/Shift.
            return unexplainedStandardModifier(in: flags)
        }

        return nil
    }

    /// Standard modifier bits in `flags` that are not already accounted for by
    /// other currently pressed physical modifier keys.
    private func unexplainedStandardModifier(in flags: CGEventFlags) -> ShortcutModifier? {
        var explained: CGEventFlags = []
        for modifier in pressedModifiers.values {
            explained.insert(Self.eventFlag(for: modifier))
        }

        // Stable priority when multiple unexplained bits appear (unusual).
        let candidates: [ShortcutModifier] = [.control, .option, .shift, .command]
        var found: [ShortcutModifier] = []
        for modifier in candidates {
            let flag = Self.eventFlag(for: modifier)
            guard Self.flagsIndicate(flag, in: flags) else { continue }
            guard !Self.flagsIndicate(flag, in: explained) else { continue }
            found.append(modifier)
        }
        return found.first
    }

    private mutating func handleUnsupportedModifier(
        keyCode: UInt16,
        isDown: Bool
    ) -> ShortcutRecordingResult {
        hasUnsupportedModifier = true
        if isDown {
            unsupportedModifierKeys.insert(keyCode)
            return .listening
        }
        unsupportedModifierKeys.remove(keyCode)
        return finishIfReleased()
    }

    private mutating func handleSupportedModifier(
        keyCode: UInt16,
        modifier: ShortcutModifier? = nil,
        isDown: Bool
    ) -> ShortcutRecordingResult {
        if isDown {
            guard let modifier else { return .listening }
            if primaryKeyCode != nil || hasStartedRelease {
                isInvalidAttempt = true
                isCancelling = false
                committedChord = nil
            }
            if !modifierOrder.contains(modifier) {
                modifierOrder.append(modifier)
            }
            pressedModifiers[keyCode] = modifier
            return .listening
        }
        guard pressedModifiers.removeValue(forKey: keyCode) != nil else { return .listening }
        hasStartedRelease = true
        return finishIfReleased()
    }

    private mutating func handleKeyDown(
        keyCode: UInt16,
        isRepeat: Bool,
        flags: CGEventFlags
    ) -> ShortcutRecordingResult {
        guard !isRepeat else { return .listening }
        // Modifier / toggle keys only produce meaningful state via flagsChanged.
        if Self.isModifierOrToggleKeyCode(keyCode) {
            return .listening
        }

        // If flagsChanged for Control was missed, the primary keyDown still carries
        // device-independent (and sometimes device-dependent) modifier bits.
        mergeModifiers(from: flags)

        if Int(keyCode) == kVK_Escape, modifierOrder.isEmpty, primaryKeyCode == nil {
            isCancelling = true
        }
        if hasStartedRelease || (primaryKeyCode != nil && primaryKeyCode != keyCode) {
            isInvalidAttempt = true
            isCancelling = false
            committedChord = nil
        }
        if primaryKeyCode == nil { primaryKeyCode = keyCode }
        pressedKeyCodes.insert(keyCode)
        commitChordIfPossible()
        return .listening
    }

    private mutating func mergeModifiers(from flags: CGEventFlags) {
        let order: [ShortcutModifier] = [.control, .option, .shift, .command]
        for modifier in order {
            guard Self.flagsIndicate(Self.eventFlag(for: modifier), in: flags) else { continue }
            if !modifierOrder.contains(modifier) {
                modifierOrder.append(modifier)
            }
        }
    }

    /// Freeze the chord when the primary key goes down so system-reserved combos
    /// (⌃← / Spaces, ⌃↑ / Mission Control, …) still record if later edges are noisy.
    private mutating func commitChordIfPossible() {
        guard !isCancelling, !isInvalidAttempt, !hasUnsupportedModifier else {
            committedChord = nil
            return
        }
        guard let primaryKeyCode else { return }
        committedChord = ShortcutChord(modifiers: modifierOrder, keyCode: primaryKeyCode)
    }

    private mutating func finishIfReleased() -> ShortcutRecordingResult {
        guard pressedModifiers.isEmpty, pressedKeyCodes.isEmpty,
              unsupportedModifierKeys.isEmpty
        else {
            return .listening
        }
        if hasUnsupportedModifier {
            self = ShortcutRecordingState()
            return .unsupportedModifier
        }
        if isCancelling {
            self = ShortcutRecordingState()
            return .cancelled
        }
        if isInvalidAttempt {
            self = ShortcutRecordingState()
            return .listening
        }
        if let committedChord {
            self = ShortcutRecordingState()
            return .captured(committedChord)
        }
        // Modifier-only chords never take the primary-key commit path.
        guard !modifierOrder.isEmpty || primaryKeyCode != nil else { return .listening }
        let chord = ShortcutChord(modifiers: modifierOrder, keyCode: primaryKeyCode)
        self = ShortcutRecordingState()
        return .captured(chord)
    }

    private static func modifier(for keyCode: UInt16) -> ShortcutModifier? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Option, kVK_RightOption: return .option
        case kVK_Control, kVK_RightControl: return .control
        case kVK_Shift, kVK_RightShift: return .shift
        default: return nil
        }
    }

    private static func isModifierOrToggleKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Shift, kVK_RightShift,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }

    private static func eventFlag(for modifier: ShortcutModifier) -> CGEventFlags {
        switch modifier {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }

    /// Device-independent mask, or the corresponding left/right device-dependent bits
    /// from `events.h` when a source only sets those.
    private static func flagsIndicate(_ flag: CGEventFlags, in flags: CGEventFlags) -> Bool {
        if flags.contains(flag) { return true }
        let deviceBits: UInt64
        switch flag {
        case .maskControl:
            // NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK
            deviceBits = 0x0000_0001 | 0x0000_2000
        case .maskShift:
            // NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK
            deviceBits = 0x0000_0002 | 0x0000_0004
        case .maskCommand:
            // NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK
            deviceBits = 0x0000_0008 | 0x0000_0010
        case .maskAlternate:
            // NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK
            deviceBits = 0x0000_0020 | 0x0000_0040
        default:
            return false
        }
        return flags.rawValue & deviceBits != 0
    }
}

/// Global keyboard tap that swallows key events while recording a shortcut,
/// so system hotkeys (e.g. lock screen) do not fire mid-recording.
final class ShortcutRecorderTap: @unchecked Sendable {
    static let shared = ShortcutRecorderTap()

    /// Called on main queue after every participating key has been released.
    var onCapture: ((ShortcutChord, String) -> Void)?
    var onCancel: (() -> Void)?
    var onUnsupportedModifier: (() -> Void)?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var recordingState = ShortcutRecordingState()
    private let queue = DispatchQueue(label: "com.strokemouse.app.shortcutRecorder")

    private init() {}

    var isActive: Bool { queue.sync { isRunning } }

    @discardableResult
    func start() -> Bool {
        queue.sync {
            guard !isRunning else { return true }
            guard AXIsProcessTrusted() else { return false }
            recordingState = ShortcutRecordingState()

            let mask =
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)

            let callback: CGEventTapCallBack = { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<ShortcutRecorderTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            }

            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            // HID-level tap so system-reserved combos (⌃←/→ Spaces, ⌃↑ Mission Control)
            // still reach the recorder and can be swallowed before Dock handles them.
            guard let eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: userInfo
            ) else {
                return false
            }

            port = eventTap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            isRunning = true
            return true
        }
    }

    func stop() {
        queue.sync {
            recordingState = ShortcutRecordingState()
            guard isRunning else { return }
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            runLoopSource = nil
            port = nil
            isRunning = false
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return nil
        }

        guard let input = ShortcutRecordingInput(type: type, event: event) else { return nil }

        let result = recordingState.handle(input)
        switch result {
        case .listening:
            break
        case .captured(let chord):
            let display = KeyCodeNames.shortcutDisplay(chord: chord)
            DispatchQueue.main.async { [weak self] in
                self?.onCapture?(chord, display)
            }
        case .cancelled:
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
        case .unsupportedModifier:
            DispatchQueue.main.async { [weak self] in
                self?.onUnsupportedModifier?()
            }
        }

        // Always swallow while recording so hotkeys never reach the system.
        return nil
    }
}
