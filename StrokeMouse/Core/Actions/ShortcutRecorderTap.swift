import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Global keyboard tap that swallows key events while recording a shortcut,
/// so system hotkeys (e.g. lock screen) do not fire mid-recording.
final class ShortcutRecorderTap: @unchecked Sendable {
    static let shared = ShortcutRecorderTap()

    /// Called on main queue when a non-modifier key combo is captured.
    var onCapture: ((UInt16, UInt, String) -> Void)?
    var onCancel: (() -> Void)?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.strokemouse.app.shortcutRecorder")

    private init() {}

    var isActive: Bool { queue.sync { isRunning } }

    @discardableResult
    func start() -> Bool {
        queue.sync {
            guard !isRunning else { return true }
            guard AXIsProcessTrusted() else { return false }

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

        // Always swallow while recording so hotkeys never reach the system.
        guard type == .keyDown else {
            return nil
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if KeyCodeNames.isModifierKeyCode(keyCode) {
            return nil
        }

        // Escape cancels recording without assigning.
        if Int(keyCode) == kVK_Escape {
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return nil
        }

        var mods: NSEvent.ModifierFlags = []
        if event.flags.contains(.maskCommand) { mods.insert(.command) }
        if event.flags.contains(.maskShift) { mods.insert(.shift) }
        if event.flags.contains(.maskAlternate) { mods.insert(.option) }
        if event.flags.contains(.maskControl) { mods.insert(.control) }

        let display = KeyCodeNames.shortcutDisplay(keyCode: keyCode, modifiers: mods)

        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(keyCode, UInt(mods.rawValue), display)
        }

        return nil
    }
}
