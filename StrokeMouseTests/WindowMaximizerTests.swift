import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class WindowMaximizerTests: XCTestCase {
    private let destination = CGRect(x: -1_920, y: -150, width: 1_920, height: 1_040)

    func testPreflightFailureNeverWrites() async {
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            for error in [AXError.success, .attributeUnsupported, .cannotComplete] {
                let ax = RecordingWindowAX()
                ax.unwritableAttribute = attribute
                ax.preflightError = error
                do {
                    try await maximizer(ax).maximize(ax.window, to: destination)
                    XCTFail("Expected unsupported resizing to fail")
                } catch GestureTargetError.windowResizeUnavailable {
                    XCTAssertNotEqual(error, .cannotComplete)
                } catch GestureTargetError.axOperationFailed(let operation, let code) {
                    XCTAssertEqual(code, error)
                    XCTAssertEqual(operation, attribute == kAXPositionAttribute
                        ? .checkPositionWritable : .checkSizeWritable)
                } catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertTrue(ax.writes.isEmpty)
            }
        }
    }

    func testWriteFailureStopsAtFailedAttributeWithoutReadbackOrRetry() async {
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            let ax = RecordingWindowAX()
            ax.failedWriteAttribute = attribute
            do {
                try await maximizer(ax).maximize(ax.window, to: destination)
                XCTFail("Expected AX write failure")
            } catch GestureTargetError.axOperationFailed(let operation, let code) {
                XCTAssertEqual(code, .cannotComplete)
                XCTAssertEqual(operation, attribute == kAXPositionAttribute ? .setPosition : .setSize)
            } catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(ax.writes, attribute == kAXPositionAttribute
                ? [kAXPositionAttribute] : [kAXPositionAttribute, kAXSizeAttribute])
            XCTAssertEqual(ax.readCount, 1)
        }
    }

    func testMaximizeUsesExactWindowAndIsIdempotent() async throws {
        let ax = RecordingWindowAX()
        let action = maximizer(ax)
        try await action.maximize(ax.window, to: destination)
        try await action.maximize(ax.window, to: destination)

        XCTAssertEqual(ax.frame, destination)
        XCTAssertEqual(ax.writes, [kAXPositionAttribute, kAXSizeAttribute])
        XCTAssertTrue(ax.receivedWindows.allSatisfy { CFEqual($0, ax.window) })
    }

    func testLayoutReappliesPositionAfterResizingForDisplayConstraints() async throws {
        let ax = RecordingWindowAX()
        try await maximizer(ax).maximize(ax.window, to: destination, correctPositionAfterResize: true)
        XCTAssertEqual(ax.writes, [kAXPositionAttribute, kAXSizeAttribute, kAXPositionAttribute])
        XCTAssertEqual(ax.frame, destination)
    }

    func testConstrainedSizeDoesNotReportSuccess() async {
        let ax = RecordingWindowAX()
        ax.appliedFrame = CGRect(x: destination.minX, y: destination.minY, width: 800, height: 600)
        do {
            try await maximizer(ax).maximize(ax.window, to: destination)
            XCTFail("Expected constrained window to fail verification")
        } catch GestureTargetError.windowMaximizeFailed {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(ax.writes, [kAXPositionAttribute, kAXSizeAttribute])
    }

    func testReadbackAllowsOnePointRounding() async throws {
        let ax = RecordingWindowAX()
        ax.appliedFrame = CGRect(x: -1_919, y: -151, width: 1_919, height: 1_041)
        try await maximizer(ax).maximize(ax.window, to: destination)
        XCTAssertEqual(ax.writes.count, 2)
    }

    func testReadbackFailurePropagatesWithoutRewriting() async {
        let ax = RecordingWindowAX()
        ax.readbackError = GestureTargetError.axOperationFailed(operation: .copySize, code: .invalidUIElement)
        do {
            try await maximizer(ax).maximize(ax.window, to: destination)
            XCTFail("Expected readback failure")
        } catch GestureTargetError.axOperationFailed(let operation, let code) {
            XCTAssertEqual(operation, .copySize)
            XCTAssertEqual(code, .invalidUIElement)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(ax.writes.count, 2)
    }

    func testDelayedApplicationResponseOnlyPollsWithoutRewriting() async throws {
        let ax = RecordingWindowAX()
        ax.delayedReads = 2
        var action = maximizer(ax)
        action.completionTimeout = .seconds(1)
        action.pollInterval = .milliseconds(1)
        try await action.maximize(ax.window, to: destination)
        XCTAssertEqual(ax.writes, [kAXPositionAttribute, kAXSizeAttribute])
        XCTAssertGreaterThan(ax.readCount, 2)
    }

    func testLayoutAcceptsMinimumSizeAndPositionsAfterResize() async throws {
        let ax = RecordingWindowAX()
        let requested = CGRect(x: 250, y: 200, width: 400, height: 300)
        ax.appliedFrame = CGRect(x: 100, y: 100, width: 820, height: 520)
        try await maximizer(ax).applyLayout(ax.window, to: requested)
        XCTAssertEqual(ax.frame, CGRect(x: 250, y: 200, width: 820, height: 520))
        XCTAssertEqual(ax.writes, [kAXSizeAttribute, kAXPositionAttribute])
    }

    func testLayoutWaitsForAsyncResizeBeforePositioning() async throws {
        let ax = RecordingWindowAX()
        ax.delayedReads = 25 // Exceeds the old 500ms deadline.
        var action = maximizer(ax)
        action.completionTimeout = .milliseconds(1500)
        let requested = CGRect(x: 250, y: 200, width: 400, height: 300)
        try await action.applyLayout(ax.window, to: requested)
        XCTAssertEqual(ax.frame, requested)
        XCTAssertEqual(ax.writes, [kAXSizeAttribute, kAXPositionAttribute])
    }

    func testLayoutDoesNotAcceptIgnoredResizeJustBecausePositionIsWritable() async {
        let ax = RecordingWindowAX()
        ax.appliedFrame = ax.frame
        do {
            try await maximizer(ax).applyLayout(ax.window, to: CGRect(x: 250, y: 200, width: 400, height: 300))
            XCTFail("Ignored resize must still fail")
        } catch WindowLayoutError.frameNotApplied {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(ax.writes, [kAXSizeAttribute])
    }

    func testRepeatedConstrainedLayoutCanUsePreviouslyVerifiedSize() async throws {
        let ax = RecordingWindowAX()
        let requested = CGRect(x: 250, y: 200, width: 400, height: 300)
        ax.appliedFrame = CGRect(x: 100, y: 100, width: 820, height: 520)
        let accepted = try await maximizer(ax).applyLayout(ax.window, to: requested)
        try await maximizer(ax).applyLayout(ax.window, to: requested, knownAcceptedSize: accepted.size)
        XCTAssertEqual(ax.frame, accepted)
    }

    func testLayoutCanMoveWindowWhoseSizeAlreadyMatches() async throws {
        let ax = RecordingWindowAX()
        let requested = CGRect(x: 250, y: 200, width: 800, height: 600)
        try await maximizer(ax).applyLayout(ax.window, to: requested)
        XCTAssertEqual(ax.frame, requested)
    }

    func testRepeatedMaximizeKeepsOriginalRestoreFrameDespiteAXRounding() async throws {
        for offset in [CGFloat(0), 1, 2] {
            let ax = RecordingWindowAX()
            let original = ax.frame
            let system = MacGestureTargetSystemClient()
            let action = maximizer(ax)
            try await system.maximizeWindow(ax.window, to: destination, using: action)
            // AX may return a slightly rounded position/size after maximizing.
            ax.frame.origin.x += offset
            ax.frame.size.width -= offset
            try await system.maximizeWindow(ax.window, to: destination, using: action)
            XCTAssertEqual(system.previousFrames.count, 1)
            XCTAssertEqual(system.previousFrames.first?.frame, original)
            XCTAssertEqual(ax.writes.count, 2, "Repeated maximize should not write again")
            try await system.restoreWindowFrame(ax.window, using: action)
            XCTAssertEqual(ax.frame, original)
        }
    }

    func testRestoreStillTogglesBetweenOriginalAndMaximizedFrame() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        let action = maximizer(ax)
        try await system.maximizeWindow(ax.window, to: destination, using: action)
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, original)
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, destination)
    }

    func testSecondMaximizeDuringFirstResizeCannotOverwriteRestoreFrame() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        ax.delayedReads = 2
        let started = expectation(description: "First maximize started")
        ax.onFirstWrite = { started.fulfill() }
        let system = MacGestureTargetSystemClient()
        var action = maximizer(ax)
        action.completionTimeout = .seconds(1)
        let first = Task { try await system.maximizeWindow(ax.window, to: destination, using: action) }
        await fulfillment(of: [started], timeout: 1)
        try await system.maximizeWindow(ax.window, to: destination, using: action)
        try await first.value
        XCTAssertEqual(system.previousFrames.first?.frame, original)
        XCTAssertEqual(ax.writes.count, 2)
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, original)
    }

    private func maximizer(_ recording: RecordingWindowAX) -> WindowMaximizer {
        var action = WindowMaximizer()
        action.ax = recording.client
        action.completionTimeout = .zero
        return action
    }
}

@MainActor
final class RecordingWindowAX {
    let window: AXUIElement

    init(pid: pid_t = 101) { window = AXUIElementCreateApplication(pid) }
    var frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    var appliedFrame: CGRect?
    var unwritableAttribute: String?
    var preflightError: AXError = .success
    var failedWriteAttribute: String?
    var ignoresPosition = false
    var readbackError: Error?
    var delayedReads = 0
    var holdsResize = false
    var onFirstWrite: (() -> Void)?
    private(set) var writes: [String] = []
    private(set) var receivedWindows: [AXUIElement] = []
    private(set) var readCount = 0
    private var pendingFrame: CGRect?

    var client: WindowFrameAXClient {
        WindowFrameAXClient(
            readFrame: { window in
                self.receivedWindows.append(window)
                self.readCount += 1
                if !self.writes.isEmpty, let error = self.readbackError { throw error }
                if let pending = self.pendingFrame, !self.holdsResize {
                    if self.delayedReads == 0 {
                        self.frame = pending
                        self.pendingFrame = nil
                    }
                    else { self.delayedReads -= 1 }
                }
                return self.frame
            },
            isSettable: { window, attribute in
                self.receivedWindows.append(window)
                return attribute as String == self.unwritableAttribute
                    ? (self.preflightError, false) : (.success, true)
            },
            setValue: { window, attribute, value in
                self.receivedWindows.append(window)
                self.writes.append(attribute as String)
                if self.writes.count == 1 { self.onFirstWrite?() }
                if attribute as String == self.failedWriteAttribute { return .cannotComplete }
                if attribute as String == kAXPositionAttribute {
                    var point = CGPoint.zero
                    guard AXValueGetValue(value, .cgPoint, &point) else { return .illegalArgument }
                    if !self.ignoresPosition { self.frame.origin = point }
                } else {
                    var size = CGSize.zero
                    guard AXValueGetValue(value, .cgSize, &size) else { return .illegalArgument }
                    self.pendingFrame = self.appliedFrame ?? CGRect(origin: self.frame.origin, size: size)
                }
                return .success
            }
        )
    }
}
