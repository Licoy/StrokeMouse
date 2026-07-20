import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum ShortcutRecordingInput: Equatable {
    case modifierChanged(keyCode: UInt16, isDown: Bool)
    case keyDown(keyCode: UInt16, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
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

    mutating func handle(_ input: ShortcutRecordingInput) -> ShortcutRecordingResult {
        switch input {
        case .modifierChanged(let keyCode, let isDown):
            return handleModifier(keyCode: keyCode, isDown: isDown)

        case .keyDown(let keyCode, let isRepeat):
            return handleKeyDown(keyCode: keyCode, isRepeat: isRepeat)

        case .keyUp(let keyCode):
            guard pressedKeyCodes.remove(keyCode) != nil else { return .listening }
            hasStartedRelease = true
            return finishIfReleased()
        }
    }

    private mutating func handleModifier(
        keyCode: UInt16,
        isDown: Bool
    ) -> ShortcutRecordingResult {
        if Self.isUnsupportedModifier(keyCode) {
            hasUnsupportedModifier = true
            if isDown {
                unsupportedModifierKeys.insert(keyCode)
                return .listening
            }
            unsupportedModifierKeys.remove(keyCode)
            return finishIfReleased()
        }
        guard let modifier = Self.modifier(for: keyCode) else { return .listening }
        if isDown {
            if primaryKeyCode != nil || hasStartedRelease {
                isInvalidAttempt = true
                isCancelling = false
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
        isRepeat: Bool
    ) -> ShortcutRecordingResult {
        guard !isRepeat else { return .listening }
        if Int(keyCode) == kVK_Escape, modifierOrder.isEmpty, primaryKeyCode == nil {
            isCancelling = true
        }
        if hasStartedRelease || (primaryKeyCode != nil && primaryKeyCode != keyCode) {
            isInvalidAttempt = true
            isCancelling = false
        }
        if primaryKeyCode == nil { primaryKeyCode = keyCode }
        pressedKeyCodes.insert(keyCode)
        return .listening
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
        guard !modifierOrder.isEmpty || primaryKeyCode != nil else { return .listening }
        if isInvalidAttempt {
            self = ShortcutRecordingState()
            return .listening
        }
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

    private static func isUnsupportedModifier(_ keyCode: UInt16) -> Bool {
        Int(keyCode) == kVK_Function || Int(keyCode) == kVK_CapsLock
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
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
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

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let input: ShortcutRecordingInput
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            input = .keyDown(keyCode: keyCode, isRepeat: isRepeat)
        case .keyUp:
            input = .keyUp(keyCode: keyCode)
        case .flagsChanged:
            let isDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
            input = .modifierChanged(keyCode: keyCode, isDown: isDown)
        default:
            return nil
        }

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
