import XCTest
@testable import StrokeMouse

final class SmoothScrollAnimatorTests: XCTestCase {
    func testTotalDistanceIsConservedAndFramesStayMonotonic() {
        var animator = SmoothScrollAnimator()
        let parameters = ScrollSmoothParameters(
            stepPixels: 100,
            durationMs: 200,
            acceleration: 0
        )
        animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0)
        let pumped = pump(&animator, from: 0, until: 0.25)

        XCTAssertEqual(pumped.y, 100, accuracy: 1)
        XCTAssertEqual(pumped.x, 0)
        XCTAssertTrue(animator.isIdle)
        var running = 0
        for frame in pumped.frames {
            XCTAssertGreaterThanOrEqual(frame.y, 0)
            running += Int(frame.y)
            XCTAssertLessThanOrEqual(running, 101)
        }
        XCTAssertEqual(running, pumped.y)
    }

    func testHardCutoffFinishesAtConfiguredDuration() {
        var animator = SmoothScrollAnimator()
        animator.add(
            directionY: 1,
            directionX: 0,
            parameters: ScrollSmoothParameters(
                stepPixels: 50,
                durationMs: 80,
                acceleration: 0
            ),
            now: 0
        )
        let early = animator.step(now: 0.04)
        XCTAssertNotNil(early)
        XCTAssertFalse(animator.isIdle)

        let final = animator.step(now: 0.08)
        XCTAssertNotNil(final)
        XCTAssertTrue(animator.isIdle)
        XCTAssertNil(animator.step(now: 0.09))
        let total = Int(early?.y ?? 0) + Int(final?.y ?? 0)
        XCTAssertEqual(total, 50, accuracy: 1)
    }

    func testReverseClearsThatAxisOnly() {
        var animator = SmoothScrollAnimator()
        let parameters = ScrollSmoothParameters(
            stepPixels: 100,
            durationMs: 400,
            acceleration: 0
        )
        animator.add(directionY: 1, directionX: 1, parameters: parameters, now: 0)
        _ = animator.step(now: 0.05)
        animator.add(directionY: -1, directionX: 0, parameters: parameters, now: 0.05)
        let pumped = pump(&animator, from: 0.05, until: 0.5)

        XCTAssertEqual(pumped.y, -100, accuracy: 1)
        XCTAssertGreaterThan(pumped.x, 0)
        XCTAssertTrue(pumped.frames.allSatisfy { $0.y <= 0 })
    }

    func testComboAccelerationGrowsThenResetsAfterPause() {
        let parameters = ScrollSmoothParameters(
            stepPixels: 100,
            durationMs: 80,
            acceleration: 1
        )
        let single = distance(for: parameters) { animator in
            animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0)
        }
        let doubled = distance(for: parameters) { animator in
            animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0)
            animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0.05)
        }
        let afterPause = distance(for: parameters) { animator in
            animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0)
            animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0.2)
        }

        XCTAssertEqual(single, 100, accuracy: 1)
        XCTAssertGreaterThan(doubled, single + 20)
        XCTAssertEqual(afterPause, 200, accuracy: 2)
    }

    func testRemainingDistanceIsCapped() {
        var animator = SmoothScrollAnimator()
        let parameters = ScrollSmoothParameters(
            stepPixels: 240,
            durationMs: 80,
            acceleration: 1
        )
        for index in 0..<40 {
            animator.add(
                directionY: 1,
                directionX: 0,
                parameters: parameters,
                now: Double(index) * 0.01
            )
        }
        let pumped = pump(&animator, from: 0.4, until: 0.6)
        XCTAssertEqual(
            pumped.y,
            Int(Constants.scrollRemainingDistanceCap),
            accuracy: 1
        )
    }

    private func distance(
        for parameters: ScrollSmoothParameters,
        add: (inout SmoothScrollAnimator) -> Void
    ) -> Int {
        var animator = SmoothScrollAnimator()
        add(&animator)
        return pump(&animator, from: 0, until: 1).y
    }

    private func pump(
        _ animator: inout SmoothScrollAnimator,
        from start: TimeInterval,
        until end: TimeInterval
    ) -> (y: Int, x: Int, frames: [(y: Int32, x: Int32)]) {
        var y = 0
        var x = 0
        var frames: [(y: Int32, x: Int32)] = []
        var now = start
        while now <= end {
            guard let delta = animator.step(now: now) else { break }
            frames.append((delta.y, delta.x))
            y += Int(delta.y)
            x += Int(delta.x)
            now += Constants.scrollFrameInterval
        }
        return (y, x, frames)
    }
}
