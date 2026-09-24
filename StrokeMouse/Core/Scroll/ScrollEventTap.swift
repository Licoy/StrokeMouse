import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

enum ScrollEventTapError: Error, Equatable, Sendable {
    case accessibilityRequired
    case eventTapCreationFailed
}

protocol ScrollEventSource: AnyObject {
    var snapshot: ScrollTapSnapshot { get set }
    var onImpulse: (@Sendable (ScrollImpulse) -> Void)? { get set }
    var onAnimationCancelRequested: (@Sendable () -> Void)? { get set }
    var isActive: Bool { get }

    func start() -> Result<Void, ScrollEventTapError>
    func stop()
    func reassertEnabled() -> Bool
}

/// Filtering scroll tap. The callback only classifies and mutates; it must not
/// touch AX, NSWorkspace, or the main thread.
final class ScrollEventTap: ScrollEventSource, @unchecked Sendable {
    private final class CallbackContext {
        weak var owner: ScrollEventTap?

        init(owner: ScrollEventTap) {
            self.owner = owner
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "ScrollEventTap"
    )

    static let tapLocation: CGEventTapLocation = .cgSessionEventTap
    static let tapOptions: CGEventTapOptions = .defaultTap

    static var eventsOfInterestMask: CGEventMask {
        CGEventMask(1) << CGEventType.scrollWheel.rawValue
    }

    private let stateLock = NSLock()
    private var snapshotStorage = ScrollTapSnapshot()
    private var onImpulseStorage: (@Sendable (ScrollImpulse) -> Void)?
    private var onAnimationCancelRequestedStorage: (@Sendable () -> Void)?
    /// True until `stop`, so `handle` can be tested before a tap exists.
    private var acceptingEvents = true
    private var port: CFMachPort?

    private let controlQueue = DispatchQueue(
        label: "com.strokemouse.app.scroll-eventtap.control"
    )
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var isRunning = false
    private var callbackContext: Unmanaged<CallbackContext>?
    private var threadExitSemaphore: DispatchSemaphore?

    var snapshot: ScrollTapSnapshot {
        get { stateLock.withLock { snapshotStorage } }
        set { stateLock.withLock { snapshotStorage = newValue } }
    }

    var onImpulse: (@Sendable (ScrollImpulse) -> Void)? {
        get { stateLock.withLock { onImpulseStorage } }
        set { stateLock.withLock { onImpulseStorage = newValue } }
    }

    var onAnimationCancelRequested: (@Sendable () -> Void)? {
        get { stateLock.withLock { onAnimationCancelRequestedStorage } }
        set { stateLock.withLock { onAnimationCancelRequestedStorage = newValue } }
    }

    var isActive: Bool {
        controlQueue.sync { isRunning }
    }

    func start() -> Result<Void, ScrollEventTapError> {
        controlQueue.sync {
            if isRunning { return .success(()) }
            guard AXIsProcessTrusted() else {
                return .failure(.accessibilityRequired)
            }
            guard waitForThreadExitLocked() else {
                return .failure(.eventTapCreationFailed)
            }

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
            thread.name = "com.strokemouse.app.scroll-eventtap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()

            ready.wait()
            isRunning = installed
            stateLock.withLock { acceptingEvents = installed }
            if !installed {
                _ = waitForThreadExitLocked()
                return .failure(.eventTapCreationFailed)
            }
            return .success(())
        }
    }

    func stop() {
        controlQueue.sync {
            guard isRunning || runLoop != nil || thread != nil else { return }
            stateLock.withLock { acceptingEvents = false }
            if let port = lockedPort() {
                CGEvent.tapEnable(tap: port, enable: false)
            }
            if let runLoop {
                CFRunLoopStop(runLoop)
            }
            let didExit = waitForThreadExitLocked()
            guard didExit else {
                isRunning = false
                Self.logger.error(
                    "Scroll event-tap thread did not stop within 2 seconds"
                )
                return
            }
            stateLock.withLock { port = nil }
            runLoopSource = nil
            runLoop = nil
            thread = nil
            isRunning = false
        }
    }

    func reassertEnabled() -> Bool {
        controlQueue.sync {
            guard let port = lockedPort() else { return false }
            CGEvent.tapEnable(tap: port, enable: true)
            return CGEvent.tapIsEnabled(tap: port)
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableAndCancelAnimation()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData)
            == CGScrollEventPoster.syntheticEventMarker
        {
            return Unmanaged.passUnretained(event)
        }

        let captured = stateLock.withLock {
            (
                acceptingEvents,
                snapshotStorage,
                onImpulseStorage,
                onAnimationCancelRequestedStorage
            )
        }
        guard captured.0 else {
            return Unmanaged.passUnretained(event)
        }
        let decision = ScrollEventClassifier.decide(
            ScrollEventSample(event: event),
            snapshot: captured.1
        )
        switch decision {
        case .passThrough(let cancelsAnimation):
            if cancelsAnimation { captured.3?() }
            return Unmanaged.passUnretained(event)
        case .reverse(let vertical, let horizontal, let cancelsAnimation):
            if cancelsAnimation { captured.3?() }
            ScrollEventMutator.reverse(
                event,
                vertical: vertical,
                horizontal: horizontal
            )
            return Unmanaged.passUnretained(event)
        case .smooth(let directionY, let directionX):
            captured.2?(
                ScrollImpulse(
                    directionY: directionY,
                    directionX: directionX,
                    parameters: captured.1.smoothParameters,
                    flags: event.flags
                )
            )
            return nil
        }
    }

    deinit {
        stop()
    }

    private func lockedPort() -> CFMachPort? {
        stateLock.withLock { port }
    }

    private func reenableAndCancelAnimation() {
        let port = lockedPort()
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        let cancel = stateLock.withLock { onAnimationCancelRequestedStorage }
        cancel?()
    }

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
            tap: Self.tapLocation,
            place: .headInsertEventTap,
            options: Self.tapOptions,
            eventsOfInterest: Self.eventsOfInterestMask,
            callback: callback,
            userInfo: retainedContext.toOpaque()
        ) else {
            retainedContext.release()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )
        let current = CFRunLoopGetCurrent()
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        stateLock.withLock { port = eventTap }
        runLoopSource = source
        runLoop = current
        callbackContext = retainedContext
        return true
    }

    private func teardownTapOnCurrentRunLoop() {
        if let port = lockedPort() {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                runLoopSource,
                .commonModes
            )
        }
        stateLock.withLock { port = nil }
        runLoopSource = nil
        runLoop = nil
        let retainedContext = callbackContext
        callbackContext = nil
        retainedContext?.release()
    }

    /// Caller must be on `controlQueue`.
    private func waitForThreadExitLocked() -> Bool {
        guard let threadExitSemaphore else { return true }
        guard threadExitSemaphore.wait(timeout: .now() + 2.0) == .success else {
            return false
        }
        self.threadExitSemaphore = nil
        thread = nil
        return true
    }
}
