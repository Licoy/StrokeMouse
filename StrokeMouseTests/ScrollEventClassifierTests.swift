import CoreGraphics
import XCTest
@testable import StrokeMouse

final class ScrollEventClassifierTests: XCTestCase {
    func testDeviceClassification() {
        XCTAssertEqual(
            ScrollEventClassifier.device(for: ScrollEventSample()),
            .lineWheel
        )
        XCTAssertEqual(
            ScrollEventClassifier.device(for: ScrollEventSample(
                isContinuous: true,
                scrollPhase: 2
            )),
            .gestureSurface
        )
        XCTAssertEqual(
            ScrollEventClassifier.device(for: ScrollEventSample(
                isContinuous: true,
                momentumPhase: 2
            )),
            .gestureSurface
        )
        XCTAssertEqual(
            ScrollEventClassifier.device(for: ScrollEventSample(
                isContinuous: true,
                momentumOptionPhase: 1
            )),
            .gestureSurface
        )
        XCTAssertEqual(
            ScrollEventClassifier.device(for: ScrollEventSample(isContinuous: true)),
            .preciseWheel
        )
    }

    func testDisabledAndExcludedPassThroughAndCancelAnimation() {
        var snapshot = activeSnapshot()
        snapshot.enhancementEnabled = false
        let sample = ScrollEventSample(lineDeltaY: 1)
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .passThrough(cancelsAnimation: true)
        )

        snapshot.enhancementEnabled = true
        snapshot.frontmostExcluded = true
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .passThrough(cancelsAnimation: true)
        )
    }

    func testTrackpadUsesTrackpadTogglesAndDoesNotSmooth() {
        var snapshot = activeSnapshot()
        snapshot.reverseMouseVertical = true
        snapshot.reverseTrackpadVertical = true
        snapshot.smoothEnabled = true
        let sample = ScrollEventSample(
            isContinuous: true,
            scrollPhase: 2,
            lineDeltaY: 4,
            lineDeltaX: -2
        )
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .reverse(vertical: true, horizontal: false, cancelsAnimation: false)
        )
    }

    func testPreciseWheelReversesWithMouseTogglesAndDoesNotSmooth() {
        var snapshot = activeSnapshot()
        snapshot.reverseTrackpadVertical = true
        snapshot.smoothEnabled = true
        let sample = ScrollEventSample(isContinuous: true, lineDeltaY: 3)
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .passThrough(cancelsAnimation: false)
        )

        snapshot.reverseMouseVertical = true
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .reverse(vertical: true, horizontal: false, cancelsAnimation: false)
        )
    }

    func testModifierBypassesSmoothAndCancelsAnimation() {
        var snapshot = activeSnapshot()
        snapshot.smoothEnabled = true
        snapshot.reverseMouseVertical = true
        let sample = ScrollEventSample(lineDeltaY: 1, flags: .maskCommand)
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .reverse(vertical: true, horizontal: false, cancelsAnimation: true)
        )
    }

    func testShiftScrollFollowsVerticalReverse() {
        var snapshot = activeSnapshot()
        snapshot.reverseMouseVertical = true
        let sample = ScrollEventSample(lineDeltaX: 1, flags: .maskShift)
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .reverse(vertical: true, horizontal: true, cancelsAnimation: true)
        )
    }

    func testSmoothUsesReversedDirection() {
        var snapshot = activeSnapshot()
        snapshot.smoothEnabled = true
        snapshot.reverseMouseVertical = true
        snapshot.reverseMouseHorizontal = true
        let sample = ScrollEventSample(lineDeltaY: 2, lineDeltaX: -3)
        XCTAssertEqual(
            ScrollEventClassifier.decide(sample, snapshot: snapshot),
            .smooth(directionY: -1, directionX: 1)
        )
    }

    func testZeroDeltaPassesThroughWithoutCancelling() {
        var snapshot = activeSnapshot()
        snapshot.smoothEnabled = true
        XCTAssertEqual(
            ScrollEventClassifier.decide(ScrollEventSample(), snapshot: snapshot),
            .passThrough(cancelsAnimation: false)
        )
    }

    func testLineAndPixelEventsNegateEveryDeltaFamily() throws {
        for units: CGScrollEventUnit in [.line, .pixel] {
            let event = try makeScrollEvent(units: units, wheel1: 2, wheel2: -1)
            let before = DeltaFields(event)
            ScrollEventMutator.reverse(event, vertical: true, horizontal: true)
            assertNegated(before, DeltaFields(event))
        }
    }

    func testIndependentDeltaFieldsNegateWithoutCrossTalk() throws {
        let event = try makeScrollEvent(units: .pixel, wheel1: 0, wheel2: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -4)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.5)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -0.25)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 40)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -7)
        event.setIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: 11)
        event.setIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis2, value: -13)
        event.setIntegerValueField(.scrollWheelEventRawDeltaAxis1, value: 17)
        event.setIntegerValueField(.scrollWheelEventRawDeltaAxis2, value: -19)
        event.setIntegerValueField(.scrollWheelEventMomentumOptionPhase, value: 8)

        let before = DeltaFields(event)
        XCTAssertEqual(before.lineY, 3)
        XCTAssertEqual(before.lineX, -4)
        XCTAssertEqual(before.fixedY, 1.5, accuracy: 0.0001)
        XCTAssertEqual(before.fixedX, -0.25, accuracy: 0.0001)
        XCTAssertEqual(before.pointY, 40)
        XCTAssertEqual(before.pointX, -7)

        ScrollEventMutator.reverse(event, vertical: true, horizontal: false)
        let verticalOnly = DeltaFields(event)
        XCTAssertEqual(verticalOnly.lineY, -before.lineY)
        XCTAssertEqual(verticalOnly.fixedY, -before.fixedY, accuracy: 0.0001)
        XCTAssertEqual(verticalOnly.pointY, -before.pointY)
        XCTAssertEqual(verticalOnly.lineX, before.lineX)
        XCTAssertEqual(verticalOnly.fixedX, before.fixedX, accuracy: 0.0001)
        XCTAssertEqual(verticalOnly.pointX, before.pointX)
        assertOptionalDeltaNegated(
            before.acceleratedY,
            verticalOnly.acceleratedY,
            horizontalBefore: before.acceleratedX,
            horizontalAfter: verticalOnly.acceleratedX
        )
        assertOptionalDeltaNegated(
            before.rawY,
            verticalOnly.rawY,
            horizontalBefore: before.rawX,
            horizontalAfter: verticalOnly.rawX
        )
        XCTAssertEqual(
            event.getIntegerValueField(.scrollWheelEventMomentumOptionPhase),
            8
        )
    }

    private func activeSnapshot() -> ScrollTapSnapshot {
        var snapshot = ScrollTapSnapshot()
        snapshot.enhancementEnabled = true
        return snapshot
    }

    private func makeScrollEvent(
        units: CGScrollEventUnit,
        wheel1: Int32,
        wheel2: Int32
    ) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ))
    }

    /// Synthetic events on this OS drop fields 175–178. Real events that keep
    /// them must still come back negated, and a dropped field must stay zero.
    private func negatedIfStored(_ value: Int64) -> Int64 {
        value == 0 ? 0 : -value
    }

    private func assertOptionalDeltaNegated(
        _ verticalBefore: Int64,
        _ verticalAfter: Int64,
        horizontalBefore: Int64,
        horizontalAfter: Int64
    ) {
        XCTAssertEqual(verticalAfter, negatedIfStored(verticalBefore))
        XCTAssertEqual(horizontalAfter, horizontalBefore)
    }

    private func assertNegated(_ before: DeltaFields, _ after: DeltaFields) {
        XCTAssertEqual(after.lineY, -before.lineY)
        XCTAssertEqual(after.lineX, -before.lineX)
        XCTAssertEqual(after.fixedY, -before.fixedY, accuracy: 0.0001)
        XCTAssertEqual(after.fixedX, -before.fixedX, accuracy: 0.0001)
        XCTAssertEqual(after.pointY, -before.pointY)
        XCTAssertEqual(after.pointX, -before.pointX)
        XCTAssertEqual(after.acceleratedY, negatedIfStored(before.acceleratedY))
        XCTAssertEqual(after.acceleratedX, negatedIfStored(before.acceleratedX))
        XCTAssertEqual(after.rawY, negatedIfStored(before.rawY))
        XCTAssertEqual(after.rawX, negatedIfStored(before.rawX))
        XCTAssertTrue(
            before.lineY != 0 || before.pointY != 0 || before.fixedY != 0,
            "constructed event had no vertical delta to negate"
        )
    }
}

private struct DeltaFields {
    var lineY: Int64
    var lineX: Int64
    var fixedY: Double
    var fixedX: Double
    var pointY: Int64
    var pointX: Int64
    var acceleratedY: Int64
    var acceleratedX: Int64
    var rawY: Int64
    var rawX: Int64

    init(_ event: CGEvent) {
        lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        acceleratedY = event.getIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis1)
        acceleratedX = event.getIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis2)
        rawY = event.getIntegerValueField(.scrollWheelEventRawDeltaAxis1)
        rawX = event.getIntegerValueField(.scrollWheelEventRawDeltaAxis2)
    }
}
