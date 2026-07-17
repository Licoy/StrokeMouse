#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

@available(macOS 13.0, *)
@MainActor
final class FloatingDropPanel: NSPanel {
    private weak var panelController: PermissionFlowController?
    private let hostingView: NSHostingView<AnyView>
    private let sizingView: NSHostingView<AnyView>
    private let initialPanelWidth: CGFloat = 420

    /// System Settings has a leading sidebar. Matching the trailing content
    /// area width keeps the floating panel visually aligned with the pane that
    /// the user is actively interacting with.
    private let sidebarWidth: CGFloat = 230
    private let screenInset: CGFloat = 12
    private let minimumPanelHeight: CGFloat = 96
    private let sizingHeightLimit: CGFloat = 4096

    /// Shorter, AppKit-native launch motion (patched for StrokeMouse smoothness).
    /// Upstream used a 0.72s Timer + Task hop + setFrame(display:true) per
    /// frame, which felt stuttery under concurrent System Settings launch load.
    private let animationDuration: TimeInterval = 0.32
    private let initialAlpha: CGFloat = 0.92
    private let minimumLaunchScale: CGFloat = 0.72
    private var isAnimatingLaunch = false
    private var launchToFrame = NSRect.zero
    private var localeIdentifier: String?
    /// Avoid re-measuring SwiftUI hosting on every settings-window poll tick.
    private var cachedMeasureWidth: CGFloat?
    private var cachedMeasureHeight: CGFloat?

    init(controller: PermissionFlowController) {
        panelController = controller
        localeIdentifier = controller.localeIdentifier
        let panelView = Self.makePanelView(controller: controller, localeIdentifier: controller.localeIdentifier)
        hostingView = NSHostingView(rootView: panelView)
        sizingView = NSHostingView(rootView: panelView)
        super.init(
            contentRect: CGRect(origin: .zero, size: CGSize(width: initialPanelWidth, height: minimumPanelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Prefer explicit NSAnimationContext over system utility-window fades.
        animationBehavior = .none

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Prevent the hosting view from pushing its SwiftUI layout size back
        // onto the enclosing NSWindow. `NSHostingView.sizingOptions` defaults
        // to `[.intrinsicContentSize]` on macOS 13.3+, which makes the host
        // re-advertise the SwiftUI root view's intrinsic size to the window
        // on every layout pass. For the panel content (ultraThinMaterial
        // background + `.fixedSize(vertical: true)` + a markdown-wrapped
        // header `AttributedString`), that intrinsic value diverges from the
        // `sizingView.fittingSize` that `measuredPanelHeight` uses — so the
        // window auto-grows well past the content-size we set, and every
        // subsequent `setFrame(...)` from `snap(to:)` is reverted on the
        // next layout tick, leaving the panel stuck off-screen.
        //
        // Opting out of `.intrinsicContentSize` makes the existing
        // `measuredPanelHeight` → `setContentSize` / `snap(to:)` pipeline the
        // single source of truth for panel geometry.
        if #available(macOS 13.3, *) {
            hostingView.sizingOptions = []
        }
        contentView = hostingView
        setContentSize(CGSize(width: initialPanelWidth, height: measuredPanelHeight(for: initialPanelWidth)))
    }

    /// Updates the locale environment used by the floating panel content.
    func updateLocaleIdentifier(_ localeIdentifier: String?) {
        guard self.localeIdentifier != localeIdentifier else { return }
        self.localeIdentifier = localeIdentifier
        guard let panelController else { return }
        let panelView = Self.makePanelView(controller: panelController, localeIdentifier: localeIdentifier)
        hostingView.rootView = panelView
        sizingView.rootView = panelView
        cachedMeasureWidth = nil
        cachedMeasureHeight = nil
        setContentSize(CGSize(width: frame.width, height: measuredPanelHeight(for: frame.width)))
    }

    /// The panel intentionally stays non-activating so System Settings remains
    /// the visible focus owner underneath it.
    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    /// If the system temporarily tries to key this panel, immediately ask the
    /// controller to keep System Settings visually frontmost underneath it.
    override func becomeKey() {
        super.becomeKey()
        panelController?.keepSettingsVisible()
    }

    /// Mirrors becomeKey() for main-window promotion attempts so the helper
    /// remains non-disruptive to the actual System Settings interaction.
    override func becomeMain() {
        super.becomeMain()
        panelController?.keepSettingsVisible()
    }

    /// Keeps System Settings visually present when the panel receives a mouse
    /// down event, while still forwarding the event through normal handling.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            panelController?.keepSettingsVisible()
        }
        super.sendEvent(event)
    }

    /// Shows the panel at its current frame without any positioning changes.
    func show() {
        orderFrontRegardless()
    }

    /// Displays the panel at the source frame used to start the launch motion.
    /// This is used before the target System Settings frame is known.
    func show(at sourceFrameInScreen: CGRect) {
        stopLaunchAnimation()
        isAnimatingLaunch = false
        alphaValue = 1
        setContentSize(CGSize(width: frame.width, height: measuredPanelHeight(for: frame.width)))
        // Lightweight first paint at source — avoid display:true flash.
        setFrame(launchSourceFrame(for: sourceFrameInScreen), display: false)
        orderFrontRegardless()
    }

    /// Animates the panel from the triggering UI element toward the current
    /// System Settings window frame once the destination becomes available.
    func present(from sourceFrameInScreen: CGRect, to settingsFrame: CGRect) {
        stopLaunchAnimation()
        let targetFrame = targetFrame(for: settingsFrame)
        launchToFrame = targetFrame

        guard sourceFrameInScreen.isEmpty == false else {
            isAnimatingLaunch = false
            alphaValue = 1
            setFrame(targetFrame, display: false)
            orderFrontRegardless()
            return
        }

        isAnimatingLaunch = true
        let from = launchSourceFrame(for: sourceFrameInScreen)
        alphaValue = initialAlpha
        setFrame(from, display: false)
        orderFrontRegardless()

        // AppKit window animator is display-synced and avoids Timer→Task hops.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
            animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAnimatingLaunch = false
                // Honor any destination updates that arrived mid-flight.
                self.setFrame(self.launchToFrame, display: false)
                self.alphaValue = 1
            }
        })
    }

    /// Switches the panel into a drag-friendly mode where mouse events pass
    /// through so System Settings can receive the drop destination interaction.
    func setDraggingPassthrough(_ isDragging: Bool) {
        ignoresMouseEvents = isDragging
        alphaValue = isDragging ? 0.72 : 1.0
        if isDragging {
            orderBack(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// Repositions the panel under the latest tracked System Settings frame.
    /// While the launch animation is still running, only the destination is
    /// updated so the motion stays continuous.
    func snap(to settingsFrame: CGRect) {
        let target = targetFrame(for: settingsFrame)
        if isAnimatingLaunch {
            // Tracking updates can arrive during the launch. Updating the final
            // destination preserves the motion instead of abruptly snapping.
            launchToFrame = target
            return
        }

        stopLaunchAnimation()
        // Avoid display:true — SwiftUI hosting already redraws as needed.
        setFrame(target, display: false)
        orderFrontRegardless()
    }

    /// Calculates the final panel frame relative to the System Settings window.
    /// The panel aligns to the trailing content area, stays underneath the
    /// window, and is clamped to the visible frame of the matching screen.
    private func targetFrame(for settingsFrame: CGRect) -> CGRect {
        let screenFrame = NSScreen.screens
            .first(where: { $0.frame.intersects(settingsFrame) })?
            .visibleFrame ?? settingsFrame

        // The helper panel is anchored to the trailing content area of System
        // Settings rather than the full window width because the leading
        // sidebar is not the user's active target.
        let contentMinX = settingsFrame.minX + sidebarWidth
        let availableContentWidth = max(240, settingsFrame.width - sidebarWidth)
        let width = min(availableContentWidth, screenFrame.width - (screenInset * 2))
        let height = measuredPanelHeight(for: width)

        // This is the place to tune visual attachment if the panel feels too
        // far from the bottom edge of System Settings.
        //
        // Current behavior:
        //   y = settingsFrame.minY - height
        // means "place the panel immediately below the tracked window frame".
        //
        // If the tracked frame still includes some visual framing/shadow, the
        // panel will look separated by that amount. A manual tweak such as:
        //
        //   y = settingsFrame.minY - height + 28
        //
        // is effectively saying "treat the bottom 28pt as non-visual spacing
        // and pull the panel upward".
        //
        // This is usually a better place for that adjustment than
        // SettingsWindowTracker.appKitScreenFrame(...), because the intent here
        // is clearly visual alignment of the floating panel, not coordinate
        // conversion of the tracked window.
        var origin = CGPoint(
            x: contentMinX,
            y: settingsFrame.minY - height
        )

        origin.x = max(screenFrame.minX + screenInset, min(origin.x, screenFrame.maxX - width - screenInset))
        origin.y = max(screenFrame.minY + screenInset, min(origin.y, screenFrame.maxY - height - screenInset))

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// Builds the starting frame for the launch animation around the source UI
    /// element that initiated the permission flow.
    private func launchSourceFrame(for sourceFrameInScreen: CGRect) -> CGRect {
        let launchSize = CGSize(
            width: max(sourceFrameInScreen.width, frame.width * minimumLaunchScale),
            height: max(sourceFrameInScreen.height, frame.height * minimumLaunchScale)
        )
        let center = CGPoint(x: sourceFrameInScreen.midX, y: sourceFrameInScreen.midY)
        return CGRect(
            x: center.x - (launchSize.width * 0.5),
            y: center.y - (launchSize.height * 0.5),
            width: launchSize.width,
            height: launchSize.height
        )
    }

    /// Measures the SwiftUI content at a specific width so the panel height can
    /// fit its dynamic contents before being positioned or animated.
    private func measuredPanelHeight(for width: CGFloat) -> CGFloat {
        if let cachedMeasureWidth, let cachedMeasureHeight,
           abs(cachedMeasureWidth - width) < 0.5 {
            return cachedMeasureHeight
        }
        sizingView.setFrameSize(NSSize(width: width, height: sizingHeightLimit))
        sizingView.layoutSubtreeIfNeeded()
        let height = max(minimumPanelHeight, sizingView.fittingSize.height)
        cachedMeasureWidth = width
        cachedMeasureHeight = height
        return height
    }

    /// Cancels any in-flight AppKit launch animation.
    private func stopLaunchAnimation() {
        // Removing animations mid-flight freezes the panel at its current frame.
        if isAnimatingLaunch {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            animator().setFrame(frame, display: false)
            NSAnimationContext.endGrouping()
        }
        isAnimatingLaunch = false
    }

    private static func makePanelView(
        controller: PermissionFlowController,
        localeIdentifier: String?
    ) -> AnyView {
        let view = PermissionFlowPanelView(controller: controller)
        guard let localeIdentifier else { return AnyView(view) }
        return AnyView(view.environment(\.locale, .init(identifier: localeIdentifier)))
    }
}
#endif
