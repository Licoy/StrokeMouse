import AppKit
import CoreGraphics

/// Borderless, click-through overlay windows that draw the live gesture stroke.
@MainActor
final class GestureHUDController {
    static let shared = GestureHUDController()

    private var windows: [NSWindow] = []
    private var pathViews: [GesturePathView] = []
    private var isVisible = false

    private init() {}

    func showPath(_ points: [CGPoint]) {
        // points are AppKit global coordinates (origin bottom-left of primary screen space).
        ensureWindows()
        guard !points.isEmpty else {
            hide()
            return
        }
        let style = DrawingStyle.snapshot()
        if !isVisible {
            for window in windows {
                window.orderFrontRegardless()
            }
            isVisible = true
        }
        for (index, screen) in NSScreen.screens.enumerated() {
            guard index < pathViews.count else { continue }
            let local = points.map { point -> CGPoint in
                CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
            }
            pathViews[index].points = local
            pathViews[index].style = style
            pathViews[index].needsDisplay = true
        }
    }

    func hide() {
        for view in pathViews {
            view.points = []
            view.needsDisplay = true
        }
        for window in windows {
            window.orderOut(nil)
        }
        isVisible = false
    }

    func tearDown() {
        hide()
        windows.forEach { $0.close() }
        windows.removeAll()
        pathViews.removeAll()
    }

    private func ensureWindows() {
        let screens = NSScreen.screens
        if windows.count == screens.count {
            for (index, screen) in screens.enumerated() {
                windows[index].setFrame(screen.frame, display: false)
            }
            return
        }

        tearDown()

        for screen in screens {
            let view = GesturePathView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.sharingType = .none
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            windows.append(window)
            pathViews.append(view)
        }
    }
}

final class GesturePathView: NSView {
    var points: [CGPoint] = []
    var style: DrawingStyle.Snapshot = DrawingStyle.snapshot()

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !points.isEmpty else { return }

        let lineWidth = max(style.lineWidth, 1)
        let lineColor = style.lineColor

        if points.count >= 2 {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.line(to: point)
            }

            // Soft glow
            lineColor.withAlphaComponent(0.25).setStroke()
            let glow = path.copy() as? NSBezierPath ?? path
            glow.lineWidth = lineWidth + 6
            glow.stroke()

            lineColor.withAlphaComponent(0.95).setStroke()
            path.stroke()

            // Head (current) dot
            if let last = points.last {
                let r = max(lineWidth * 0.9, 4)
                let dot = NSBezierPath(ovalIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2))
                NSColor.white.withAlphaComponent(0.95).setFill()
                dot.fill()
                lineColor.setStroke()
                dot.lineWidth = 2
                dot.stroke()
            }
        }

        // Start point — red circle
        if style.showStartPoint, let start = points.first {
            let r = style.startPointRadius
            let outer = NSBezierPath(ovalIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
            style.startColor.withAlphaComponent(0.95).setFill()
            outer.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            outer.lineWidth = 2
            outer.stroke()

            let innerR = max(r * 0.35, 2)
            let inner = NSBezierPath(ovalIn: CGRect(x: start.x - innerR, y: start.y - innerR, width: innerR * 2, height: innerR * 2))
            NSColor.white.setFill()
            inner.fill()
        }
    }
}
