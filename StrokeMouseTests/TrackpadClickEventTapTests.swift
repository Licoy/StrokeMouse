import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TrackpadClickEventTapTests: XCTestCase {
    func testMaskHoldsOnlyLeftEdges() {
        let mask = TrackpadClickEventTap.eventsOfInterestMask

        XCTAssertTrue(maskContains(mask, .leftMouseDown))
        XCTAssertTrue(maskContains(mask, .leftMouseUp))
        XCTAssertFalse(maskContains(mask, .leftMouseDragged),
                       "Filtering movement can freeze the system cursor")
        XCTAssertFalse(maskContains(mask, .mouseMoved))
        XCTAssertFalse(maskContains(mask, .rightMouseDown))
        XCTAssertFalse(maskContains(mask, .otherMouseDown))
    }

    func testOnlyClickGesturesInstallAnActiveFilter() {
        XCTAssertEqual(
            TrackpadClickEventTap.tapOptions(interceptsPresses: true),
            .defaultTap
        )
        XCTAssertEqual(
            TrackpadClickEventTap.tapOptions(interceptsPresses: false),
            .listenOnly
        )
    }

    func testSwallowedDownAlsoSwallowsItsPairedUp() throws {
        let tap = TrackpadClickEventTap()
        tap.interceptsPresses = true
        var offeredSwallow: [Bool] = []
        tap.onPress = { canSwallow in
            offeredSwallow.append(canSwallow)
            return .swallow
        }
        let down = try makeEvent(.leftMouseDown)
        let up = try makeEvent(.leftMouseUp)
        let nextUp = try makeEvent(.leftMouseUp)

        XCTAssertNil(tap.handle(type: .leftMouseDown, event: down))
        XCTAssertNil(tap.handle(type: .leftMouseUp, event: up))
        XCTAssertNotNil(tap.handle(type: .leftMouseUp, event: nextUp))
        XCTAssertEqual(offeredSwallow, [true])
    }

    func testPassedThroughDownKeepsItsUp() throws {
        let tap = TrackpadClickEventTap()
        tap.interceptsPresses = true
        tap.onPress = { _ in .passThrough }
        let down = try makeEvent(.leftMouseDown)
        let up = try makeEvent(.leftMouseUp)

        let returnedDown = try XCTUnwrap(
            tap.handle(type: .leftMouseDown, event: down)
        )
        XCTAssertTrue(returnedDown.takeUnretainedValue() === down)
        XCTAssertNotNil(tap.handle(type: .leftMouseUp, event: up))
    }

    func testListenOnlyTapReportsPressButNeverSwallows() throws {
        let tap = TrackpadClickEventTap()
        tap.interceptsPresses = false
        var offeredSwallow: [Bool] = []
        tap.onPress = { canSwallow in
            offeredSwallow.append(canSwallow)
            return .swallow
        }
        let down = try makeEvent(.leftMouseDown)
        let up = try makeEvent(.leftMouseUp)

        XCTAssertNotNil(tap.handle(type: .leftMouseDown, event: down))
        XCTAssertNotNil(tap.handle(type: .leftMouseUp, event: up))
        XCTAssertEqual(offeredSwallow, [false])
    }

    func testFreshDownClearsAnUpOwedFromALostPair() throws {
        let tap = TrackpadClickEventTap()
        tap.interceptsPresses = true
        var decisions: [TrackpadClickEventTap.PressDecision] = [
            .swallow,
            .passThrough,
        ]
        tap.onPress = { _ in decisions.removeFirst() }
        let swallowedDown = try makeEvent(.leftMouseDown)
        let freshDown = try makeEvent(.leftMouseDown)
        let up = try makeEvent(.leftMouseUp)

        XCTAssertNil(tap.handle(type: .leftMouseDown, event: swallowedDown))
        XCTAssertNotNil(tap.handle(type: .leftMouseDown, event: freshDown))
        XCTAssertNotNil(tap.handle(type: .leftMouseUp, event: up))
    }

    func testReplayedEventsBypassPressHandling() throws {
        let tap = TrackpadClickEventTap()
        tap.interceptsPresses = true
        var pressCount = 0
        tap.onPress = { _ in
            pressCount += 1
            return .swallow
        }
        let down = try makeEvent(.leftMouseDown)
        down.setIntegerValueField(
            .eventSourceUserData,
            value: MouseEventTap.replayEventMarker
        )

        XCTAssertNotNil(tap.handle(type: .leftMouseDown, event: down))
        XCTAssertEqual(pressCount, 0)
    }

    private func makeEvent(_ type: CGEventType) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: .left
        ))
    }

    private func maskContains(_ mask: CGEventMask, _ type: CGEventType) -> Bool {
        mask & (CGEventMask(1) << type.rawValue) != 0
    }
}
