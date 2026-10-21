import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TrackpadPressArbiterTests: XCTestCase {
    func testPressWithoutContactsIsUnrelated() {
        let arbiter = TrackpadPressArbiter()

        XCTAssertEqual(arbiter.press(canSwallow: true), .unrelated)
    }

    func testArmedGroupedRestingPressBecomesClick() {
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 7)
        arbiter.arm(sequenceID: 7, fingerCounts: [3])

        guard case .click(let press) = arbiter.press(canSwallow: true) else {
            return XCTFail("Expected an armed click")
        }
        XCTAssertEqual(press.sequenceID, 7)
        XCTAssertEqual(press.fingers, 3)
        XCTAssertEqual(press.centroid.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(press.centroid.y, 0.45, accuracy: 1e-9)
    }

    func testListenOnlyTapNeverProducesClick() {
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 1)
        arbiter.arm(sequenceID: 1, fingerCounts: [3])

        XCTAssertEqual(arbiter.press(canSwallow: false), .observed)
    }

    func testUnarmedFingerCountIsOnlyObserved() {
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 1)
        arbiter.arm(sequenceID: 1, fingerCounts: [4, 5])

        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testStaleArmingForAnotherSequenceIsIgnored() {
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 2)
        arbiter.arm(sequenceID: 1, fingerCounts: [3])

        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testLateFingerBeyondLandingSpreadIsNotAClick() {
        // Two resting fingers plus a thumb that lands later to click.
        let arbiter = TrackpadPressArbiter()
        var points = threePoints()
        let thumb = points.removeValue(forKey: 3)
        _ = arbiter.record(frame(at: 1, points: points), sequenceID: 1)
        arbiter.arm(sequenceID: 1, fingerCounts: [3])
        points[3] = thumb
        _ = arbiter.record(frame(at: 1.5, points: points), sequenceID: 1)

        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testMovedContactsAreNotAClick() {
        // Three-finger drag synthesizes a left down only after movement.
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 1)
        arbiter.arm(sequenceID: 1, fingerCounts: [3])
        _ = arbiter.record(
            frame(at: 1.1, points: threePoints().mapValues {
                CGPoint(x: $0.x + 0.05, y: $0.y)
            }),
            sequenceID: 1
        )

        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testLiftedContactPreventsClickWithRemainingFingers() {
        let arbiter = TrackpadPressArbiter()
        var points = threePoints()
        points[4] = CGPoint(x: 0.5, y: 0.5)
        _ = arbiter.record(frame(at: 1, points: points), sequenceID: 1)
        arbiter.arm(sequenceID: 1, fingerCounts: [3, 4])
        _ = arbiter.record(frame(at: 1.1, points: threePoints()), sequenceID: 1)

        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testPressedStateIsReportedThroughReleaseThenCleared() {
        let arbiter = TrackpadPressArbiter()
        XCTAssertFalse(
            arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 1)
        )
        _ = arbiter.press(canSwallow: false)

        XCTAssertTrue(
            arbiter.record(frame(at: 1.1, points: threePoints()), sequenceID: 1)
        )
        XCTAssertTrue(arbiter.record(frame(at: 1.2, points: [:]), sequenceID: 1))
        XCTAssertFalse(
            arbiter.record(frame(at: 2, points: threePoints()), sequenceID: 2)
        )
        XCTAssertEqual(arbiter.press(canSwallow: true), .observed)
    }

    func testResetForgetsTheSequence() {
        let arbiter = TrackpadPressArbiter()
        _ = arbiter.record(frame(at: 1, points: threePoints()), sequenceID: 1)
        arbiter.reset()

        XCTAssertEqual(arbiter.press(canSwallow: true), .unrelated)
    }

    private func frame(
        at timestamp: TimeInterval,
        points: [Int: CGPoint]
    ) -> TrackpadTouchFrame {
        TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: points.map {
                TrackpadTouchContact(
                    id: $0.key,
                    phase: .moved,
                    position: $0.value
                )
            }
        )
    }

    private func threePoints() -> [Int: CGPoint] {
        [
            1: CGPoint(x: 0.2, y: 0.4),
            2: CGPoint(x: 0.3, y: 0.5),
            3: CGPoint(x: 0.4, y: 0.45),
        ]
    }
}
