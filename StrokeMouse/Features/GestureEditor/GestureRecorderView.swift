import AppKit
import SwiftUI

struct GestureRecorderView: View {
    @Binding var path: [CodablePoint]
    var onRecordedPath: (([CGPoint]) -> Void)?
    @State private var draft: [CGPoint] = []
    @State private var isDrawing = false

    init(
        path: Binding<[CodablePoint]>,
        onRecordedPath: (([CGPoint]) -> Void)? = nil
    ) {
        _path = path
        self.onRecordedPath = onRecordedPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let points: [CGPoint] = {
                    if !draft.isEmpty { return draft }
                    return displayPoints(in: geo.size)
                }()
                // Only show the center hint when canvas is empty (no saved path, not drawing).
                let showHint = path.isEmpty && !isDrawing && draft.isEmpty

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)

                    // Stroke
                    Path { p in
                        guard let first = points.first else { return }
                        p.move(to: first)
                        for point in points.dropFirst() {
                            p.addLine(to: point)
                        }
                    }
                    .stroke(
                        DrawingStyle.lineSwiftUIColor,
                        style: StrokeStyle(lineWidth: DrawingStyle.lineWidth, lineCap: .round, lineJoin: .round)
                    )

                    // Start point (red)
                    if DrawingStyle.showStartPoint, let start = points.first {
                        Circle()
                            .fill(DrawingStyle.startSwiftUIColor)
                            .frame(width: DrawingStyle.startPointRadius * 2, height: DrawingStyle.startPointRadius * 2)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white)
                                    .frame(
                                        width: max(DrawingStyle.startPointRadius * 0.7, 3),
                                        height: max(DrawingStyle.startPointRadius * 0.7, 3)
                                    )
                            )
                            .position(start)
                    }

                    // Live head while drawing
                    if isDrawing, let last = points.last {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(DrawingStyle.lineSwiftUIColor, lineWidth: 2))
                            .position(last)
                    }

                    // Center hint: left mouse button — only when empty
                    if showHint {
                        VStack(spacing: 10) {
                            Image(systemName: "computermouse.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.hierarchical)

                            Text(L10n.string("editor.recordUseLeftButtonTitle"))
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.center)

                            Text(L10n.string("editor.recordUseLeftButtonBody"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)

                            Text(L10n.string("editor.recordUseLeftButtonBadge"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                        )
                        .allowsHitTesting(false)
                    }

                    // Capture right-button (primary) and left-button drags via AppKit.
                    RightButtonDrawCatcher(
                        isDrawing: $isDrawing,
                        draft: $draft,
                        onFinished: { points in
                            commitDraft(points)
                        }
                    )
                }
            }
            .frame(minHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(L10n.string("editor.startPointHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.string("editor.pointCount") + ": \(path.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.string("editor.clear")) {
                    path = []
                    draft = []
                }
            }
        }
    }

    private func commitDraft(_ draftPoints: [CGPoint]) {
        guard draftPoints.count >= 2 else {
            draft = []
            return
        }
        // View Y grows downward; live engine uses AppKit Y-up.
        let flipped = flipY(draftPoints)
        let simplified = PathSimplifier.simplify(flipped, epsilon: 2)
        let normalized = PathSimplifier.normalize(simplified)
        let sampled = PathSimplifier.resample(normalized, count: Constants.freePathSampleCount)
        path = sampled.map(CodablePoint.init)
        onRecordedPath?(flipped)
        draft = []
    }

    /// Map stored Y-up unit points into view coordinates (Y-down).
    private func displayPoints(in size: CGSize) -> [CGPoint] {
        let pts = path.map(\.cgPoint)
        return GesturePreviewGeometry.aspectFit(points: pts, in: size, padding: 16)
    }

    private func flipY(_ points: [CGPoint]) -> [CGPoint] {
        guard let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return points }
        return points.map { CGPoint(x: $0.x, y: maxY + minY - $0.y) }
    }
}

// MARK: - Right-button (and left) drag capture

/// AppKit view so right-mouse drag works (SwiftUI `DragGesture` only tracks left button).
private struct RightButtonDrawCatcher: NSViewRepresentable {
    @Binding var isDrawing: Bool
    @Binding var draft: [CGPoint]
    var onFinished: ([CGPoint]) -> Void

    func makeNSView(context: Context) -> DrawCatcherNSView {
        let view = DrawCatcherNSView()
        view.onBegin = { point in
            isDrawing = true
            draft = [point]
        }
        view.onMove = { point in
            draft.append(point)
        }
        view.onEnd = { points in
            isDrawing = false
            onFinished(points)
        }
        return view
    }

    func updateNSView(_ nsView: DrawCatcherNSView, context: Context) {
        nsView.onBegin = { point in
            isDrawing = true
            draft = [point]
        }
        nsView.onMove = { point in
            draft.append(point)
        }
        nsView.onEnd = { points in
            isDrawing = false
            onFinished(points)
        }
    }

    final class DrawCatcherNSView: NSView {
        var onBegin: ((CGPoint) -> Void)?
        var onMove: ((CGPoint) -> Void)?
        var onEnd: (([CGPoint]) -> Void)?

        private var points: [CGPoint] = []
        private var trackingLeft = false
        private var trackingRight = false

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true } // match SwiftUI top-left origin

        override func hitTest(_ point: NSPoint) -> NSView? { self }

        // Primary: left mouse button drag to record.
        override func mouseDown(with event: NSEvent) {
            begin(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard trackingLeft else { return }
            move(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            guard trackingLeft else { return }
            end()
        }

        private func begin(with event: NSEvent) {
            window?.makeFirstResponder(self)
            trackingLeft = true
            trackingRight = false
            let p = convert(event.locationInWindow, from: nil)
            points = [p]
            onBegin?(p)
        }

        private func move(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let last = points.last, hypot(p.x - last.x, p.y - last.y) < 1 { return }
            points.append(p)
            onMove?(p)
        }

        private func end() {
            let finished = points
            points = []
            trackingLeft = false
            trackingRight = false
            onEnd?(finished)
        }
    }
}
