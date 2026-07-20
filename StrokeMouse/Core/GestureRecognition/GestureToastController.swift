import AppKit
import SwiftUI

/// Bottom-centered toast for gesture match / miss feedback.
@MainActor
final class GestureToastController {
    static let shared = GestureToastController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func showMatched(name: String, score: Double) {
        let pct = Int((score * 100).rounded())
        let text = String(format: L10n.string("toast.matched"), locale: L10n.locale, name, pct)
        present(text: text, isSuccess: true)
    }

    func showNoMatch() {
        present(text: L10n.string("toast.noMatch"), isSuccess: false)
    }

    func showTooShort() {
        present(text: L10n.string("toast.tooShort"), isSuccess: false)
    }

    func showActionError(_ message: String) {
        present(text: message, isSuccess: false)
    }

    private func present(text: String, isSuccess: Bool) {
        hideWorkItem?.cancel()

        let root = ToastBannerView(text: text, isSuccess: isSuccess)
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        // Measure intrinsic single-line size (no artificial min width that forces wrap).
        let fitting = hosting.fittingSize
        let size = NSSize(
            width: ceil(fitting.width) + 2,
            height: ceil(fitting.height) + 2
        )
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(size)
        // Avoid boxy system chrome around the pill.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        positionBottomCenter(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        return panel
    }

    private func positionBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 36
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ToastBannerView: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSuccess ? Color.green : Color.secondary)
                .fixedSize()

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        // No strokeBorder — avoids the outer dark rectangular frame.
    }
}
