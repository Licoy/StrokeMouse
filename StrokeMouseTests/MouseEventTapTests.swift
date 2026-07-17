import CoreGraphics
import XCTest
@testable import StrokeMouse

final class MouseEventTapTests: XCTestCase {
    private let replayEventMarker: Int64 = 0x5354524F4B454D4F

    func testTapIsConfiguredAsActiveFilter() {
        XCTAssertEqual(MouseEventTap.tapOptions, .defaultTap)
    }

    func testEventsOfInterestExcludesFreeMouseMovedAndLeftButton() {
        let mask = MouseEventTap.eventsOfInterestMask

        XCTAssertFalse(maskContains(mask, .mouseMoved),
                       "Filtering mouseMoved freezes the system cursor on some macOS versions")
        XCTAssertFalse(maskContains(mask, .leftMouseDown))
        XCTAssertFalse(maskContains(mask, .leftMouseUp))
        XCTAssertFalse(maskContains(mask, .leftMouseDragged))

        XCTAssertTrue(maskContains(mask, .rightMouseDown))
        XCTAssertTrue(maskContains(mask, .rightMouseUp))
        XCTAssertTrue(maskContains(mask, .rightMouseDragged))
        XCTAssertTrue(maskContains(mask, .otherMouseDown))
        XCTAssertTrue(maskContains(mask, .otherMouseUp))
        XCTAssertTrue(maskContains(mask, .otherMouseDragged))
    }

    func testWatchedRightButtonKeepsCursorMovingWhileDownAndUpAreConsumed() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        var observedKinds: [String] = []
        tap.onEvent = { event in
            switch event {
            case .buttonDown:
                observedKinds.append("down")
            case .buttonUp:
                observedKinds.append("up")
            case .drag:
                observedKinds.append("drag")
            }
        }

        let down = try makeMouseEvent(type: .rightMouseDown, button: .right)
        let drag = try makeMouseEvent(type: .rightMouseDragged, button: .right)
        let up = try makeMouseEvent(type: .rightMouseUp, button: .right)

        XCTAssertNil(tap.handle(type: .rightMouseDown, event: down))
        XCTAssertNotNil(tap.handle(type: .rightMouseDragged, event: drag))
        XCTAssertNil(tap.handle(type: .rightMouseUp, event: up))
        XCTAssertEqual(observedKinds, ["down", "drag", "up"])
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
        tap.onEvent = { _ in observedEventCount += 1 }

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

    func testTaggedReplayEventsPassThroughWithoutBeingObserved() throws {
        let tap = MouseEventTap()
        tap.watchedButtons = [.right]
        var observedEventCount = 0
        tap.onEvent = { _ in observedEventCount += 1 }

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

    private func maskContains(_ mask: CGEventMask, _ type: CGEventType) -> Bool {
        mask & CGEventMask(1 << type.rawValue) != 0
    }

    private func makeMouseEvent(type: CGEventType, button: CGMouseButton) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: button
        ))
    }
}
