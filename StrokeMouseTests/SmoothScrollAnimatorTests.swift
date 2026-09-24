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
        let pumped = pump(&animator, from: 0, until: 0.5)

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

    func testFinishesWithinOneAndAHalfDurationWithoutATailJump() throws {
        var animator = SmoothScrollAnimator()
        let duration = 0.08
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
        var now = 0.0
        var frames: [Int32] = []
        while now < duration * 1.5 + Constants.scrollFrameInterval {
            now += Constants.scrollFrameInterval
            guard let delta = animator.step(now: now) else { break }
            frames.append(delta.y)
        }

        XCTAssertTrue(animator.isIdle)
        XCTAssertNil(animator.step(now: now + 0.01))
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        let total = frames.reduce(Int32(0), +)
        XCTAssertEqual(Double(total), 50, accuracy: 1)
        let last = try XCTUnwrap(frames.last)
        let previous = frames[frames.count - 2]
        XCTAssertLessThanOrEqual(last, previous + 1)
    }

    func testNotchDuringAnimationDoesNotSlowTheNextFrame() throws {
        var animator = SmoothScrollAnimator()
        let parameters = ScrollSmoothParameters(
            stepPixels: 80,
            durationMs: 260,
            acceleration: 0
        )
        let frame = Constants.scrollFrameInterval
        animator.add(directionY: 1, directionX: 0, parameters: parameters, now: 0)
        var now = 0.0
        var previous: Int32 = 0
        var checks = 0
        var pending = Array(stride(from: 0.04, through: 0.20, by: 0.04))
        while now < 0.28 {
            let next = now + frame
            if let impulse = pending.first, impulse > now, impulse <= next {
                pending.removeFirst()
                animator.add(
                    directionY: 1,
                    directionX: 0,
                    parameters: parameters,
                    now: impulse
                )
                let delta = try XCTUnwrap(animator.step(now: next))
                XCTAssertGreaterThanOrEqual(delta.y, previous)
                previous = delta.y
                checks += 1
                now = next
                continue
            }
            if let delta = animator.step(now: next) {
                previous = delta.y
            }
            now = next
        }
        XCTAssertGreaterThanOrEqual(checks, 4)
    }

    func testFastRepeatTailDoesNotJump() throws {
        var animator = SmoothScrollAnimator()
        let parameters = ScrollSmoothParameters(
            stepPixels: 80,
            durationMs: 260,
            acceleration: 0.5
        )
        let frame = Constants.scrollFrameInterval
        var now = 0.0
        for index in 0..<10 {
            let impulseTime = Double(index) * 0.02
            while now + frame < impulseTime {
                now += frame
                _ = animator.step(now: now)
            }
            animator.add(
                directionY: 1,
                directionX: 0,
                parameters: parameters,
                now: impulseTime
            )
        }
        var frames: [Int32] = []
        let deadline = now + 1
        while now < deadline {
            now += frame
            guard let delta = animator.step(now: now) else { break }
            if delta.y != 0 {
                frames.append(delta.y)
            }
        }
        XCTAssertTrue(animator.isIdle)
        XCTAssertGreaterThanOrEqual(frames.count, 2)
        let last = Int(try XCTUnwrap(frames.last))
        let previous = Int(frames[frames.count - 2])
        XCTAssertLessThanOrEqual(last, max(2, previous + 1))
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
        let pumped = pump(&animator, from: 0.05, until: 1)

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
        let pumped = pump(&animator, from: 0.4, until: 1)
        XCTAssertEqual(
            pumped.y,
            Int(Constants.scrollRemainingDistanceCap(stepPixels: parameters.stepPixels)),
            accuracy: 1
        )
    }

    private func distance(
        for parameters: ScrollSmoothParameters,
        add: (inout SmoothScrollAnimator) -> Void
    ) -> Int {
        var animator = SmoothScrollAnimator()
        add(&animator)
        return pump(&animator, from: 0, until: 1.2).y
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
