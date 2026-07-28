import CoreGraphics
import Foundation
import OSLog

enum MultitouchSupportAdapterError: Error, Equatable, Sendable {
    case frameworkUnavailable
    case missingSymbol(String)
    case deviceUnavailable
    case invalidDimensions
    case startFailed
    case invalidFrame
    case resourceUnavailable(String?)
}

extension MultitouchSupportAdapterError: CustomStringConvertible {
    var description: String {
        switch self {
        case .frameworkUnavailable:
            return "MultitouchSupport framework unavailable"
        case let .missingSymbol(symbol):
            return "Missing MultitouchSupport symbol: \(symbol)"
        case .deviceUnavailable:
            return "Default multitouch device unavailable"
        case .invalidDimensions:
            return "Multitouch device returned invalid dimensions"
        case .startFailed:
            return "Multitouch device did not enter running state"
        case .invalidFrame:
            return "MultitouchSupport returned an invalid contact frame"
        case let .resourceUnavailable(detail):
            return detail.map { "Multitouch bridge resource unavailable: \($0)" }
                ?? "Multitouch bridge resource unavailable"
        }
    }
}

protocol MultitouchSupportFrameSource: AnyObject, Sendable {
    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (MultitouchSupportAdapterError) -> Void
    ) throws

    func stop()
}

enum MultitouchSupportBridgeProbe {
    static func verify(frameworkPath: String? = nil) throws {
        var bridgeError = SMTrackpadBridgeError()
        let succeeded = withFrameworkPath(frameworkPath) { path in
            SMTrackpadBridgeProbe(path, &bridgeError)
        }
        guard succeeded else {
            throw MultitouchSupportAdapterError(bridgeError: bridgeError)
        }
    }
}

final class MultitouchSupportAdapter: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "MultitouchSupport"
    )

    private let source: MultitouchSupportFrameSource
    private let deliveryQueue: DispatchQueue
    private let lifecycleLock = NSRecursiveLock()
    private let stateLock = NSLock()

    private var generation: UInt64 = 0
    private var running = false
    private var frameHandler: (@Sendable (TrackpadTouchFrame) -> Void)?
    private var failureHandler:
        (@Sendable (MultitouchSupportAdapterError) -> Void)?
    private var storedLastFailure: MultitouchSupportAdapterError?

    init(
        source: MultitouchSupportFrameSource = CMultitouchSupportFrameSource(),
        deliveryQueue: DispatchQueue = DispatchQueue(
            label: "com.strokemouse.app.multitouch.delivery"
        )
    ) {
        self.source = source
        self.deliveryQueue = deliveryQueue
    }

    var isRunning: Bool {
        stateLock.withLock { running }
    }

    var lastFailure: MultitouchSupportAdapterError? {
        stateLock.withLock { storedLastFailure }
    }

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void
    ) throws {
        try start(onFrame: onFrame) { error in
            Self.logger.error("\(error.description, privacy: .public)")
        }
    }

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (
            MultitouchSupportAdapterError
        ) -> Void
    ) throws {
        lifecycleLock.lock()

        let startState: (
            wasRunning: Bool,
            generation: UInt64,
            failure: MultitouchSupportAdapterError?
        ) =
            stateLock.withLock {
            if running {
                frameHandler = onFrame
                failureHandler = onFailure
                return (true, generation, nil)
            }
            if let storedLastFailure {
                return (false, generation, storedLastFailure)
            }
            frameHandler = onFrame
            failureHandler = onFailure
            generation &+= 1
            running = true
            return (false, generation, nil)
        }
        if let failure = startState.failure {
            lifecycleLock.unlock()
            throw failure
        }
        guard !startState.wasRunning else {
            lifecycleLock.unlock()
            return
        }
        let activeGeneration = startState.generation

        do {
            try source.start(
                onFrame: { [weak self] frame in
                    self?.enqueue(frame, generation: activeGeneration)
                },
                onFailure: { [weak self] error in
                    self?.enqueue(error, generation: activeGeneration)
                }
            )
            lifecycleLock.unlock()
        } catch {
            let typedError = error as? MultitouchSupportAdapterError
                ?? .resourceUnavailable(String(describing: error))
            stateLock.withLock {
                guard generation == activeGeneration else { return }
                generation &+= 1
                running = false
                frameHandler = nil
                failureHandler = nil
                storedLastFailure = typedError
            }
            source.stop()
            lifecycleLock.unlock()
            throw typedError
        }
    }

    func stop() {
        lifecycleLock.lock()

        let shouldStop = stateLock.withLock {
            guard running else { return false }
            generation &+= 1
            running = false
            frameHandler = nil
            failureHandler = nil
            return true
        }
        if shouldStop {
            source.stop()
        }
        lifecycleLock.unlock()
    }

    func clearFailure() {
        stateLock.withLock {
            storedLastFailure = nil
        }
    }

    deinit {
        stop()
    }

    private func enqueue(
        _ frame: TrackpadTouchFrame,
        generation: UInt64
    ) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            let handler: (@Sendable (TrackpadTouchFrame) -> Void)? =
                stateLock.withLock {
                guard self.running, self.generation == generation else {
                    return nil
                }
                return self.frameHandler
            }
            handler?(frame)
        }
    }

    private func enqueue(
        _ error: MultitouchSupportAdapterError,
        generation: UInt64
    ) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.lifecycleLock.lock()
            defer { self.lifecycleLock.unlock() }
            let handler: (
                @Sendable (MultitouchSupportAdapterError) -> Void
            )? = stateLock.withLock {
                guard self.running, self.generation == generation else {
                    return nil
                }
                self.generation &+= 1
                self.running = false
                self.storedLastFailure = error
                let handler = self.failureHandler
                self.frameHandler = nil
                self.failureHandler = nil
                return handler
            }
            guard let handler else { return }
            self.source.stop()
            handler(error)
        }
    }

}

final class CMultitouchSupportFrameSource: MultitouchSupportFrameSource,
    @unchecked Sendable
{
    private let frameworkPath: String?
    private let lifecycleLock = NSLock()
    private var bridge: OpaquePointer?
    private var retainedCallbackBox:
        Unmanaged<MultitouchSupportCallbackBox>?

    init(frameworkPath: String? = nil) {
        self.frameworkPath = frameworkPath
    }

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (
            MultitouchSupportAdapterError
        ) -> Void
    ) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard bridge == nil else { return }

        var bridgeError = SMTrackpadBridgeError()
        guard let newBridge = withFrameworkPath(frameworkPath, {
            SMTrackpadBridgeCreate($0, &bridgeError)
        }) else {
            throw MultitouchSupportAdapterError(bridgeError: bridgeError)
        }

        let callbackBox = MultitouchSupportCallbackBox(
            onFrame: onFrame,
            onFailure: onFailure
        )
        let retainedBox = Unmanaged.passRetained(callbackBox)
        let started = SMTrackpadBridgeStart(
            newBridge,
            multitouchFrameCallback,
            multitouchFailureCallback,
            retainedBox.toOpaque(),
            &bridgeError
        )
        guard started else {
            SMTrackpadBridgeDestroy(newBridge)
            retainedBox.release()
            throw MultitouchSupportAdapterError(bridgeError: bridgeError)
        }

        bridge = newBridge
        retainedCallbackBox = retainedBox
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard let bridge else { return }

        SMTrackpadBridgeStop(bridge)
        SMTrackpadBridgeDestroy(bridge)
        self.bridge = nil
        retainedCallbackBox?.release()
        retainedCallbackBox = nil
    }

    deinit {
        stop()
    }
}

private final class MultitouchSupportCallbackBox: @unchecked Sendable {
    private let onFrame: @Sendable (TrackpadTouchFrame) -> Void
    private let onFailure:
        @Sendable (MultitouchSupportAdapterError) -> Void

    init(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (
            MultitouchSupportAdapterError
        ) -> Void
    ) {
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func receive(
        timestamp: TimeInterval,
        contacts: UnsafePointer<SMTrackpadContact>?,
        count: Int
    ) {
        guard count == 0 || contacts != nil else {
            onFailure(.invalidFrame)
            return
        }
        var copiedContacts: [TrackpadTouchContact] = []
        copiedContacts.reserveCapacity(count)
        for index in 0..<count {
            let contact = contacts![index]
            guard let phase = TrackpadTouchPhase(bridgePhase: contact.phase)
            else {
                onFailure(.invalidFrame)
                return
            }
            copiedContacts.append(TrackpadTouchContact(
                id: Int(contact.identifier),
                phase: phase,
                position: CGPoint(x: contact.x, y: contact.y)
            ))
        }
        onFrame(TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: copiedContacts
        ))
    }

    func fail(code: SMTrackpadBridgeErrorCode) {
        onFailure(MultitouchSupportAdapterError(bridgeCode: code))
    }
}

private let multitouchFrameCallback: SMTrackpadFrameCallback = {
    context,
    timestamp,
    contacts,
    count in
    guard let context else { return }
    Unmanaged<MultitouchSupportCallbackBox>
        .fromOpaque(context)
        .takeUnretainedValue()
        .receive(
            timestamp: timestamp,
            contacts: contacts,
            count: count
        )
}

private let multitouchFailureCallback: SMTrackpadFailureCallback = {
    context,
    code in
    guard let context else { return }
    Unmanaged<MultitouchSupportCallbackBox>
        .fromOpaque(context)
        .takeUnretainedValue()
        .fail(code: code)
}

private extension TrackpadTouchPhase {
    init?(bridgePhase: SMTrackpadContactPhase) {
        switch Int(bridgePhase) {
        case SMTrackpadContactPhaseBegan:
            self = .began
        case SMTrackpadContactPhaseMoved:
            self = .moved
        case SMTrackpadContactPhaseResting:
            self = .resting
        case SMTrackpadContactPhaseEnded:
            self = .ended
        case SMTrackpadContactPhaseCancelled:
            self = .cancelled
        default:
            return nil
        }
    }
}

private extension MultitouchSupportAdapterError {
    init(bridgeError: SMTrackpadBridgeError) {
        self.init(
            bridgeCode: bridgeError.code,
            detail: bridgeError.detail.map(String.init(cString:))
        )
    }

    init(
        bridgeCode: SMTrackpadBridgeErrorCode,
        detail: String? = nil
    ) {
        switch Int(bridgeCode) {
        case SMTrackpadBridgeErrorCodeFrameworkUnavailable:
            self = .frameworkUnavailable
        case SMTrackpadBridgeErrorCodeMissingSymbol:
            self = .missingSymbol(detail ?? "<unknown>")
        case SMTrackpadBridgeErrorCodeDeviceUnavailable:
            self = .deviceUnavailable
        case SMTrackpadBridgeErrorCodeInvalidDimensions:
            self = .invalidDimensions
        case SMTrackpadBridgeErrorCodeStartFailed:
            self = .startFailed
        case SMTrackpadBridgeErrorCodeInvalidFrame:
            self = .invalidFrame
        default:
            self = .resourceUnavailable(detail)
        }
    }
}

private func withFrameworkPath<Result>(
    _ frameworkPath: String?,
    _ body: (UnsafePointer<CChar>?) -> Result
) -> Result {
    guard let frameworkPath else {
        return body(nil)
    }
    return frameworkPath.withCString(body)
}

private extension NSLock {
    func withLock<Result>(_ body: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return body()
    }
}
