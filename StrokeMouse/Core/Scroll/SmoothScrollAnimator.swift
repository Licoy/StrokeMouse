import Foundation

/// Per-axis inertial scroll. Each impulse travels `step × acceleration factor`
/// and decays with τ = duration / 4 until less than half a pixel remains.
struct SmoothScrollAnimator: Equatable {
    private var vertical = SmoothScrollAxis()
    private var horizontal = SmoothScrollAxis()
    private var lastStepTime: TimeInterval = 0
    private var active = false

    var isIdle: Bool { !active }

    mutating func reset() {
        self = SmoothScrollAnimator()
    }

    mutating func add(
        directionY: Int,
        directionX: Int,
        parameters: ScrollSmoothParameters,
        now: TimeInterval
    ) {
        let parameters = parameters.clamped()
        let wasIdle = !active
        vertical.add(direction: directionY, parameters: parameters, now: now)
        horizontal.add(direction: directionX, parameters: parameters, now: now)
        guard vertical.hasPending || horizontal.hasPending else { return }
        // A notch during an active glide only adds distance. Moving the time
        // base here would shrink the next frame and hitch on every notch.
        if wasIdle {
            lastStepTime = now
        }
        active = true
    }

    /// `nil` means there is nothing left to emit. `(0, 0)` means a frame produced
    /// no whole pixel yet and the animation is still running.
    /// `now` is an absolute clock sample, not a fixed frame step.
    mutating func step(now: TimeInterval) -> (y: Int32, x: Int32)? {
        guard active else { return nil }
        let dt = max(0, now - lastStepTime)
        lastStepTime = now
        let y = vertical.advance(dt: dt)
        let x = horizontal.advance(dt: dt)
        if !vertical.hasPending && !horizontal.hasPending {
            active = false
        }
        return (y, x)
    }
}

private struct SmoothScrollAxis: Equatable {
    var remaining: Double = 0
    var fractional: Double = 0
    var combo = 0
    var lastDirection = 0
    var lastImpulseTime = -TimeInterval.infinity
    var duration: TimeInterval = 0

    var hasPending: Bool {
        abs(remaining) > 0.000_001 || abs(fractional) > 0.000_001
    }

    mutating func add(
        direction: Int,
        parameters: ScrollSmoothParameters,
        now: TimeInterval
    ) {
        guard direction != 0 else { return }
        if lastDirection != 0 && direction != lastDirection {
            remaining = 0
            fractional = 0
            combo = 0
        }
        let withinWindow = now - lastImpulseTime <= Constants.scrollComboWindow
        if direction == lastDirection && withinWindow && combo > 0 {
            combo = min(combo + 1, Constants.scrollComboLimit)
        } else {
            combo = 1
        }
        lastDirection = direction
        lastImpulseTime = now
        let factor = 1 + parameters.acceleration
            * Constants.scrollAccelerationGain
            * Double(combo - 1)
        remaining += parameters.stepPixels * factor * Double(direction)
        let cap = Constants.scrollRemainingDistanceCap(
            stepPixels: parameters.stepPixels
        )
        if remaining > cap { remaining = cap }
        if remaining < -cap { remaining = -cap }
        duration = parameters.durationMs / 1000
    }

    mutating func advance(dt: TimeInterval) -> Int32 {
        guard hasPending else { return 0 }
        let tau = max(duration / 4, 0.000_1)
        var portion = remaining * (1 - exp(-dt / tau))
        if abs(portion) > abs(remaining) {
            portion = remaining
        }
        remaining -= portion
        if abs(remaining) <= Constants.scrollStopDistance {
            let total = remaining + portion + fractional
            remaining = 0
            fractional = 0
            return Int32(total.rounded())
        }
        let total = portion + fractional
        let pixels = Int32(total.rounded(.towardZero))
        fractional = total - Double(pixels)
        if abs(remaining) < 0.000_001 { remaining = 0 }
        if abs(fractional) < 0.000_001 { fractional = 0 }
        return pixels
    }
}
