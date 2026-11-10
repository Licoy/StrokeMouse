import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class WindowFrameTransactionTests: XCTestCase {
    private let layout = CGRect(x: 0, y: 20, width: 1000, height: 700)
    private let maximized = CGRect(x: 0, y: 20, width: 1400, height: 900)

    func testRestoreOnlyMovesFixedSizeWindowAndStillVerifiesPosition() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        ax.frame.origin = CGPoint(x: 300, y: 250)
        ax.unwritableAttribute = kAXSizeAttribute
        let system = MacGestureTargetSystemClient()
        system.rememberFrame(ax.window, frame: original)
        try await system.restoreWindowFrame(ax.window, using: resizer(ax))
        XCTAssertEqual(ax.frame, original)
        XCTAssertEqual(ax.writes, [kAXPositionAttribute])
        XCTAssertGreaterThan(ax.readCount, 1)
    }

    func testPreflightFailurePreservesEarlierRestorePoint() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        let action = resizer(ax)
        try await system.applyFrame(layout, window: ax.window, using: action)
        ax.unwritableAttribute = kAXSizeAttribute
        do {
            try await system.applyFrame(maximized, window: ax.window, using: action)
            XCTFail("Expected preflight failure")
        } catch GestureTargetError.windowResizeUnavailable { }
        XCTAssertEqual(ax.frame, layout)
        XCTAssertEqual(system.previousFrames.last?.frame, original)
    }

    func testIgnoredLayoutPreservesEarlierRestorePoint() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        let action = resizer(ax)
        try await system.applyFrame(layout, window: ax.window, using: action)
        ax.appliedFrame = ax.frame
        do {
            try await system.applyFrame(maximized, window: ax.window, using: action)
            XCTFail("Expected ignored resize failure")
        } catch WindowLayoutError.frameNotApplied { }
        XCTAssertEqual(system.previousFrames.last?.frame, original)
        ax.appliedFrame = nil
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, original)
    }

    func testPartialLayoutFailureRemembersItsStartingFrame() async throws {
        let ax = RecordingWindowAX()
        let system = MacGestureTargetSystemClient()
        let action = resizer(ax)
        try await system.applyFrame(layout, window: ax.window, using: action)
        ax.failedWriteAttribute = kAXPositionAttribute
        do {
            try await system.applyFrame(maximized, window: ax.window, using: action)
            XCTFail("Expected position write failure after resizing")
        } catch GestureTargetError.axOperationFailed(let operation, _) {
            XCTAssertEqual(operation, .setPosition)
        }
        XCTAssertEqual(ax.frame.size, maximized.size)
        XCTAssertEqual(system.previousFrames.last?.frame, layout)
        ax.failedWriteAttribute = nil
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, layout)
    }

    func testLayoutThenRestoreWaitsForCompleteFrameAndToggles() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        var action = resizer(ax)
        action.completionTimeout = .seconds(1)
        ax.delayedReads = 3
        let started = expectation(description: "Layout resize written")
        ax.onFirstWrite = { started.fulfill() }
        let first = Task {
            try await system.applyFrame(layout, window: ax.window, using: action)
        }
        await fulfillment(of: [started], timeout: 1)
        let restore = Task { try await system.restoreWindowFrame(ax.window, using: action) }
        try await first.value
        try await restore.value
        XCTAssertEqual(ax.frame, original)
        XCTAssertEqual(system.previousFrames.last?.frame, layout)
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, layout)
    }

    func testLayoutThenMaximizeUsesCompletedLayoutAsRestorePoint() async throws {
        let ax = RecordingWindowAX()
        let system = MacGestureTargetSystemClient()
        var action = resizer(ax)
        action.completionTimeout = .seconds(1)
        ax.delayedReads = 3
        let started = expectation(description: "Layout resize written")
        ax.onFirstWrite = { started.fulfill() }
        let first = Task {
            try await system.applyFrame(layout, window: ax.window, using: action)
        }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { try await system.maximizeWindow(ax.window, to: maximized, using: action) }
        try await first.value
        try await second.value
        XCTAssertEqual(ax.frame, maximized)
        XCTAssertEqual(system.previousFrames.last?.frame, layout)
        XCTAssertEqual(ax.writes, [kAXSizeAttribute, kAXPositionAttribute, kAXPositionAttribute, kAXSizeAttribute])
    }

    func testMaximizePreflightFailurePreservesEarlierRestorePoint() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        let action = resizer(ax)
        try await system.applyFrame(layout, window: ax.window, using: action)
        ax.unwritableAttribute = kAXSizeAttribute
        do {
            try await system.maximizeWindow(ax.window, to: maximized, using: action)
            XCTFail("Expected preflight failure")
        } catch GestureTargetError.windowResizeUnavailable { }
        XCTAssertEqual(system.previousFrames.last?.frame, original)
    }

    func testIgnoredFixedSizePositionWriteStillFailsAndKeepsHistory() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        ax.frame.origin.x = 300
        ax.unwritableAttribute = kAXSizeAttribute
        ax.ignoresPosition = true
        let system = MacGestureTargetSystemClient()
        system.rememberFrame(ax.window, frame: original)
        do {
            try await system.restoreWindowFrame(ax.window, using: resizer(ax))
            XCTFail("Expected ignored position write to fail")
        } catch WindowLayoutError.frameNotApplied { }
        XCTAssertEqual(ax.writes, [kAXPositionAttribute])
        XCTAssertEqual(system.previousFrames.last?.frame, original)
    }

    func testAnotherWindowCompletesWhileFirstWindowWaits() async throws {
        let firstAX = RecordingWindowAX()
        let otherAX = RecordingWindowAX(pid: 102)
        let system = MacGestureTargetSystemClient()
        var slow = resizer(firstAX)
        slow.completionTimeout = .seconds(10)
        firstAX.holdsResize = true
        let started = expectation(description: "First window resize started")
        firstAX.onFirstWrite = { started.fulfill() }
        let first = Task { try await system.applyFrame(layout, window: firstAX.window, using: slow) }
        await fulfillment(of: [started], timeout: 1)
        try await system.applyFrame(maximized, window: otherAX.window, using: resizer(otherAX))
        XCTAssertEqual(otherAX.frame, maximized)
        XCTAssertEqual(firstAX.writes, [kAXSizeAttribute], "Other windows must not wait for this resize")
        firstAX.holdsResize = false
        try await first.value
    }

    func testCancelledWaiterDoesNotWriteOrBlockFollowingRestore() async throws {
        let ax = RecordingWindowAX()
        let original = ax.frame
        let system = MacGestureTargetSystemClient()
        var action = resizer(ax)
        action.completionTimeout = .seconds(10)
        ax.holdsResize = true
        let started = expectation(description: "Layout started")
        ax.onFirstWrite = { started.fulfill() }
        let first = Task { try await system.applyFrame(layout, window: ax.window, using: action) }
        await fulfillment(of: [started], timeout: 1)
        let queued = expectation(description: "Waiter submitted")
        let cancelled = Task {
            queued.fulfill()
            try await system.maximizeWindow(ax.window, to: maximized, using: action)
        }
        await fulfillment(of: [queued], timeout: 1)
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("Expected queued operation cancellation")
        } catch is CancellationError { }
        ax.holdsResize = false
        let restore = Task { try await system.restoreWindowFrame(ax.window, using: action) }
        try await first.value
        try await restore.value
        XCTAssertEqual(ax.frame, original)
        XCTAssertEqual(ax.writes, [kAXSizeAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXPositionAttribute])
    }

    func testCenterQueuesAfterLayoutAndRestoresCompletedLayout() async throws {
        let ax = RecordingWindowAX()
        let system = MacGestureTargetSystemClient()
        var action = resizer(ax)
        action.completionTimeout = .seconds(1)
        system.frameResizer = action
        ax.delayedReads = 3
        let started = expectation(description: "Layout started")
        ax.onFirstWrite = { started.fulfill() }
        let first = Task { try await system.applyFrame(layout, window: ax.window, using: action) }
        await fulfillment(of: [started], timeout: 1)
        let target = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(processIdentifier: 101, bundleIdentifier: "test.window"),
            application: nil, window: GestureWindowTarget(element: ax.window)
        )
        let center = Task { try await system.centerWindow(target) }
        try await first.value
        try await center.value
        XCTAssertEqual(ax.frame.size, layout.size)
        XCTAssertEqual(system.previousFrames.last?.frame, layout)
        XCTAssertEqual(ax.writes, [kAXSizeAttribute, kAXPositionAttribute, kAXPositionAttribute])
        try await system.restoreWindowFrame(ax.window, using: action)
        XCTAssertEqual(ax.frame, layout)
    }

    private func resizer(_ ax: RecordingWindowAX) -> WindowMaximizer {
        var resizer = WindowMaximizer()
        resizer.ax = ax.client
        resizer.completionTimeout = .zero
        resizer.pollInterval = .milliseconds(1)
        return resizer
    }
}
