import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TrackpadTapSequenceResolverTests: XCTestCase {
    func testSingleOnlyResolvesImmediately() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)

        XCTAssertEqual(
            resolver.register(first, availability: .singleOnly),
            [.single(first)]
        )
        XCTAssertEqual(resolver.advance(to: 2), [])
    }

    func testSingleAndDoubleDelaysSingleUntilDeadline() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(resolver.advance(to: 1.299), [])
        XCTAssertEqual(resolver.advance(to: 1.301), [.single(first)])
    }

    func testValidSecondTapExecutesOnlyDouble() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(at: 1.20)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(second, availability: .singleAndDouble),
            [.double(first: first, second: second)]
        )
        XCTAssertEqual(resolver.advance(to: 2), [])
    }

    func testSecondTapMayLiftAfterDeadlineWhenItBeganInTime() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(at: 1.45, beganAt: 1.29)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(second, availability: .singleAndDouble),
            [.double(first: first, second: second)]
        )
        XCTAssertEqual(resolver.advance(to: 2), [])
    }

    func testSecondTapThatBeginsAfterDeadlineDoesNotFormDouble() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(at: 1.40, beganAt: 1.31)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(second, availability: .singleAndDouble),
            [.single(first)]
        )
    }

    func testDoubleOnlyDoesNothingWhenSecondTapNeverArrives() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)

        XCTAssertEqual(
            resolver.register(tap(at: 1), availability: .doubleOnly),
            []
        )
        XCTAssertEqual(resolver.advance(to: 1.31), [])
    }

    func testDifferentFingerCountFlushesFirstAndStartsSecondSequence() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(at: 1.1, fingers: 4)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(
                second,
                availability: .singleAndDouble
            ),
            [.single(first)]
        )
        XCTAssertEqual(resolver.advance(to: 1.41), [.single(second)])
    }

    func testFarSecondTapDoesNotFormDouble() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(
            at: 1.1,
            centroid: CGPoint(x: 0.7, y: 0.5)
        )

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(second, availability: .singleAndDouble),
            [.single(first)]
        )
    }

    func testTripleTapProducesDoubleThenPendingSingle() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        let second = tap(at: 1.1)
        let third = tap(at: 1.2)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(
            resolver.register(second, availability: .singleAndDouble),
            [.double(first: first, second: second)]
        )
        XCTAssertEqual(
            resolver.register(third, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(resolver.advance(to: 1.51), [.single(third)])
    }

    func testTimeGoingBackIsRejectedWithoutChangingPendingTap() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)
        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )

        XCTAssertEqual(
            resolver.register(tap(at: 0.9), availability: .singleAndDouble),
            [.invalidTimestamp]
        )
        XCTAssertEqual(resolver.advance(to: 1.31), [.single(first)])
    }

    func testDoubleOnlyPendingDoesNotStealFollowingImmediateSingle() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let doubleOnly = tap(at: 1, fingers: 3)
        let singleOnly = tap(at: 1.1, fingers: 4)

        XCTAssertEqual(
            resolver.register(doubleOnly, availability: .doubleOnly),
            []
        )
        XCTAssertEqual(
            resolver.register(singleOnly, availability: .singleOnly),
            [.single(singleOnly)]
        )
    }

    func testNonTapInterruptionFlushesPendingSingle() {
        var resolver = TrackpadTapSequenceResolver(doubleClickInterval: 0.30)
        let first = tap(at: 1)

        XCTAssertEqual(
            resolver.register(first, availability: .singleAndDouble),
            []
        )
        XCTAssertEqual(resolver.interrupt(), [.single(first)])
        XCTAssertEqual(
            resolver.register(tap(at: 1.2), availability: .singleAndDouble),
            []
        )
    }

    private func tap(
        at timestamp: TimeInterval,
        beganAt: TimeInterval? = nil,
        fingers: Int = 3,
        centroid: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> TrackpadTap {
        TrackpadTap(
            deviceID: 1,
            fingers: fingers,
            centroid: centroid,
            beganAt: beganAt,
            timestamp: timestamp
        )
    }
}
