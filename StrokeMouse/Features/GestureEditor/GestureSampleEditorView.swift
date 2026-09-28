import SwiftUI

struct GestureSampleEditorView: View {
    @Binding var state: GestureSampleEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectedPreview
            sampleStrip
            controls
            Text(L10n.string("editor.samples.recommendation"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: recordingPresented) {
            recordingSheet
        }
    }

    @ViewBuilder
    private var selectedPreview: some View {
        if let path = state.selectedPath {
            GestureSamplePathPreview(path: path, padding: 20)
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.string("editor.samples.empty"))
                    .font(.headline)
                Button(L10n.string("editor.samples.recordFirst")) {
                    state.beginAppend()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private var sampleStrip: some View {
        if !state.samples.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(state.samples.indices, id: \.self) { index in
                        GestureSampleThumbnail(
                            path: state.samples[index],
                            index: index,
                            isSelected: index == state.selectedIndex,
                            onSelect: { state.select(index) }
                        )
                    }
                }
            }
            .frame(height: 88)
            .scrollIndicators(.hidden)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(L10n.string("editor.samples.add"), systemImage: "plus") {
                state.beginAppend()
            }
            .disabled(!state.canAppend)

            Button(L10n.string("editor.samples.rerecord"), systemImage: "arrow.counterclockwise") {
                state.beginReplaceSelected()
            }
            .disabled(state.selectedIndex == nil)

            Menu {
                Button(L10n.string("editor.samples.makePrimary"), systemImage: "star") {
                    state.promoteSelected()
                }
                .disabled(state.selectedIndex == nil || state.selectedIndex == 0)
                Divider()
                Button(
                    L10n.string("editor.samples.delete"),
                    systemImage: "trash",
                    role: .destructive
                ) {
                    state.deleteSelected()
                }
                .disabled(state.selectedIndex == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
            Text("\(state.samples.count)/\(DrawnGesture.maximumSampleCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var recordingSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string(recordingTitleKey))
                .font(.title2.bold())
            GestureRecorderView(path: pendingPath)
                .frame(minWidth: 520, minHeight: 360)
            HStack {
                Button(L10n.string("common.cancel")) {
                    state.cancelRecording()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("editor.samples.useRecording")) {
                    state.commitRecording()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.pendingPath.count < 2)
            }
        }
        .padding(20)
        .interactiveDismissDisabled()
    }

    private var recordingTitleKey: String {
        switch state.recordingTarget {
        case .replace: return "editor.samples.rerecordTitle"
        default: return "editor.samples.addTitle"
        }
    }

    private var pendingPath: Binding<[CodablePoint]> {
        Binding(
            get: { state.pendingPath },
            set: { state.updatePendingPath($0) }
        )
    }

    private var recordingPresented: Binding<Bool> {
        Binding(
            get: { state.recordingTarget != nil },
            set: { isPresented in
                if !isPresented { state.cancelRecording() }
            }
        )
    }
}

private struct GestureSampleThumbnail: View {
    let path: [CodablePoint]
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                GestureSamplePathPreview(path: path, padding: 7)
                    .frame(width: 68, height: 52)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var title: String {
        index == 0 ? L10n.string("editor.samples.primary") : "\(index + 1)"
    }

    private var accessibilityTitle: String {
        index == 0
            ? L10n.string("editor.samples.primary")
            : "\(L10n.string("editor.samples.sample")) \(index + 1)"
    }

    private var backgroundColor: Color {
        isSelected
            ? Color.accentColor.opacity(0.16)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor : Color(nsColor: .separatorColor)
    }
}

private struct GestureSamplePathPreview: View {
    let path: [CodablePoint]
    let padding: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let safePadding = max(padding, 12)
            let points = GesturePreviewGeometry.aspectFit(
                points: path.map(\.cgPoint),
                in: geometry.size,
                padding: safePadding
            )
            ZStack {
                Path { line in
                    guard let first = points.first else { return }
                    line.move(to: first)
                    points.dropFirst().forEach { line.addLine(to: $0) }
                }
                .stroke(
                    DrawingStyle.lineSwiftUIColor,
                    style: StrokeStyle(
                        lineWidth: DrawingStyle.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if let start = points.first {
                    Circle()
                        .fill(DrawingStyle.startSwiftUIColor)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        .position(start)
                }

                terminalArrow(points)
                    .stroke(
                        DrawingStyle.lineSwiftUIColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func terminalArrow(_ points: [CGPoint]) -> Path {
        var arrow = Path()
        guard points.count >= 2, let end = points.last else { return arrow }
        var previousIndex = points.count - 2
        while previousIndex > 0,
              hypot(end.x - points[previousIndex].x, end.y - points[previousIndex].y) < 5
        {
            previousIndex -= 1
        }
        let previous = points[previousIndex]
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        let length: CGFloat = 9
        for offset in [-CGFloat.pi * 0.82, CGFloat.pi * 0.82] {
            arrow.move(to: end)
            arrow.addLine(to: CGPoint(
                x: end.x + cos(angle + offset) * length,
                y: end.y + sin(angle + offset) * length
            ))
        }
        return arrow
    }
}
