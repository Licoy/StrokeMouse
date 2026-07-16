import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Active CGEventTap wrapper that reserves configured trigger-button gestures.
final class MouseEventTap: @unchecked Sendable {
    struct Sample {
        let location: CGPoint
        let timestamp: TimeInterval
    }

    enum EventKind {
        case buttonDown(MouseTriggerButton, CGPoint)
        case buttonUp(MouseTriggerButton, CGPoint)
        case drag(CGPoint)
    }

    /// Buttons that arm gesture capture. Unwatched mouse input always passes through.
    var watchedButtons: Set<MouseTriggerButton> = [.right]

    static let tapOptions: CGEventTapOptions = .defaultTap
    private static let replayEventMarker: Int64 = 0x5354524F4B454D4F

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var capturedButtons: Set<MouseTriggerButton> = []
    private let queue = DispatchQueue(label: "com.strokemouse.app.eventtap")

    var onEvent: ((EventKind) -> Void)?

    var isActive: Bool { isRunning }

    func start() -> Bool {
        queue.sync {
            guard !isRunning else { return true }
            guard AXIsProcessTrusted() else { return false }

            let mask =
                (1 << CGEventType.leftMouseDown.rawValue) |
                (1 << CGEventType.leftMouseUp.rawValue) |
                (1 << CGEventType.rightMouseDown.rawValue) |
                (1 << CGEventType.rightMouseUp.rawValue) |
                (1 << CGEventType.otherMouseDown.rawValue) |
                (1 << CGEventType.otherMouseUp.rawValue) |
                (1 << CGEventType.leftMouseDragged.rawValue) |
                (1 << CGEventType.rightMouseDragged.rawValue) |
                (1 << CGEventType.otherMouseDragged.rawValue) |
                (1 << CGEventType.mouseMoved.rawValue)

            let callback: CGEventTapCallBack = { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MouseEventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            }

            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: Self.tapOptions,
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
            capturedButtons = []
        }
    }

    /// Re-inject a normal click after a captured trigger press produced no gesture.
    @discardableResult
    func replayClick(button: MouseTriggerButton, location: CGPoint) -> Bool {
        guard let events = Self.makeReplayEvents(button: button, location: location) else {
            return false
        }
        DispatchQueue.main.async {
            events.down.post(tap: .cghidEventTap)
            events.up.post(tap: .cghidEventTap)
        }
        return true
    }

    static func makeReplayEvents(
        button: MouseTriggerButton,
        location: CGPoint
    ) -> (down: CGEvent, up: CGEvent)? {
        let (downType, upType, cgButton, buttonNumber) = eventTypes(for: button)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ) else {
            return nil
        }

        if button != .right {
            down.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            up.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        down.setIntegerValueField(.eventSourceUserData, value: replayEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: replayEventMarker)
        return (down, up)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if system disables the tap under pressure.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Replayed short clicks must reach the target without re-arming capture.
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let button = resolveButton(type: type, event: event)

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let button, watchedButtons.contains(button) {
                capturedButtons.insert(button)
                onEvent?(.buttonDown(button, location))
                return nil
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if let button, capturedButtons.remove(button) != nil {
                onEvent?(.buttonUp(button, location))
                return nil
            }
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if let button, capturedButtons.contains(button) {
                onEvent?(.drag(location))
            }
        case .mouseMoved:
            if !capturedButtons.isEmpty {
                onEvent?(.drag(location))
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func resolveButton(type: CGEventType, event: CGEvent) -> MouseTriggerButton? {
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            let number = event.getIntegerValueField(.mouseEventButtonNumber)
            switch number {
            case 2: return .middle
            case 3: return .sideBack
            case 4: return .sideForward
            default: return nil
            }
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            // Left button is not a gesture trigger in this product.
            return nil
        default:
            return nil
        }
    }

    private static func eventTypes(
        for button: MouseTriggerButton
    ) -> (CGEventType, CGEventType, CGMouseButton, Int64) {
        switch button {
        case .right:
            return (.rightMouseDown, .rightMouseUp, .right, 1)
        case .middle:
            return (.otherMouseDown, .otherMouseUp, .center, 2)
        case .sideBack:
            return (.otherMouseDown, .otherMouseUp, .center, 3)
        case .sideForward:
            return (.otherMouseDown, .otherMouseUp, .center, 4)
        }
    }
}
