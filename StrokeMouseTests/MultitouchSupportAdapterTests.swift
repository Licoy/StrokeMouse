import CoreGraphics
import XCTest
@testable import StrokeMouse

final class MultitouchSupportAdapterTests: XCTestCase {
    func testAdapterDeliversFramesInSourceOrder() throws {
        let source = TestMultitouchFrameSource()
        let adapter = MultitouchSupportAdapter(
            source: source,
            deliveryQueue: DispatchQueue(label: "MultitouchSupportAdapterTests.delivery")
        )
        let delivered = expectation(description: "frames delivered")
        delivered.expectedFulfillmentCount = 2
        let values = LockedValue<[TrackpadTouchFrame]>([])
        let first = frame(timestamp: 1, x: 0.2)
        let second = frame(timestamp: 2, x: 0.4)

        try adapter.start { frame in
            values.withLock { $0.append(frame) }
            delivered.fulfill()
        }
        source.emit(first)
        source.emit(second)

        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(values.value, [first, second])
        XCTAssertTrue(adapter.isRunning)
    }

    func testStopIsIdempotentAndDropsAlreadyQueuedFrames() throws {
        let source = TestMultitouchFrameSource()
        let deliveryQueue = DispatchQueue(
            label: "MultitouchSupportAdapterTests.blockedDelivery"
        )
        let queueGate = DispatchSemaphore(value: 0)
        deliveryQueue.async {
            queueGate.wait()
        }
        let adapter = MultitouchSupportAdapter(
            source: source,
            deliveryQueue: deliveryQueue
        )
        let delivered = expectation(description: "frame is discarded after stop")
        delivered.isInverted = true

        try adapter.start { _ in delivered.fulfill() }
        source.emit(frame(timestamp: 1, x: 0.2))
        adapter.stop()
        adapter.stop()
        queueGate.signal()

        wait(for: [delivered], timeout: 0.15)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertFalse(adapter.isRunning)
    }

    func testStopDoesNotWaitForAnInFlightFrameHandler() throws {
        let source = TestMultitouchFrameSource()
        let adapter = MultitouchSupportAdapter(
            source: source,
            deliveryQueue: DispatchQueue(
                label: "MultitouchSupportAdapterTests.inFlightDelivery"
            )
        )
        let handlerStarted = DispatchSemaphore(value: 0)
        let allowHandlerToFinish = DispatchSemaphore(value: 0)
        let stopReturned = DispatchSemaphore(value: 0)

        try adapter.start { _ in
            handlerStarted.signal()
            allowHandlerToFinish.wait()
        }
        source.emit(frame(timestamp: 1, x: 0.2))
        XCTAssertEqual(
            handlerStarted.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            adapter.stop()
            stopReturned.signal()
        }
        XCTAssertEqual(
            stopReturned.wait(timeout: .now() + 1),
            .success
        )
        allowHandlerToFinish.signal()
        XCTAssertFalse(adapter.isRunning)
    }

    func testStartFailureIsTypedAndLeavesAdapterStopped() {
        let source = TestMultitouchFrameSource()
        source.startError = .startFailed
        let adapter = MultitouchSupportAdapter(source: source)

        XCTAssertThrowsError(try adapter.start { _ in }) { error in
            XCTAssertEqual(error as? MultitouchSupportAdapterError, .startFailed)
        }
        XCTAssertFalse(adapter.isRunning)
    }

    func testAsynchronousSourceFailureIsDeliveredOnAdapterQueue() throws {
        let source = TestMultitouchFrameSource()
        let adapter = MultitouchSupportAdapter(
            source: source,
            deliveryQueue: DispatchQueue(label: "MultitouchSupportAdapterTests.failure")
        )
        let delivered = expectation(description: "failure delivered")
        let frameDelivered = expectation(
            description: "frames queued after failure are discarded"
        )
        frameDelivered.isInverted = true
        let observed = LockedValue<MultitouchSupportAdapterError?>(nil)

        try adapter.start(onFrame: { _ in
            frameDelivered.fulfill()
        }, onFailure: { error in
            observed.withLock { $0 = error }
            delivered.fulfill()
        })
        source.fail(.invalidFrame)
        source.emit(frame(timestamp: 2, x: 0.4))

        wait(for: [delivered, frameDelivered], timeout: 1)
        XCTAssertEqual(observed.value, .invalidFrame)
        XCTAssertEqual(adapter.lastFailure, .invalidFrame)
        XCTAssertFalse(adapter.isRunning)
        XCTAssertEqual(source.stopCount, 1)
    }

    func testAsynchronousFailureRequiresExplicitClearBeforeRestart() throws {
        let source = TestMultitouchFrameSource()
        let adapter = MultitouchSupportAdapter(
            source: source,
            deliveryQueue: DispatchQueue(
                label: "MultitouchSupportAdapterTests.failureRestart"
            )
        )
        let failureHandlerStarted = DispatchSemaphore(value: 0)
        let allowFailureHandlerToFinish = DispatchSemaphore(value: 0)
        let restartReturned = DispatchSemaphore(value: 0)
        let restartError = LockedValue<MultitouchSupportAdapterError?>(nil)

        try adapter.start(onFrame: { _ in }, onFailure: { _ in
            failureHandlerStarted.signal()
            allowFailureHandlerToFinish.wait()
        })
        source.fail(.invalidFrame)
        XCTAssertEqual(
            failureHandlerStarted.wait(timeout: .now() + 1),
            .success
        )

        DispatchQueue.global().async {
            do {
                try adapter.start(onFrame: { _ in }, onFailure: { _ in })
            } catch let error as MultitouchSupportAdapterError {
                restartError.withLock { $0 = error }
            } catch {
                XCTFail("Unexpected restart error: \(error)")
            }
            restartReturned.signal()
        }
        XCTAssertEqual(
            restartReturned.wait(timeout: .now() + 0.1),
            .timedOut
        )

        allowFailureHandlerToFinish.signal()
        XCTAssertEqual(
            restartReturned.wait(timeout: .now() + 1),
            .success
        )
        XCTAssertFalse(adapter.isRunning)
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(restartError.value, .invalidFrame)

        adapter.clearFailure()
        try adapter.start(onFrame: { _ in }, onFailure: { _ in })

        XCTAssertTrue(adapter.isRunning)
        XCTAssertEqual(source.startCount, 2)
    }

    func testProbeReportsMissingFramework() {
        XCTAssertThrowsError(
            try MultitouchSupportBridgeProbe.verify(
                frameworkPath: "/definitely/missing/MultitouchSupport"
            )
        ) { error in
            XCTAssertEqual(
                error as? MultitouchSupportAdapterError,
                .frameworkUnavailable
            )
        }
    }

    func testProbeReportsFirstMissingSymbol() {
        XCTAssertThrowsError(
            try MultitouchSupportBridgeProbe.verify(
                frameworkPath: "/usr/lib/libSystem.B.dylib"
            )
        ) { error in
            XCTAssertEqual(
                error as? MultitouchSupportAdapterError,
                .missingSymbol("MTDeviceCreateDefault")
            )
        }
    }

    func testProbeResolvesCurrentMultitouchSupportSymbols() {
        XCTAssertNoThrow(try MultitouchSupportBridgeProbe.verify())
    }

    func testLiveAdapterStartsAndStopsWhenDefaultDeviceExists() throws {
        let adapter = MultitouchSupportAdapter()

        do {
            try adapter.start { _ in }
        } catch MultitouchSupportAdapterError.deviceUnavailable {
            throw XCTSkip("This Mac has no default multitouch device")
        }

        XCTAssertTrue(adapter.isRunning)
        adapter.stop()
        XCTAssertFalse(adapter.isRunning)
    }

    private func frame(timestamp: TimeInterval, x: CGFloat) -> TrackpadTouchFrame {
        TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: [
                TrackpadTouchContact(
                    id: 7,
                    phase: .moved,
                    position: CGPoint(x: x, y: 0.6)
                ),
            ]
        )
    }
}

private final class TestMultitouchFrameSource: MultitouchSupportFrameSource,
    @unchecked Sendable
{
    var startError: MultitouchSupportAdapterError?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onFrame: (@Sendable (TrackpadTouchFrame) -> Void)?
    private var onFailure: (@Sendable (MultitouchSupportAdapterError) -> Void)?

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (MultitouchSupportAdapterError) -> Void
    ) throws {
        startCount += 1
        if let startError {
            throw startError
        }
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stop() {
        guard onFrame != nil || onFailure != nil else { return }
        stopCount += 1
        onFrame = nil
        onFailure = nil
    }

    func emit(_ frame: TrackpadTouchFrame) {
        onFrame?(frame)
    }

    func fail(_ error: MultitouchSupportAdapterError) {
        onFailure?(error)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
