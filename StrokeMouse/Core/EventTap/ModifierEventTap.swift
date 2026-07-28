import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

enum ModifierEventTapError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case creationFailed
}

struct ModifierFlagsStateMachine {
    enum Event: Equatable, Sendable {
        case began(GestureModifierKey)
        case ended(GestureModifierKey)
        case cancelled(GestureModifierKey)
        case drained(GestureModifierKey)
        case interrupted(GestureModifierKey)
    }

    private var watchedKeys: Set<GestureModifierKey>
    private var activeKey: GestureModifierKey?
    private var drainingKey: GestureModifierKey?
    private var waitsForAllKeysUp = false

    init(watchedKeys: Set<GestureModifierKey> = []) {
        self.watchedKeys = watchedKeys
    }

    mutating func setWatchedKeys(_ keys: Set<GestureModifierKey>) {
        watchedKeys = keys
    }

    mutating func reset() {
        activeKey = nil
        drainingKey = nil
        waitsForAllKeysUp = false
    }

    mutating func interrupt(
        keys: Set<GestureModifierKey>
    ) -> Event? {
        let interruptedKey = activeKey ?? drainingKey
        activeKey = nil
        drainingKey = keys.isEmpty ? nil : interruptedKey
        waitsForAllKeysUp = !keys.isEmpty
        return interruptedKey.map(Event.interrupted)
    }

    mutating func process(
        keys: Set<GestureModifierKey>
    ) -> Event? {
        if let activeKey {
            if keys == [activeKey] {
                return nil
            }
            self.activeKey = nil
            if keys.isEmpty {
                return .ended(activeKey)
            }
            waitsForAllKeysUp = true
            drainingKey = activeKey
            return .cancelled(activeKey)
        }

        if waitsForAllKeysUp {
            if keys.isEmpty {
                waitsForAllKeysUp = false
                if let drainingKey {
                    self.drainingKey = nil
                    return .drained(drainingKey)
                }
            }
            return nil
        }
        guard !keys.isEmpty else { return nil }
        guard keys.count == 1, let key = keys.first, watchedKeys.contains(key) else {
            waitsForAllKeysUp = true
            return nil
        }

        activeKey = key
        return .began(key)
    }
}

/// A passive flagsChanged observer used to arm modifier-drawn gestures.
/// It never suppresses keyboard events and runs on its own run loop thread.
final class ModifierEventTap: @unchecked Sendable {
    private final class CallbackContext {
        weak var owner: ModifierEventTap?

        init(owner: ModifierEventTap) {
            self.owner = owner
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "ModifierEventTap"
    )

    static let tapOptions: CGEventTapOptions = .listenOnly
    static let eventsOfInterestMask =
        CGEventMask(1) << CGEventType.flagsChanged.rawValue

    private let stateLock = NSLock()
    private var stateMachine = ModifierFlagsStateMachine()
    // True initially keeps direct state-machine tests independent of AX.
    private var acceptingEvents = true
    private var eventGeneration: UInt64 = 0
    private var onEventStorage:
        (@Sendable (
            ModifierFlagsStateMachine.Event,
            CGPoint,
            UInt64
        ) -> Void)?
    private let physicalKeysProvider:
        @Sendable () -> Set<GestureModifierKey>
    private let controlQueue = DispatchQueue(
        label: "com.strokemouse.app.modifier-eventtap.control"
    )
    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var isRunning = false
    private var threadExitSemaphore: DispatchSemaphore?
    private var callbackContext: Unmanaged<CallbackContext>?

    var onEvent:
        (@Sendable (
            ModifierFlagsStateMachine.Event,
            CGPoint,
            UInt64
        ) -> Void)? {
            get { stateLock.withLock { onEventStorage } }
            set { stateLock.withLock { onEventStorage = newValue } }
        }

    var watchedKeys: Set<GestureModifierKey> {
        get {
            stateLock.withLock { watchedKeysStorage }
        }
        set {
            stateLock.withLock {
                watchedKeysStorage = newValue
                stateMachine.setWatchedKeys(newValue)
            }
        }
    }

    private var watchedKeysStorage: Set<GestureModifierKey> = []

    var isActive: Bool {
        controlQueue.sync { isRunning }
    }

    init(
        physicalKeysProvider: @escaping @Sendable (
        ) -> Set<GestureModifierKey> = {
            ModifierEventTap.supportedKeys(
                in: CGEventSource.flagsState(.combinedSessionState)
            )
        }
    ) {
        self.physicalKeysProvider = physicalKeysProvider
    }

    func start() -> Result<Void, ModifierEventTapError> {
        controlQueue.sync {
            guard !isRunning else { return .success(()) }
            guard AXIsProcessTrusted() else {
                return .failure(.accessibilityPermissionRequired)
            }
            guard waitForThreadExitLocked() else {
                return .failure(.creationFailed)
            }
            stateLock.withLock {
                stateMachine.reset()
                eventGeneration &+= 1
            }

            let ready = DispatchSemaphore(value: 0)
            let exit = DispatchSemaphore(value: 0)
            threadExitSemaphore = exit
            var installed = false
            let thread = Thread { [weak self] in
                guard self != nil else {
                    ready.signal()
                    exit.signal()
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
                exit.signal()
            }
            thread.name = "com.strokemouse.app.modifier-eventtap"
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
                return .failure(.creationFailed)
            }
            return .success(())
        }
    }

    func stop() {
        controlQueue.sync {
            guard isRunning || runLoop != nil || thread != nil else { return }
            stateLock.withLock {
                acceptingEvents = false
                eventGeneration &+= 1
                stateMachine.reset()
            }
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

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let interruptionGeneration: UInt64? = stateLock.withLock {
                guard acceptingEvents else { return nil }
                eventGeneration &+= 1
                if let port {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
                return eventGeneration
            }
            guard let interruptionGeneration else {
                return Unmanaged.passUnretained(event)
            }
            // Enable first so a release racing this live-state sample is either
            // reflected by the sample or queued as the next flagsChanged edge.
            let physicalKeys = physicalKeysProvider()
            let delivery: [ModifierFlagsStateMachine.Event]? =
                stateLock.withLock {
                guard acceptingEvents,
                      eventGeneration == interruptionGeneration
                else {
                    return nil
                }
                guard let interrupted = stateMachine.interrupt(
                    keys: physicalKeys
                ) else {
                    return []
                }
                var events = [interrupted]
                if physicalKeys.isEmpty,
                   case .interrupted(let key) = interrupted
                {
                    events.append(.drained(key))
                }
                return events
            }
            if let delivery {
                for interruptedEvent in delivery {
                    onEvent?(
                        interruptedEvent,
                        event.location,
                        interruptionGeneration
                    )
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keys = Self.supportedKeys(in: event.flags)
        let delivery: (
            event: ModifierFlagsStateMachine.Event,
            generation: UInt64
        )? = stateLock.withLock {
            guard acceptingEvents else { return nil }
            guard let event = stateMachine.process(keys: keys) else {
                return nil
            }
            return (event, eventGeneration)
        }
        if let delivery {
            onEvent?(
                delivery.event,
                event.location,
                delivery.generation
            )
        }
        return Unmanaged.passUnretained(event)
    }

    func isCurrentEventGeneration(_ generation: UInt64) -> Bool {
        stateLock.withLock {
            acceptingEvents && eventGeneration == generation
        }
    }

    static func supportedKeys(
        in flags: CGEventFlags
    ) -> Set<GestureModifierKey> {
        var keys = Set<GestureModifierKey>()
        if flags.contains(.maskSecondaryFn) { keys.insert(.function) }
        if flags.contains(.maskControl) { keys.insert(.control) }
        if flags.contains(.maskAlternate) { keys.insert(.option) }
        if flags.contains(.maskShift) { keys.insert(.shift) }
        if flags.contains(.maskCommand) { keys.insert(.command) }
        return keys
    }

    private func installTapOnCurrentRunLoop() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
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

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )
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
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                runLoopSource,
                .commonModes
            )
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
        guard threadExitSemaphore.wait(timeout: .now() + 2) == .success
        else {
            Self.logger.error(
                "Modifier event-tap thread did not stop within 2 seconds"
            )
            return false
        }
        self.threadExitSemaphore = nil
        thread = nil
        return true
    }
}
