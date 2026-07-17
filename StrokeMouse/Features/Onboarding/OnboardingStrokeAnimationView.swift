import SwiftUI

/// Looping stroke demo drawn with Canvas + TimelineView (no external animation deps).
struct OnboardingStrokeAnimationView: View {
    enum Style {
        /// Single continuous welcome loop (L-shape then return).
        case welcome
        /// hold → draw → release stages for the demo step.
        case demo
    }

    var style: Style = .welcome
    var lineColor: Color = .accentColor
    var lineWidth: CGFloat = 4
    /// Pause while System Settings / permission panel is launching to free main-thread capacity.
    var isPaused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(in: canvas, size: size, time: t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let pathPoints = Self.demoPath(in: size)
        guard pathPoints.count >= 2 else { return }

        let cycle: TimeInterval = style == .welcome ? 2.8 : 3.6
        let phase = time.truncatingRemainder(dividingBy: cycle) / cycle

        switch style {
        case .welcome:
            drawWelcome(context: context, pathPoints: pathPoints, size: size, phase: phase)
        case .demo:
            drawDemo(context: context, pathPoints: pathPoints, size: size, phase: phase)
        }
    }

    private func drawWelcome(
        context: GraphicsContext,
        pathPoints: [CGPoint],
        size: CGSize,
        phase: Double
    ) {
        // 0–0.75 draw stroke, 0.75–1.0 hold then fade.
        let drawEnd = 0.78
        let progress: Double
        let opacity: Double
        if phase < drawEnd {
            progress = phase / drawEnd
            opacity = 1
        } else {
            progress = 1
            opacity = max(0, 1 - (phase - drawEnd) / (1 - drawEnd))
        }

        var ctx = context
        ctx.opacity = opacity
        strokePartialPath(ctx: ctx, points: pathPoints, progress: progress)

        if let cursor = point(along: pathPoints, progress: min(progress, 0.999)), progress < 1 {
            drawCursor(ctx: ctx, at: cursor)
        }
    }

    private func drawDemo(
        context: GraphicsContext,
        pathPoints: [CGPoint],
        size: CGSize,
        phase: Double
    ) {
        // Stages: idle/hold (0–0.18), draw (0.18–0.72), release flash (0.72–1.0)
        let holdEnd = 0.18
        let drawEnd = 0.72

        if phase < holdEnd {
            if let start = pathPoints.first {
                drawCursor(ctx: context, at: start, pressed: true)
                drawHoldRing(ctx: context, at: start, pulse: phase / holdEnd)
            }
            return
        }

        if phase < drawEnd {
            let progress = (phase - holdEnd) / (drawEnd - holdEnd)
            strokePartialPath(ctx: context, points: pathPoints, progress: progress)
            if let cursor = point(along: pathPoints, progress: min(progress, 0.999)) {
                drawCursor(ctx: context, at: cursor, pressed: true)
            }
            return
        }

        // Full path + release
        strokePartialPath(ctx: context, points: pathPoints, progress: 1)
        if let end = pathPoints.last {
            let releaseT = (phase - drawEnd) / (1 - drawEnd)
            drawReleaseBurst(ctx: context, at: end, t: releaseT)
        }
    }

    private func strokePartialPath(ctx: GraphicsContext, points: [CGPoint], progress: Double) {
        guard progress > 0.001 else { return }
        let total = pathLength(points)
        guard total > 0 else { return }
        let target = total * progress

        var path = Path()
        path.move(to: points[0])
        var traveled: CGFloat = 0
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if traveled + seg <= target {
                path.addLine(to: b)
                traveled += seg
            } else {
                let remain = target - traveled
                let t = remain / max(seg, 0.0001)
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                break
            }
        }

        ctx.stroke(
            path,
            with: .color(lineColor),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCursor(ctx: GraphicsContext, at point: CGPoint, pressed: Bool = false) {
        let r: CGFloat = pressed ? 7 : 5
        let circle = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .color(lineColor.opacity(0.9)))
        ctx.stroke(circle, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
    }

    private func drawHoldRing(ctx: GraphicsContext, at point: CGPoint, pulse: Double) {
        let r = 12 + CGFloat(pulse) * 8
        let ring = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        ctx.stroke(ring, with: .color(lineColor.opacity(0.35 + (1 - pulse) * 0.35)), lineWidth: 2)
    }

    private func drawReleaseBurst(ctx: GraphicsContext, at point: CGPoint, t: Double) {
        let r = 6 + CGFloat(t) * 22
        let ring = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        ctx.stroke(ring, with: .color(Color.green.opacity(max(0, 0.7 * (1 - t)))), lineWidth: 2.5)
        let checkR: CGFloat = 5
        let check = Path(ellipseIn: CGRect(x: point.x - checkR, y: point.y - checkR, width: checkR * 2, height: checkR * 2))
        ctx.fill(check, with: .color(Color.green.opacity(0.85)))
    }

    // MARK: - Geometry

    /// Right-angle L stroke that reads well at onboarding sizes.
    private static func demoPath(in size: CGSize) -> [CGPoint] {
        let insetX = size.width * 0.18
        let insetY = size.height * 0.22
        let midY = size.height * 0.55
        return [
            CGPoint(x: insetX, y: insetY),
            CGPoint(x: insetX, y: midY),
            CGPoint(x: size.width - insetX, y: midY),
        ]
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { sum, pair in
            sum + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private func point(along points: [CGPoint], progress: Double) -> CGPoint? {
        guard let first = points.first else { return nil }
        let total = pathLength(points)
        guard total > 0 else { return first }
        let target = total * CGFloat(progress)
        var traveled: CGFloat = 0
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if traveled + seg >= target {
                let t = (target - traveled) / max(seg, 0.0001)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            traveled += seg
        }
        return points.last
    }
}
