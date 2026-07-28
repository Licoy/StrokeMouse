import CoreGraphics
import XCTest
@testable import StrokeMouse

final class MouseEventTapTests: XCTestCase {
    private let replayEventMarker: Int64 = 0x5354524F4B454D4F

    func testTapIsConfiguredAsActiveFilter() {
        XCTAssertEqual(MouseEventTap.tapOptions, .defaultTap)
    }

    func testEventsOfInterestExcludesAllContinuousMouseMovement() {
        let mask = MouseEventTap.eventsOfInterestMask

        XCTAssertFalse(maskContains(mask, .mouseMoved),
                       "Filtering movement can freeze the system cursor on macOS 14")
        XCTAssertFalse(maskContains(mask, .leftMouseDown))
        XCTAssertFalse(maskContains(mask, .leftMouseUp))
        XCTAssertFalse(maskContains(mask, .leftMouseDragged))
        XCTAssertFalse(maskContains(mask, .rightMouseDragged))
        XCTAssertFalse(maskContains(mask, .otherMouseDragged))

        XCTAssertTrue(maskContains(mask, .rightMouseDown))
        XCTAssertTrue(maskContains(mask, .rightMouseUp))
        XCTAssertTrue(maskContains(mask, .otherMouseDown))
        XCTAssertTrue(maskContains(mask, .otherMouseUp))
    }

    func testWatchedRightButtonFiltersOnlyDownAndUp() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        var observedKinds: [String] = []
        var observedEventCount = 0
        tap.onEvent = { event, _ in
            observedEventCount += 1
            if case .buttonDown = event {
                observedKinds.append("down")
            } else if case .buttonUp = event {
                observedKinds.append("up")
            }
        }

        let down = try makeMouseEvent(type: .rightMouseDown, button: .right)
        let drag = try makeMouseEvent(type: .rightMouseDragged, button: .right)
        let up = try makeMouseEvent(type: .rightMouseUp, button: .right)

        XCTAssertNil(tap.handle(type: .rightMouseDown, event: down))
        let returnedDrag = try XCTUnwrap(tap.handle(type: .rightMouseDragged, event: drag))
        XCTAssertTrue(returnedDrag.takeUnretainedValue() === drag)
        XCTAssertNil(tap.handle(type: .rightMouseUp, event: up))
        XCTAssertEqual(observedKinds, ["down", "up"])
        XCTAssertEqual(observedEventCount, 2)
    }

    func testWatchedOtherButtonDragPassesThroughUnchangedWithoutNotification() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.middle]
        var observedEventCount = 0
        tap.onEvent = { _, _ in observedEventCount += 1 }

        let down = try makeMouseEvent(type: .otherMouseDown, button: .center)
        let drag = try makeMouseEvent(type: .otherMouseDragged, button: .center)
        let up = try makeMouseEvent(type: .otherMouseUp, button: .center)

        XCTAssertNil(tap.handle(type: .otherMouseDown, event: down))
        let returnedDrag = try XCTUnwrap(tap.handle(type: .otherMouseDragged, event: drag))
        XCTAssertTrue(returnedDrag.takeUnretainedValue() === drag)
        XCTAssertNil(tap.handle(type: .otherMouseUp, event: up))
        XCTAssertEqual(observedEventCount, 2)
    }

    func testLeftButtonEventsPassThroughIfHandled() throws {
        // Left is outside the live mask; handle must still never swallow it.
        let tap = MouseEventTap()
        let down = try makeMouseEvent(type: .leftMouseDown, button: .left)
        let drag = try makeMouseEvent(type: .leftMouseDragged, button: .left)
        let up = try makeMouseEvent(type: .leftMouseUp, button: .left)

        XCTAssertNotNil(tap.handle(type: .leftMouseDown, event: down))
        XCTAssertNotNil(tap.handle(type: .leftMouseDragged, event: drag))
        XCTAssertNotNil(tap.handle(type: .leftMouseUp, event: up))
    }

    func testUnwatchedRightButtonEventsPassThrough() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.middle]
        var observedEventCount = 0
        tap.onEvent = { _, _ in observedEventCount += 1 }

        let down = try makeMouseEvent(type: .rightMouseDown, button: .right)
        let drag = try makeMouseEvent(type: .rightMouseDragged, button: .right)
        let up = try makeMouseEvent(type: .rightMouseUp, button: .right)

        XCTAssertNotNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNotNil(tap.handle(type: .rightMouseDragged, event: drag))
        XCTAssertNotNil(tap.handle(type: .rightMouseUp, event: up))
        XCTAssertEqual(observedEventCount, 0)
    }

    func testUnpairedWatchedButtonUpPassesThrough() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        let up = try makeMouseEvent(type: .rightMouseUp, button: .right)

        XCTAssertNotNil(tap.handle(type: .rightMouseUp, event: up))
    }

    func testRejectedSessionClaimPassesDownAndUpThroughUnchanged() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        tap.shouldCapture = { _ in false }
        var observedEventCount = 0
        tap.onEvent = { _, _ in observedEventCount += 1 }
        let down = try makeMouseEvent(type: .rightMouseDown, button: .right)
        let up = try makeMouseEvent(type: .rightMouseUp, button: .right)

        XCTAssertNotNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNotNil(tap.handle(type: .rightMouseUp, event: up))
        XCTAssertEqual(observedEventCount, 0)
    }

    func testTaggedReplayEventsPassThroughWithoutBeingObserved() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        var observedEventCount = 0
        tap.onEvent = { _, _ in observedEventCount += 1 }

        let events = try XCTUnwrap(MouseEventTap.makeReplayEvents(
            button: .right,
            location: CGPoint(x: 120, y: 80)
        ))

        XCTAssertEqual(
            events.down.getIntegerValueField(.eventSourceUserData),
            replayEventMarker
        )
        XCTAssertEqual(
            events.up.getIntegerValueField(.eventSourceUserData),
            replayEventMarker
        )
        XCTAssertNotNil(tap.handle(type: .rightMouseDown, event: events.down))
        XCTAssertNotNil(tap.handle(type: .rightMouseUp, event: events.up))
        XCTAssertEqual(observedEventCount, 0)
    }

    func testTapDisableInterruptsCaptureAndWaitsForPhysicalButtonUp()
        throws
    {
        let tap = MouseEventTap(buttonStateProvider: { _ in true })
        tap.watchedButtons = [.right]
        var observed: [(kind: String, generation: UInt64)] = []
        tap.onEvent = { event, generation in
            let kind: String
            switch event {
            case .buttonDown: kind = "down"
            case .buttonUp: kind = "up"
            case .interrupted: kind = "interrupted"
            case .drained: kind = "drained"
            }
            observed.append((kind, generation))
        }

        let down = try makeMouseEvent(
            type: .rightMouseDown,
            button: .right
        )
        let up = try makeMouseEvent(
            type: .rightMouseUp,
            button: .right
        )

        XCTAssertNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNotNil(tap.handle(
            type: .tapDisabledByTimeout,
            event: down
        ))
        XCTAssertFalse(tap.isCurrentEventGeneration(0))
        XCTAssertTrue(tap.isCurrentEventGeneration(1))

        // The matching up must pass through and only drain the interrupted
        // physical press. A fresh press can then begin a new sequence.
        XCTAssertNotNil(tap.handle(type: .rightMouseUp, event: up))
        XCTAssertNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNil(tap.handle(type: .rightMouseUp, event: up))

        XCTAssertEqual(observed.map(\.kind), [
            "down",
            "interrupted",
            "drained",
            "down",
            "up",
        ])
        XCTAssertEqual(observed.map(\.generation), [0, 1, 1, 1, 1])
    }

    func testTapDisableImmediatelyDrainsButtonAlreadyReleased()
        throws
    {
        let tap = MouseEventTap(buttonStateProvider: { _ in false })
        tap.watchedButtons = [.right]
        var observed: [String] = []
        tap.onEvent = { event, _ in
            switch event {
            case .buttonDown: observed.append("down")
            case .buttonUp: observed.append("up")
            case .interrupted: observed.append("interrupted")
            case .drained: observed.append("drained")
            }
        }
        let down = try makeMouseEvent(
            type: .rightMouseDown,
            button: .right
        )

        XCTAssertNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNotNil(tap.handle(
            type: .tapDisabledByTimeout,
            event: down
        ))

        XCTAssertEqual(observed, ["down", "interrupted", "drained"])
    }

    func testQuartzLocationConvertsToAppKitCoordinates() {
        let converted = GestureRuntime.appKitLocation(
            fromQuartz: CGPoint(x: 10, y: 30),
            zeroScreenMaxY: 1080
        )
        XCTAssertEqual(converted, CGPoint(x: 10, y: 1050))

        let origin = GestureRuntime.appKitLocation(
            fromQuartz: .zero,
            zeroScreenMaxY: 900
        )
        XCTAssertEqual(origin, CGPoint(x: 0, y: 900))
    }

    private func maskContains(_ mask: CGEventMask, _ type: CGEventType) -> Bool {
        mask & CGEventMask(1 << type.rawValue) != 0
    }

    private func makeMouseEvent(
        type: CGEventType,
        button: CGMouseButton
    ) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: button
        ))
    }
}
