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

    private func maximizer(_ recording: RecordingWindowAX) -> WindowMaximizer {
        var action = WindowMaximizer()
        action.ax = recording.client
        action.completionTimeout = .zero
        return action
    }
}

@MainActor
private final class RecordingWindowAX {
    let window = AXUIElementCreateApplication(101)
    var frame = CGRect(x: 100, y: 100, width: 800, height: 600)
    var appliedFrame: CGRect?
    var unwritableAttribute: String?
    var preflightError: AXError = .success
    var failedWriteAttribute: String?
    var readbackError: Error?
    var delayedReads = 0
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
                if let pending = self.pendingFrame {
                    if self.delayedReads == 0 { self.frame = pending }
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
                if attribute as String == self.failedWriteAttribute { return .cannotComplete }
                if attribute as String == kAXPositionAttribute {
                    var point = CGPoint.zero
                    guard AXValueGetValue(value, .cgPoint, &point) else { return .illegalArgument }
                    self.frame.origin = point
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
