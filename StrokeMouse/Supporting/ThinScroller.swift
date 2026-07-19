import AppKit
import ObjectiveC
import SwiftUI

// MARK: - ThinScroller

/// Narrow overlay-style scroller with idle / hover / active knob states.
/// Replaces the stock legacy bar (wide, flat gray, no hover feedback).
final class ThinScroller: NSScroller {
    static let trackWidth: CGFloat = 10
    private static let knobThicknessIdle: CGFloat = 5
    private static let knobThicknessHover: CGFloat = 6

    private var isPointerInside = false
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        trackWidth
    }

    private var runsHorizontally: Bool {
        bounds.width >= bounds.height
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: bounds, highlight: false)
        if usableParts != .noScrollerParts {
            drawKnob()
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Transparent track.
    }

    override func drawKnob() {
        let thickness = (isPointerInside || isDragging) ? Self.knobThicknessHover : Self.knobThicknessIdle
        var knob = rect(for: .knob)
        let horizontal = runsHorizontally

        if horizontal {
            let height = min(thickness, max(knob.height, thickness))
            knob.origin.y = knob.midY - height / 2
            knob.size.height = height
            knob = knob.insetBy(dx: 1, dy: 0)
            knob.size.width = max(knob.width, 18)
        } else {
            let width = min(thickness, max(knob.width, thickness))
            knob.origin.x = knob.midX - width / 2
            knob.size.width = width
            knob = knob.insetBy(dx: 0, dy: 1)
            knob.size.height = max(knob.height, 18)
        }

        let alpha: CGFloat
        if isDragging {
            alpha = 0.58
        } else if isPointerInside {
            alpha = 0.42
        } else {
            alpha = 0.22
        }

        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        let radius = min(knob.width, knob.height) / 2
        NSBezierPath(roundedRect: knob, xRadius: radius, yRadius: radius).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        needsDisplay = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        needsDisplay = true
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        needsDisplay = true
        super.mouseDown(with: event)
        isDragging = false
        needsDisplay = true
    }
}

// MARK: - ScrollAppearance

/// Installs thin scrollers on every `NSScrollView` at creation / tile time so Form tabs
/// never paint a frame with the stock thick bar.
enum ScrollAppearance {
    private static var didInstall = false
    private static var isApplying = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true
        NSScrollView.sm_installThinScrollerHooks()
        // Catch anything already in the hierarchy.
        DispatchQueue.main.async {
            restyleAllWindows()
        }
    }

    /// Immediate, re-entrancy-safe apply. Safe to call from init / tile / UI code.
    static func apply(to scrollView: NSScrollView) {
        guard !isApplying else { return }

        if let host = scrollView.window?.className, host.contains("SU") {
            return
        }

        let needsVertical = !(scrollView.verticalScroller is ThinScroller)
        let needsHorizontal = !(scrollView.horizontalScroller is ThinScroller)
        // Always re-assert overlay prefs — AppKit / SwiftUI may flip them on tab switch.
        let needsStyle =
            scrollView.scrollerStyle != .overlay
            || !scrollView.autohidesScrollers

        guard needsVertical || needsHorizontal || needsStyle else { return }

        isApplying = true
        defer { isApplying = false }

        if needsVertical {
            let scroller = ThinScroller()
            scroller.controlSize = scrollView.verticalScroller?.controlSize ?? .regular
            scrollView.verticalScroller = scroller
        }
        if needsHorizontal {
            let scroller = ThinScroller()
            scroller.controlSize = scrollView.horizontalScroller?.controlSize ?? .regular
            scrollView.horizontalScroller = scroller
        }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
    }

    static func applyRecursively(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            apply(to: scrollView)
        }
        for subview in view.subviews {
            applyRecursively(in: subview)
        }
    }

    static func restyleAllWindows() {
        for window in NSApp.windows {
            if let content = window.contentView {
                applyRecursively(in: content)
            }
        }
    }
}

// MARK: - NSScrollView hooks (subclass-safe swizzle)

private extension NSScrollView {
    static func sm_installThinScrollerHooks() {
        let cls: AnyClass = NSScrollView.self

        // init — style before first paint (eliminates flash on Form / new tabs).
        sm_swizzle(
            cls,
            original: #selector(NSScrollView.init(frame:)),
            swizzled: #selector(NSScrollView.sm_initWithFrame(_:))
        )
        sm_swizzle(
            cls,
            original: #selector(NSScrollView.init(coder:)),
            swizzled: #selector(NSScrollView.sm_initWithCoder(_:))
        )

        // tile — AppKit / SwiftUI may recreate stock scrollers; re-assert before layout paint.
        sm_swizzle(
            cls,
            original: #selector(NSScrollView.tile),
            swizzled: #selector(NSScrollView.sm_tile)
        )

        // viewDidMoveToWindow is often *inherited* from NSView. Use class_addMethod so we
        // only override it on NSScrollView — never touch NSView's IMP (that crashed launch).
        sm_swizzle(
            cls,
            original: #selector(NSView.viewDidMoveToWindow),
            swizzled: #selector(NSScrollView.sm_viewDidMoveToWindow)
        )
    }

    /// Swizzle `original` on `cls` only. If the method lives on a superclass, install a
    /// subclass override instead of exchanging the superclass IMP.
    static func sm_swizzle(_ cls: AnyClass, original: Selector, swizzled: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(cls, swizzled) else { return }

        if let originalMethod = class_getInstanceMethod(cls, original) {
            let added = class_addMethod(
                cls,
                original,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod)
            )
            if added {
                // `original` was inherited; `cls` now has our IMP under `original`.
                // Point `swizzled` at the real superclass implementation for chaining.
                class_replaceMethod(
                    cls,
                    swizzled,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod)
                )
            } else {
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }
    }

    @objc func sm_initWithFrame(_ frameRect: NSRect) -> AnyObject {
        // After exchange / replace this invokes the original init.
        let object = sm_initWithFrame(frameRect)
        if let scrollView = object as? NSScrollView {
            ScrollAppearance.apply(to: scrollView)
        }
        return object
    }

    @objc func sm_initWithCoder(_ coder: NSCoder) -> AnyObject {
        let object = sm_initWithCoder(coder)
        if let scrollView = object as? NSScrollView {
            ScrollAppearance.apply(to: scrollView)
        }
        return object
    }

    @objc func sm_tile() {
        // Install thin scrollers first so width / style participate in this tile pass.
        ScrollAppearance.apply(to: self)
        sm_tile()
    }

    @objc func sm_viewDidMoveToWindow() {
        sm_viewDidMoveToWindow()
        ScrollAppearance.apply(to: self)
    }
}

// MARK: - SwiftUI host (tab switches / late hierarchy)

/// Mounted on the settings root so tab content changes get an immediate restyle pass
/// without waiting for debounced window notifications.
struct ScrollAppearanceInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateNSView(_ nsView: InstallerView, context: Context) {
        nsView.restyleNow()
    }

    final class InstallerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            restyleNow()
        }

        override func layout() {
            super.layout()
            // Immediate — no async delay (delay was the source of “flash then fix”).
            restyleNow()
        }

        func restyleNow() {
            guard let content = window?.contentView else { return }
            ScrollAppearance.applyRecursively(in: content)
        }
    }
}
