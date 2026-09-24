import CoreGraphics
import Foundation

struct ScrollImpulse: Equatable, Sendable {
    var directionY: Int
    var directionX: Int
    var parameters: ScrollSmoothParameters
    var flags: CGEventFlags
    var location: CGPoint
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

    func post(_ event: CGEvent) {
        event.post(tap: .cgSessionEventTap)
    }

    static func makeEvent(
        deltaY: Int32,
        deltaX: Int32,
        flags: CGEventFlags,
        location: CGPoint
    ) -> CGEvent? {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
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
        event.location = location
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
        label: "com.strokemouse.app.smooth-scroll"
    )
    private let poster: ScrollEventPosting
    private let clock: @Sendable () -> TimeInterval
    private let installsTimer: Bool
    private let generationLock = NSLock()
    private var generation: UInt64 = 0
    private var animator = SmoothScrollAnimator()
    private var timer: DispatchSourceTimer?
    private var latestFlags: CGEventFlags = []
    private var latestLocation: CGPoint = .zero

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
            self.latestLocation = impulse.location
            self.animator.add(
                directionY: impulse.directionY,
                directionX: impulse.directionX,
                parameters: impulse.parameters,
                now: self.clock()
            )
            self.ensureTimer()
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

    private func ensureTimer() {
        guard installsTimer, timer == nil, !animator.isIdle else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = Constants.scrollFrameInterval
        timer.schedule(
            deadline: .now() + interval,
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
            flags: latestFlags,
            location: latestLocation
        ) else {
            return
        }
        poster.post(event)
    }
}
