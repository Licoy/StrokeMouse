import CoreGraphics
import XCTest
@testable import StrokeMouse

final class ScrollEventTapTests: XCTestCase {
    func testTapObservesOnlyScrollWheelAtSessionHead() {
        XCTAssertEqual(ScrollEventTap.tapOptions, .defaultTap)
        XCTAssertEqual(ScrollEventTap.tapLocation, .cgSessionEventTap)
        XCTAssertEqual(
            ScrollEventTap.eventsOfInterestMask,
            CGEventMask(1) << CGEventType.scrollWheel.rawValue
        )
        XCTAssertFalse(ScrollEventTap().reassertEnabled())
    }

    func testReverseReturnsTheSameEventWithNegatedDeltas() throws {
        let tap = ScrollEventTap()
        var snapshot = ScrollTapSnapshot()
        snapshot.enhancementEnabled = true
        snapshot.reverseTrackpadVertical = true
        tap.snapshot = snapshot
        let event = try makeScrollEvent(wheel1: 5, wheel2: 2)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let before = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)

        let returned = try XCTUnwrap(tap.handle(type: .scrollWheel, event: event))
        XCTAssertTrue(returned.takeUnretainedValue() === event)
        XCTAssertEqual(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            -before
        )
        XCTAssertNotEqual(before, 0)
    }

    func testSmoothSwallowsTheEventAndEmitsAnImpulse() throws {
        let tap = ScrollEventTap()
        var snapshot = ScrollTapSnapshot()
        snapshot.enhancementEnabled = true
        snapshot.smoothEnabled = true
        snapshot.smoothStepPixels = 80
        tap.snapshot = snapshot
        var impulses: [ScrollImpulse] = []
        tap.onImpulse = { impulses.append($0) }
        let event = try makeScrollEvent(wheel1: -1, wheel2: 0)

        XCTAssertNil(tap.handle(type: .scrollWheel, event: event))
        XCTAssertEqual(impulses.count, 1)
        XCTAssertEqual(impulses[0].directionY, -1)
        XCTAssertEqual(impulses[0].directionX, 0)
        XCTAssertEqual(impulses[0].parameters.stepPixels, 80)
    }

    func testMarkedAndZeroEventsPassThrough() throws {
        let tap = ScrollEventTap()
        var snapshot = ScrollTapSnapshot()
        snapshot.enhancementEnabled = true
        snapshot.reverseMouseVertical = true
        snapshot.smoothEnabled = true
        tap.snapshot = snapshot
        var impulses: [ScrollImpulse] = []
        tap.onImpulse = { impulses.append($0) }

        let marked = try makeScrollEvent(wheel1: 3, wheel2: 0)
        marked.setIntegerValueField(
            .eventSourceUserData,
            value: CGScrollEventPoster.syntheticEventMarker
        )
        let markedDelta = marked.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let returned = try XCTUnwrap(tap.handle(type: .scrollWheel, event: marked))
        XCTAssertTrue(returned.takeUnretainedValue() === marked)
        XCTAssertEqual(
            marked.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            markedDelta
        )

        let zero = try makeScrollEvent(wheel1: 0, wheel2: 0)
        XCTAssertNotNil(tap.handle(type: .scrollWheel, event: zero))
        XCTAssertTrue(impulses.isEmpty)
    }

    func testTimeoutRequestsAnimationCancel() throws {
        let tap = ScrollEventTap()
        var cancelled = false
        tap.onAnimationCancelRequested = { cancelled = true }
        let event = try makeScrollEvent(wheel1: 1, wheel2: 0)

        XCTAssertNotNil(tap.handle(type: .tapDisabledByTimeout, event: event))
        XCTAssertTrue(cancelled)
    }

    private func makeScrollEvent(wheel1: Int32, wheel2: Int32) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ))
    }
}
