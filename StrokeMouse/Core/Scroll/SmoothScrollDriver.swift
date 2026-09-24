import CoreGraphics
import Foundation

struct ScrollImpulse: Equatable, Sendable {
    var directionY: Int
    var directionX: Int
    var parameters: ScrollSmoothParameters
    var flags: CGEventFlags
}

protocol ScrollEventPosting: AnyObject {
    func post(_ event: CGEvent)
}

protocol SmoothScrollDriving: AnyObject {
    func submit(_ impulse: ScrollImpulse)
    func cancel()
}

final class CGScrollEventPoster: ScrollEventPosting, @unchecked Sendable {
    /// "STROKESC" — distinct from the mouse-click replay marker.
    static let syntheticEventMarker: Int64 = 0x5354524F4B455343

    /// Created once. `localEventsSuppressionInterval` is not per-frame work.
    private static let sharedSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    func post(_ event: CGEvent) {
        event.post(tap: .cgSessionEventTap)
    }

    static func makeEvent(
        deltaY: Int32,
        deltaX: Int32,
        flags: CGEventFlags,
        source: CGEventSource? = sharedSource
    ) -> CGEvent? {
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            return nil
        }
        event.flags = flags
        // Do not assign `location`. The constructor samples the cursor, and a
        // stale point is applied by WindowServer as the pointer position.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // Point deltas last. Pixel-unit construction already fills line deltas
        // at the system scale; overwriting those with the pixel count would make
        // line-only clients jump by whole notches per frame.
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: Int64(deltaY)
        )
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis2,
            value: Int64(deltaX)
        )
        event.setIntegerValueField(
            .eventSourceUserData,
            value: syntheticEventMarker
        )
        return event
    }
}

final class SmoothScrollDriver: SmoothScrollDriving, @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.strokemouse.app.smooth-scroll",
        qos: .userInteractive
    )
    private let poster: ScrollEventPosting
    private let clock: @Sendable () -> TimeInterval
    private let installsTimer: Bool
    private let generationLock = NSLock()
    private var generation: UInt64 = 0
    private var animator = SmoothScrollAnimator()
    private var timer: DispatchSourceTimer?
    private var latestFlags: CGEventFlags = []

    init(
        poster: ScrollEventPosting,
        clock: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        installsTimer: Bool = true
    ) {
        self.poster = poster
        self.clock = clock
        self.installsTimer = installsTimer
    }

    func submit(_ impulse: ScrollImpulse) {
        let token = generationLock.withLock { generation }
        queue.async { [weak self] in
            guard let self else { return }
            let current = self.generationLock.withLock { self.generation }
            guard token == current else { return }
            self.latestFlags = impulse.flags
            let wasIdle = self.animator.isIdle
            let now = self.clock()
            self.animator.add(
                directionY: impulse.directionY,
                directionX: impulse.directionX,
                parameters: impulse.parameters,
                now: now
            )
            // Don't wait a full timer period for the first pixels. The sample
            // is one frame ahead so the next fire still has a full interval.
            if wasIdle, !self.animator.isIdle {
                self.step(at: now + Constants.scrollFrameInterval)
            }
            self.ensureTimer(afterLeadingFrame: wasIdle)
        }
    }

    func cancel() {
        generationLock.withLock { generation &+= 1 }
        queue.async { [weak self] in
            self?.animator.reset()
            self?.stopTimer()
        }
    }

    func tickForTesting() {
        queue.sync {
            step(at: clock())
        }
    }

    private func ensureTimer(afterLeadingFrame: Bool) {
        guard installsTimer, timer == nil, !animator.isIdle else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = Constants.scrollFrameInterval
        let firstDelay = afterLeadingFrame ? interval * 2 : interval
        timer.schedule(
            deadline: .now() + firstDelay,
            repeating: interval,
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.step(at: self.clock())
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func step(at now: TimeInterval) {
        guard let delta = animator.step(now: now) else {
            stopTimer()
            return
        }
        guard delta.y != 0 || delta.x != 0 else { return }
        guard let event = CGScrollEventPoster.makeEvent(
            deltaY: delta.y,
            deltaX: delta.x,
            flags: latestFlags
        ) else {
            return
        }
        poster.post(event)
    }
}
