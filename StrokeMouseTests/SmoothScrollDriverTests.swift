import CoreGraphics
import XCTest
@testable import StrokeMouse

final class SmoothScrollDriverTests: XCTestCase {
    func testSubmitPostsPixelsAndCancelDropsQueuedImpulses() {
        let poster = RecordingPoster()
        let clock = ManualClock()
        let driver = SmoothScrollDriver(
            poster: poster,
            clock: { clock.now },
            installsTimer: false
        )
        let impulse = ScrollImpulse(
            directionY: 1,
            directionX: 0,
            parameters: ScrollSmoothParameters(
                stepPixels: 80,
                durationMs: 80,
                acceleration: 0
            ),
            flags: .maskShift
        )

        clock.now = 0
        driver.submit(impulse)
        driver.tickForTesting()
        clock.now = 0.2
        driver.tickForTesting()

        XCTAssertFalse(poster.events.isEmpty)
        XCTAssertEqual(postedVerticalSum(poster.events), 80, accuracy: 1)
        let event = poster.events[0]
        XCTAssertEqual(event.flags, .maskShift)
        let cursor = CGEvent(source: nil)?.location ?? .zero
        XCTAssertEqual(event.location.x, cursor.x, accuracy: 1)
        XCTAssertEqual(event.location.y, cursor.y, accuracy: 1)

        let beforeCancel = poster.events.count
        driver.submit(impulse)
        driver.cancel()
        clock.now = 1
        driver.tickForTesting()
        XCTAssertEqual(poster.events.count, beforeCancel)
    }

    func testSyntheticEventIsContinuousMarkedAndPixelValued() throws {
        let source = CGEventSource(stateID: .privateState)
        let before = CGEvent(source: nil)?.location ?? .zero
        let event = try XCTUnwrap(CGScrollEventPoster.makeEvent(
            deltaY: 12,
            deltaX: -4,
            flags: .maskCommand,
            source: source
        ))
        let after = CGEvent(source: nil)?.location ?? .zero
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 12)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -4)
        XCTAssertEqual(
            event.getIntegerValueField(.eventSourceUserData),
            CGScrollEventPoster.syntheticEventMarker
        )
        XCTAssertEqual(event.flags, .maskCommand)
        XCTAssertEqual(event.location.x, before.x, accuracy: 1)
        XCTAssertEqual(event.location.y, before.y, accuracy: 1)
        XCTAssertEqual(event.location.x, after.x, accuracy: 1)
        XCTAssertEqual(event.location.y, after.y, accuracy: 1)
    }

    private func postedVerticalSum(_ events: [CGEvent]) -> Int {
        events.reduce(0) { sum, event in
            sum + Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        }
    }
}

private final class RecordingPoster: ScrollEventPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CGEvent] = []

    var events: [CGEvent] {
        lock.withLock { storage }
    }

    func post(_ event: CGEvent) {
        lock.withLock { storage.append(event) }
    }
}

private final class ManualClock: @unchecked Sendable {
    var now: TimeInterval = 0
}
