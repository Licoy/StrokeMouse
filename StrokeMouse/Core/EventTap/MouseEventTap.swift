import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Active CGEventTap wrapper that reserves configured trigger-button gestures.
///
/// Important design constraints (esp. macOS 14):
/// - Use `.defaultTap` only for trigger down/up/drag — **never** put free `mouseMoved`
///   in the mask; a filtering tap on mouseMoved gates system cursor updates on this
///   process and can freeze the pointer until the app quits.
/// - Run the tap on a dedicated CFRunLoop thread so main-thread UI work cannot stall
///   cursor delivery.
/// - Always return the original event for dragged types so the cursor keeps moving
///   after a consumed trigger-down.
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

    static let tapOptions: CGEventTapOptions = .defaultTap
    private static let replayEventMarker: Int64 = 0x5354524F4B454D4F

    /// Trigger-related events only. Free `mouseMoved` and left-button traffic stay
    /// outside the tap so the system updates the cursor without entering this process.
    static var eventsOfInterestMask: CGEventMask {
        let rightDown = CGEventMask(1) << CGEventType.rightMouseDown.rawValue
        let rightUp = CGEventMask(1) << CGEventType.rightMouseUp.rawValue
        let otherDown = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        let otherUp = CGEventMask(1) << CGEventType.otherMouseUp.rawValue
        let rightDrag = CGEventMask(1) << CGEventType.rightMouseDragged.rawValue
        let otherDrag = CGEventMask(1) << CGEventType.otherMouseDragged.rawValue
        return rightDown | rightUp | otherDown | otherUp | rightDrag | otherDrag
    }

    /// Buttons that arm gesture capture. Unwatched mouse input is not in the mask
    /// (left) or is ignored in `handle` (unwatched right/other).
    var watchedButtons: Set<MouseTriggerButton> {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return watchedButtonsStorage
        }
        set {
            stateLock.lock()
            watchedButtonsStorage = newValue
            stateLock.unlock()
        }
    }

    private var watchedButtonsStorage: Set<MouseTriggerButton> = [.right]
    private var capturedButtons: Set<MouseTriggerButton> = []
    private let stateLock = NSLock()

    private let controlQueue = DispatchQueue(label: "com.strokemouse.app.eventtap.control")
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var isRunning = false
    /// Signaled when the tap thread leaves `CFRunLoopRun`.
    private var threadExitSemaphore: DispatchSemaphore?

    var onEvent: ((EventKind) -> Void)?

    var isActive: Bool {
        controlQueue.sync { isRunning }
    }

    func start() -> Bool {
        controlQueue.sync {
            guard !isRunning else { return true }
            guard AXIsProcessTrusted() else { return false }

            waitForThreadExitLocked()

            let ready = DispatchSemaphore(value: 0)
            let exitSem = DispatchSemaphore(value: 0)
            threadExitSemaphore = exitSem
            var installed = false

            let thread = Thread { [weak self] in
                guard let self else {
                    ready.signal()
                    exitSem.signal()
                    return
                }
                installed = self.installTapOnCurrentRunLoop()
                ready.signal()
                if installed {
                    CFRunLoopRun()
                    self.teardownTapOnCurrentRunLoop()
                }
                exitSem.signal()
            }
            thread.name = "com.strokemouse.app.eventtap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()

            ready.wait()
            isRunning = installed
            if !installed {
                waitForThreadExitLocked()
            }
            return installed
        }
    }

    func stop() {
        controlQueue.sync {
            guard isRunning || runLoop != nil || thread != nil else { return }

            // Disable first so WindowServer stops waiting on this filter.
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            if let runLoop {
                CFRunLoopStop(runLoop)
            }

            waitForThreadExitLocked()

            port = nil
            runLoopSource = nil
            runLoop = nil
            thread = nil
            isRunning = false
            stateLock.lock()
            capturedButtons = []
            stateLock.unlock()
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
        var kind: EventKind?
        var swallow = false

        stateLock.lock()
        switch type {
        case .rightMouseDown, .otherMouseDown:
            if let button, watchedButtonsStorage.contains(button) {
                capturedButtons.insert(button)
                kind = .buttonDown(button, location)
                swallow = true
            }
        case .rightMouseUp, .otherMouseUp:
            if let button, capturedButtons.remove(button) != nil {
                kind = .buttonUp(button, location)
                swallow = true
            }
        case .rightMouseDragged, .otherMouseDragged:
            // Must always pass the event through so the system cursor keeps moving
            // after a consumed trigger-down. Path sampling is primarily timer-based.
            if let button, capturedButtons.contains(button) {
                kind = .drag(location)
            }
        default:
            break
        }
        stateLock.unlock()

        if let kind {
            onEvent?(kind)
        }
        if swallow {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Tap thread install

    private func installTapOnCurrentRunLoop() -> Bool {
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
            eventsOfInterest: Self.eventsOfInterestMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        let current = CFRunLoopGetCurrent()
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        port = eventTap
        runLoopSource = source
        runLoop = current
        return true
    }

    private func teardownTapOnCurrentRunLoop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        port = nil
        runLoopSource = nil
        runLoop = nil
    }

    /// Caller must be on `controlQueue`.
    private func waitForThreadExitLocked() {
        guard let threadExitSemaphore else { return }
        // Bound wait so a stuck runloop cannot deadlock control forever.
        _ = threadExitSemaphore.wait(timeout: .now() + 2.0)
        self.threadExitSemaphore = nil
        thread = nil
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
        default:
            // Left button is intentionally outside the tap mask and not a trigger.
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
