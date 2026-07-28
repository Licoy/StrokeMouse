import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import OSLog

/// Active CGEventTap wrapper that reserves configured trigger-button gestures.
///
/// Important design constraints (esp. macOS 14):
/// - Use `.defaultTap` only for trigger down/up. Continuous movement must bypass
///   the filtering tap so macOS can update the cursor independently of this process.
/// - Run the tap on a dedicated CFRunLoop thread so main-thread UI work cannot stall
///   cursor delivery.
final class MouseEventTap: @unchecked Sendable {
    private final class CallbackContext {
        weak var owner: MouseEventTap?

        init(owner: MouseEventTap) {
            self.owner = owner
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "MouseEventTap"
    )

    struct Sample {
        let location: CGPoint
        let timestamp: TimeInterval
    }

    enum EventKind {
        case buttonDown(MouseTriggerButton, CGPoint)
        case buttonUp(MouseTriggerButton, CGPoint)
        case interrupted(MouseTriggerButton, CGPoint)
        case drained(MouseTriggerButton)
    }

    static let tapOptions: CGEventTapOptions = .defaultTap
    private static let replayEventMarker: Int64 = 0x5354524F4B454D4F

    /// Trigger-button edges only. All continuous movement stays outside the tap so
    /// the system updates the cursor without entering this process.
    static var eventsOfInterestMask: CGEventMask {
        let rightDown = CGEventMask(1) << CGEventType.rightMouseDown.rawValue
        let rightUp = CGEventMask(1) << CGEventType.rightMouseUp.rawValue
        let otherDown = CGEventMask(1) << CGEventType.otherMouseDown.rawValue
        let otherUp = CGEventMask(1) << CGEventType.otherMouseUp.rawValue
        return rightDown | rightUp | otherDown | otherUp
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
    private var blockedButtonsUntilUp: Set<MouseTriggerButton> = []
    // True initially keeps the pure `handle` seam usable before a real tap is
    // installed; no system callback can exist until `start()` succeeds.
    private var acceptingEvents = true
    private var eventGeneration: UInt64 = 0
    private var onEventStorage: ((EventKind, UInt64) -> Void)?
    private var shouldCaptureStorage: ((MouseTriggerButton) -> Bool)?
    private let stateLock = NSLock()
    private let buttonStateProvider:
        @Sendable (MouseTriggerButton) -> Bool

    private let controlQueue = DispatchQueue(label: "com.strokemouse.app.eventtap.control")
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var isRunning = false
    private var callbackContext: Unmanaged<CallbackContext>?
    /// Signaled when the tap thread leaves `CFRunLoopRun`.
    private var threadExitSemaphore: DispatchSemaphore?

    var onEvent: ((EventKind, UInt64) -> Void)? {
        get { stateLock.withLock { onEventStorage } }
        set { stateLock.withLock { onEventStorage = newValue } }
    }
    /// Synchronous lightweight arbitration. A rejected down/up pair is passed
    /// through untouched, which is required when another input source owns the session.
    var shouldCapture: ((MouseTriggerButton) -> Bool)? {
        get { stateLock.withLock { shouldCaptureStorage } }
        set { stateLock.withLock { shouldCaptureStorage = newValue } }
    }

    var isActive: Bool {
        controlQueue.sync { isRunning }
    }

    init(
        buttonStateProvider: @escaping @Sendable (
            MouseTriggerButton
        ) -> Bool = { button in
            CGEventSource.buttonState(
                .combinedSessionState,
                button: MouseEventTap.cgMouseButton(for: button)
            )
        }
    ) {
        self.buttonStateProvider = buttonStateProvider
    }

    func start() -> Bool {
        controlQueue.sync {
            guard !isRunning else { return true }
            guard AXIsProcessTrusted() else { return false }

            guard waitForThreadExitLocked() else { return false }
            stateLock.withLock {
                eventGeneration &+= 1
                capturedButtons = []
                blockedButtonsUntilUp = []
            }

            let ready = DispatchSemaphore(value: 0)
            let exitSem = DispatchSemaphore(value: 0)
            threadExitSemaphore = exitSem
            var installed = false

            let thread = Thread { [weak self] in
                guard self != nil else {
                    ready.signal()
                    exitSem.signal()
                    return
                }
                if let self {
                    installed = self.installTapOnCurrentRunLoop()
                }
                ready.signal()
                if installed {
                    CFRunLoopRun()
                    self?.teardownTapOnCurrentRunLoop()
                }
                exitSem.signal()
            }
            thread.name = "com.strokemouse.app.eventtap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()

            ready.wait()
            isRunning = installed
            stateLock.withLock {
                acceptingEvents = installed
            }
            if !installed {
                _ = waitForThreadExitLocked()
            }
            return installed
        }
    }

    func stop() {
        controlQueue.sync {
            guard isRunning || runLoop != nil || thread != nil else { return }

            stateLock.withLock {
                acceptingEvents = false
                eventGeneration &+= 1
                capturedButtons = []
                blockedButtonsUntilUp = []
            }
            // Disable first so WindowServer stops waiting on this filter.
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            if let runLoop {
                CFRunLoopStop(runLoop)
            }

            let didExit = waitForThreadExitLocked()
            guard didExit else {
                isRunning = false
                return
            }

            port = nil
            runLoopSource = nil
            runLoop = nil
            thread = nil
            isRunning = false
        }
    }

    deinit {
        stop()
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

    func isCurrentEventGeneration(_ generation: UInt64) -> Bool {
        stateLock.withLock {
            acceptingEvents && eventGeneration == generation
        }
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let interruptionBase: (
                buttons: Set<MouseTriggerButton>,
                generation: UInt64
            )? = stateLock.withLock {
                guard acceptingEvents else { return nil }
                eventGeneration &+= 1
                let interruptedButtons = capturedButtons
                capturedButtons = []
                if let port {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
                return (interruptedButtons, eventGeneration)
            }
            guard let interruptionBase else {
                return Unmanaged.passUnretained(event)
            }
            // Sample only after re-enabling. A release before this sample is
            // observed here; one after it is delivered as the queued up edge.
            let stillPressed = Set(interruptionBase.buttons.filter {
                buttonStateProvider($0)
            })
            let interruption: [EventKind]? = stateLock.withLock {
                guard acceptingEvents,
                      eventGeneration == interruptionBase.generation
                else {
                    return nil
                }
                blockedButtonsUntilUp.formUnion(stillPressed)
                let alreadyReleased =
                    interruptionBase.buttons.subtracting(stillPressed)
                return interruptionBase.buttons.map {
                    .interrupted($0, event.location)
                } + alreadyReleased.map(EventKind.drained)
            }
            if let interruption {
                for kind in interruption {
                    onEvent?(kind, interruptionBase.generation)
                }
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
        var deliveryGeneration: UInt64?
        var swallow = false

        stateLock.lock()
        guard acceptingEvents else {
            stateLock.unlock()
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .rightMouseDown, .otherMouseDown:
            if let button,
               watchedButtonsStorage.contains(button),
               !blockedButtonsUntilUp.contains(button)
            {
                stateLock.unlock()
                let claimed = shouldCapture?(button) ?? true
                stateLock.lock()
                if acceptingEvents,
                   claimed,
                   !blockedButtonsUntilUp.contains(button)
                {
                    capturedButtons.insert(button)
                    kind = .buttonDown(button, location)
                    deliveryGeneration = eventGeneration
                    swallow = true
                }
            }
        case .rightMouseUp, .otherMouseUp:
            if let button {
                if blockedButtonsUntilUp.remove(button) != nil {
                    kind = .drained(button)
                    deliveryGeneration = eventGeneration
                    break
                }
                if capturedButtons.remove(button) != nil {
                    kind = .buttonUp(button, location)
                    deliveryGeneration = eventGeneration
                    swallow = true
                }
            }
        default:
            break
        }
        stateLock.unlock()

        if let kind, let deliveryGeneration {
            onEvent?(kind, deliveryGeneration)
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
            let context = Unmanaged<CallbackContext>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            guard let tap = context.owner else {
                return Unmanaged.passUnretained(event)
            }
            return tap.handle(type: type, event: event)
        }

        let retainedContext = Unmanaged.passRetained(
            CallbackContext(owner: self)
        )
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: Self.tapOptions,
            eventsOfInterest: Self.eventsOfInterestMask,
            callback: callback,
            userInfo: retainedContext.toOpaque()
        ) else {
            retainedContext.release()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        let current = CFRunLoopGetCurrent()
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        port = eventTap
        runLoopSource = source
        runLoop = current
        callbackContext = retainedContext
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
        let retainedContext = callbackContext
        callbackContext = nil
        retainedContext?.release()
    }

    /// Caller must be on `controlQueue`.
    private func waitForThreadExitLocked() -> Bool {
        guard let threadExitSemaphore else { return true }
        // Bound wait so a stuck runloop cannot deadlock control forever.
        guard threadExitSemaphore.wait(timeout: .now() + 2.0) == .success
        else {
            Self.logger.error(
                "Mouse event-tap thread did not stop within 2 seconds"
            )
            return false
        }
        self.threadExitSemaphore = nil
        thread = nil
        return true
    }

    private func resolveButton(type: CGEventType, event: CGEvent) -> MouseTriggerButton? {
        switch type {
        case .rightMouseDown, .rightMouseUp:
            return .right
        case .otherMouseDown, .otherMouseUp:
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

    private static func cgMouseButton(
        for button: MouseTriggerButton
    ) -> CGMouseButton {
        switch button {
        case .right:
            return .right
        case .middle:
            return .center
        case .sideBack:
            return CGMouseButton(rawValue: 3)!
        case .sideForward:
            return CGMouseButton(rawValue: 4)!
        }
    }
}
