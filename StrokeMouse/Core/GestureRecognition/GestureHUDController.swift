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

    /// - Parameter lineColorOverride: When non-nil, replaces the configured trail color
    ///   (used for live mismatch feedback). Start-point color is unchanged.
    /// - Parameter badge: Short label drawn beside the stroke head.
    func showPath(
        _ points: [CGPoint],
        lineColorOverride: NSColor? = nil,
        badge: String? = nil
    ) {
        // points are AppKit global coordinates (origin bottom-left of primary screen space).
        ensureWindows()
        guard !points.isEmpty else {
            hide()
            return
        }
        let style = DrawingStyle.snapshot(lineColorOverride: lineColorOverride)
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
            pathViews[index].badge = badge
            pathViews[index].needsDisplay = true
        }
    }

    func hide() {
        for view in pathViews {
            view.points = []
            view.badge = nil
            view.needsDisplay = true
        }
        for window in windows {
            window.orderOut(nil)
        }
        isVisible = false
    }

    func setIncludedInCaptures(_ included: Bool) {
        let sharingType: NSWindow.SharingType = included ? .readOnly : .none
        for window in windows where window.sharingType != sharingType {
            window.sharingType = sharingType
        }
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
            setIncludedInCaptures(DrawingStyle.includeHUDInCaptures)
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
            window.sharingType = DrawingStyle.includeHUDInCaptures
                ? .readOnly
                : .none
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
    var badge: String?

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
                if let badge {
                    drawBadge(badge, near: last, offset: r + 6, color: lineColor)
                }
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

    private func drawBadge(
        _ text: String,
        near point: CGPoint,
        offset: CGFloat,
        color: NSColor
    ) {
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        let frame = CGRect(
            x: point.x + offset,
            y: point.y + offset,
            width: size.width + 12,
            height: size.height + 4
        )
        color.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
        label.draw(at: CGPoint(x: frame.minX + 6, y: frame.minY + 2))
    }
}
