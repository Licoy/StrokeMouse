import AppKit
import CoreGraphics
import QuartzCore

/// Borderless, click-through overlay windows that draw the live gesture stroke.
@MainActor
final class GestureHUDController {
    static let shared = GestureHUDController()

    private var windows: [NSWindow] = []
    private var pathViews: [GesturePathView] = []
    private var isVisible = false
    private var strokeStyle = DrawingStyle.snapshot()

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
        guard !points.isEmpty else {
            hide()
            return
        }
        let startsStroke = !isVisible
        if startsStroke {
            // Screens and style preferences are read once per stroke, not on
            // every 120 Hz sample.
            ensureWindows()
            strokeStyle = DrawingStyle.snapshot()
        }
        let style = lineColorOverride.map(strokeStyle.withLineColor) ?? strokeStyle
        for (window, view) in zip(windows, pathViews) {
            let origin = window.frame.origin
            view.update(
                points: points.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) },
                style: style,
                badge: badge
            )
        }
        if startsStroke {
            for window in windows {
                window.orderFrontRegardless()
            }
            isVisible = true
        }
    }

    func hide() {
        for view in pathViews {
            view.clear()
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
            // A nonactivating panel can join another app's full-screen Space
            // even when StrokeMouse uses the regular (Dock-visible) policy.
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
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

/// Draws the stroke with Core Animation shape layers. Updating layer paths
/// costs a fraction of the main-thread time of redrawing a full-screen view
/// on every sample.
final class GesturePathView: NSView {
    private static let glowExtraWidth: CGFloat = 6

    private(set) var points: [CGPoint] = []
    private(set) var style: DrawingStyle.Snapshot = DrawingStyle.snapshot()
    private(set) var badge: String?

    private let glowLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let headLayer = CAShapeLayer()
    private let badgeLayer = CALayer()
    private let badgeTextLayer = CATextLayer()
    private let startLayer = CAShapeLayer()
    private let startCenterLayer = CAShapeLayer()

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true

        for stroke in [glowLayer, lineLayer] {
            stroke.fillColor = nil
            stroke.lineCap = .round
            stroke.lineJoin = .round
        }
        headLayer.lineWidth = 2
        startLayer.lineWidth = 2
        badgeLayer.anchorPoint = .zero
        badgeLayer.addSublayer(badgeTextLayer)
        // Same stacking as the stroke order: trail, head, badge, start point.
        for sublayer in [
            glowLayer, lineLayer, headLayer, badgeLayer, startLayer, startCenterLayer,
        ] {
            root.addSublayer(sublayer)
        }
        withoutAnimation {
            applyStyle()
            applyBadge()
            layoutStroke()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        points newPoints: [CGPoint],
        style newStyle: DrawingStyle.Snapshot,
        badge newBadge: String?
    ) {
        let styleChanged = newStyle != style
        let badgeChanged = newBadge != badge
        points = newPoints
        style = newStyle
        badge = newBadge
        withoutAnimation {
            if styleChanged { applyStyle() }
            if badgeChanged { applyBadge() }
            layoutStroke()
        }
    }

    func clear() {
        update(points: [], style: style, badge: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        withoutAnimation { applyStyle() }
    }

    private var lineWidth: CGFloat { max(style.lineWidth, 1) }

    private var headRadius: CGFloat { max(lineWidth * 0.9, 4) }

    private func updateContentsScale() {
        guard let scale = window?.backingScaleFactor else { return }
        withoutAnimation {
            for sublayer in [
                glowLayer, lineLayer, headLayer, badgeLayer, badgeTextLayer,
                startLayer, startCenterLayer,
            ] {
                sublayer.contentsScale = scale
            }
        }
    }

    private func applyStyle() {
        let startRadius = style.startPointRadius
        // Layers take CGColors, so resolve dynamic colors for this view.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let lineColor = style.lineColor
            glowLayer.strokeColor = lineColor.withAlphaComponent(0.25).cgColor
            lineLayer.strokeColor = lineColor.withAlphaComponent(0.95).cgColor
            headLayer.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
            headLayer.strokeColor = lineColor.cgColor
            badgeLayer.backgroundColor = lineColor.withAlphaComponent(0.95).cgColor
            startLayer.fillColor = style.startColor.withAlphaComponent(0.95).cgColor
            startLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            startCenterLayer.fillColor = NSColor.white.cgColor
        }
        glowLayer.lineWidth = lineWidth + Self.glowExtraWidth
        lineLayer.lineWidth = lineWidth
        headLayer.path = Self.circle(radius: headRadius)
        startLayer.path = Self.circle(radius: startRadius)
        startCenterLayer.path = Self.circle(radius: max(startRadius * 0.35, 2))
    }

    private func applyBadge() {
        guard let badge else { return }
        let label = NSAttributedString(string: badge, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let size = label.size()
        badgeLayer.bounds = CGRect(x: 0, y: 0, width: size.width + 12, height: size.height + 4)
        badgeLayer.cornerRadius = badgeLayer.bounds.height / 2
        badgeTextLayer.string = label
        badgeTextLayer.frame = CGRect(origin: CGPoint(x: 6, y: 2), size: size)
    }

    private func layoutStroke() {
        let path = CGMutablePath()
        if points.count >= 2 {
            path.addLines(between: points)
        }
        glowLayer.path = path
        lineLayer.path = path

        // Head (current) dot
        let head = points.count >= 2 ? points.last : nil
        headLayer.isHidden = head == nil
        badgeLayer.isHidden = head == nil || badge == nil
        if let head {
            headLayer.position = head
            let offset = headRadius + 6
            badgeLayer.position = CGPoint(x: head.x + offset, y: head.y + offset)
        }

        // Start point — red circle
        let start = style.showStartPoint ? points.first : nil
        startLayer.isHidden = start == nil
        startCenterLayer.isHidden = start == nil
        if let start {
            startLayer.position = start
            startCenterLayer.position = start
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private static func circle(radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}
