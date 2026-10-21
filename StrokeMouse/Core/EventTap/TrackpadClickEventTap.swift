import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

/// Left-button tap that lets a physical multi-finger trackpad press become a
/// Touch Gesture.
///
/// - Only left down/up enter the mask; `leftMouseDragged` and all other
///   movement stay outside so cursor delivery never waits on this process.
/// - `.defaultTap` only while some click gesture exists; otherwise the tap is
///   listen-only and merely marks pressed sequences so they never yield a tap.
/// - A swallowed down always swallows its paired up, so applications never see
///   half a click. Synthetic events carrying the replay marker pass untouched.
final class TrackpadClickEventTap: @unchecked Sendable {
    private final class CallbackContext {
        weak var owner: TrackpadClickEventTap?

        init(owner: TrackpadClickEventTap) {
            self.owner = owner
        }
    }

    enum PressDecision: Equatable, Sendable {
        case passThrough
        case swallow
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "TrackpadClickEventTap"
    )

    static var eventsOfInterestMask: CGEventMask {
        let leftDown = CGEventMask(1) << CGEventType.leftMouseDown.rawValue
        let leftUp = CGEventMask(1) << CGEventType.leftMouseUp.rawValue
        return leftDown | leftUp
    }

    static func tapOptions(interceptsPresses: Bool) -> CGEventTapOptions {
        interceptsPresses ? .defaultTap : .listenOnly
    }

    private let stateLock = NSLock()
    private var interceptsPressesStorage = false
    /// Mode of the installed tap; nil keeps the `handle` seam usable in tests.
    private var installedInterceptsStorage: Bool?
    private var onPressStorage: ((Bool) -> PressDecision)?
    /// A swallowed left down still owes its up to this tap.
    private var swallowsUp = false
    /// True until `stop`, so `handle` can be tested before a tap exists.
    private var acceptingEvents = true
    private var port: CFMachPort?

    private let controlQueue = DispatchQueue(
        label: "com.strokemouse.app.trackpad-click-eventtap.control"
    )
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var isRunning = false
    private var callbackContext: Unmanaged<CallbackContext>?
    private var threadExitSemaphore: DispatchSemaphore?

    /// Read by `start()`; a running tap is reinstalled when this changes.
    var interceptsPresses: Bool {
        get { stateLock.withLock { interceptsPressesStorage } }
        set { stateLock.withLock { interceptsPressesStorage = newValue } }
    }

    /// Runs synchronously on the tap thread for each left down. The argument
    /// is false for a listen-only tap. Lock-only work: no AX, IPC or main.
    var onPress: ((Bool) -> PressDecision)? {
        get { stateLock.withLock { onPressStorage } }
        set { stateLock.withLock { onPressStorage = newValue } }
    }

    var isActive: Bool {
        controlQueue.sync { isRunning }
    }

    func start() -> Bool {
        let intercepts = interceptsPresses
        let modeChanged = controlQueue.sync {
            let installed = stateLock.withLock { installedInterceptsStorage }
            return isRunning && installed != intercepts
        }
        if modeChanged {
            stop()
        }
        return controlQueue.sync {
            if isRunning { return true }
            guard AXIsProcessTrusted() else { return false }
            guard waitForThreadExitLocked() else { return false }
            stateLock.withLock { swallowsUp = false }

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
                installed = self.installTapOnCurrentRunLoop(
                    interceptsPresses: intercepts
                )
                ready.signal()
                if installed {
                    CFRunLoopRun()
                    self.teardownTapOnCurrentRunLoop()
                }
                exitSem.signal()
            }
            thread.name = "com.strokemouse.app.trackpad-click-eventtap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()

            ready.wait()
            isRunning = installed
            stateLock.withLock {
                acceptingEvents = installed
                installedInterceptsStorage = installed ? intercepts : nil
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
                installedInterceptsStorage = nil
                swallowsUp = false
            }
            // Disable first so WindowServer stops waiting on this filter.
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
                    "Trackpad click event-tap thread did not stop within 2 seconds"
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

    deinit {
        stop()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A swallowed down keeps owing its up across re-enable.
            if let port = lockedPort() {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData)
            == MouseEventTap.replayEventMarker
        {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            let captured: (canSwallow: Bool, onPress: ((Bool) -> PressDecision)?)? =
                stateLock.withLock {
                    guard acceptingEvents else { return nil }
                    // A fresh press proves any up still owed was lost while
                    // the tap was disabled; never swallow an unrelated up.
                    swallowsUp = false
                    return (
                        installedInterceptsStorage ?? interceptsPressesStorage,
                        onPressStorage
                    )
                }
            guard let captured else {
                return Unmanaged.passUnretained(event)
            }
            let decision = captured.onPress?(captured.canSwallow)
                ?? .passThrough
            guard captured.canSwallow, decision == .swallow else {
                return Unmanaged.passUnretained(event)
            }
            let swallowed = stateLock.withLock {
                guard acceptingEvents else { return false }
                swallowsUp = true
                return true
            }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp:
            let swallowed = stateLock.withLock {
                defer { swallowsUp = false }
                return acceptingEvents && swallowsUp
            }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Tap thread install

    private func lockedPort() -> CFMachPort? {
        stateLock.withLock { port }
    }

    private func installTapOnCurrentRunLoop(interceptsPresses: Bool) -> Bool {
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
            options: Self.tapOptions(interceptsPresses: interceptsPresses),
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
