import AppKit
import SwiftUI

private enum GestureTestInputMode: String, CaseIterable, Identifiable {
    case mouseDraw
    case modifierDraw
    case directTrackpad

    var id: String { rawValue }
    var titleKey: String { "gestureTest.input.\(rawValue)" }
}

struct GestureTestView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var previewPath: [CodablePoint] = []
    @State private var selectedButton: MouseTriggerButton = .right
    @State private var inputMode: GestureTestInputMode = .mouseDraw
    @State private var evaluation: GestureRecognitionEvaluation?
    @State private var rawPointCount = 0
    @State private var sessionID = UUID()
    @State private var diagnosticSession: GestureDiagnosticSession?
    @State private var didSaveLog = false
    @State private var logError: String?
    @AppStorage(PreferenceKey.directTrackpadEnabled)
    private var directTrackpadEnabled = true

    private let logStore = GestureTestLogStore()
    private let optionLabelWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            testContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 860, idealWidth: 920, minHeight: 580, idealHeight: 640)
        .onAppear(perform: beginSession)
        .onDisappear(perform: endSession)
        .onChange(of: inputMode) { _, _ in
            previewPath = []
            evaluation = nil
            rawPointCount = 0
        }
        .onChange(of: selectedButton) { _, _ in
            previewPath = []
            evaluation = nil
            rawPointCount = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("gestureTest.title"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.string("gestureTest.subtitle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    L10n.string("gestureTest.diagnosticsActive"),
                    systemImage: "waveform.path.ecg"
                )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }

            labeledSegmentedPicker(
                title: L10n.string("gestureTest.inputMode"),
                selection: $inputMode,
                maxControlWidth: 680
            ) {
                ForEach(GestureTestInputMode.allCases) { mode in
                    Text(L10n.string(mode.titleKey)).tag(mode)
                }
            }

            switch inputMode {
            case .mouseDraw:
                labeledSegmentedPicker(
                    title: L10n.string("gestureTest.trigger"),
                    selection: $selectedButton,
                    maxControlWidth: 560
                ) {
                    ForEach(MouseTriggerButton.allCases) { button in
                        Text(L10n.string(button.displayKey)).tag(button)
                    }
                }
            case .modifierDraw:
                Label(
                    L10n.string("gestureTest.modifierInstruction"),
                    systemImage: "keyboard"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            case .directTrackpad:
                Label(
                    L10n.string("gestureTest.directInstruction"),
                    systemImage: "hand.tap"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledSegmentedPicker<
        SelectionValue: Hashable,
        Content: View
    >(
        title: String,
        selection: Binding<SelectionValue>,
        maxControlWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: optionLabelWidth, alignment: .leading)
            Picker(title, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: maxControlWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var testContent: some View {
        switch inputMode {
        case .mouseDraw:
            HStack(alignment: .top, spacing: 16) {
                drawingPanel
                resultPanel
                    .frame(width: 330)
            }
        case .modifierDraw:
            HStack(alignment: .top, spacing: 16) {
                modifierDrawingPanel
                resultPanel
                    .frame(width: 330)
            }
        case .directTrackpad:
            trackpadResultPanel
        }
    }

    private var drawingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("gestureTest.canvas"))
                .font(.headline)
            GestureRecorderView(path: $previewPath) { rawPath in
                evaluateAndLog(rawPath)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modifierDrawingPanel: some View {
        let runtime = appState.gestureRuntime
        let path = isModifierSource(
            runtime.state.activeSession?.source
        )
            ? runtime.currentPath
            : (modifierDrawDiagnostic?.path ?? [])

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("gestureTest.trackpadDrawCanvas"))
                .font(.headline)
            GesturePathPreview(path: path)
                .frame(maxHeight: .infinity)

            if let diagnostic = modifierDrawDiagnostic {
                if let source = modifierSourceText(diagnostic.source) {
                    Label(source, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(
                    trackpadOutcomeText(diagnostic.outcome),
                    systemImage: trackpadOutcomeSymbol(diagnostic.outcome)
                )
                .font(.caption)
            } else {
                Text(L10n.string("gestureTest.trackpadDrawWaiting"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let evaluation = activeDrawEvaluation {
                    decisionView(
                        evaluation,
                        rawPointCount: activeDrawRawPointCount
                    )
                    Divider()
                    if evaluation.candidates.isEmpty {
                        Text(L10n.string("gestureTest.noCandidates"))
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(evaluation.candidates.enumerated()), id: \.element.profile.id) {
                                    index, candidate in
                                    candidateView(candidate, rank: index + 1)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        L10n.string("gestureTest.emptyResult"),
                        systemImage: "scribble.variable"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            Text(L10n.string("gestureTest.results"))
                .font(.headline)
        }
    }

    private var activeDrawEvaluation: GestureRecognitionEvaluation? {
        switch inputMode {
        case .mouseDraw:
            return evaluation
        case .modifierDraw:
            return modifierDrawDiagnostic?.evaluation
        case .directTrackpad:
            return nil
        }
    }

    private var activeDrawRawPointCount: Int {
        switch inputMode {
        case .mouseDraw:
            return rawPointCount
        case .modifierDraw:
            return modifierDrawDiagnostic?.path.count ?? 0
        case .directTrackpad:
            return 0
        }
    }

    private var trackpadResultPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TrackpadTouchPreview(
                    contacts: appState.gestureRuntime.currentTouches
                )
                .frame(height: 104)

                if let metrics = appState.gestureRuntime.lastTrackpadMetrics {
                    Text(
                        String(
                            format: L10n.string("gestureTest.trackpadMetrics"),
                            locale: L10n.locale,
                            metrics.fingerCount,
                            metrics.translationX,
                            metrics.translationY,
                            metrics.scale,
                            metrics.rotationRadians * 180 / .pi
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                if !directTrackpadEnabled {
                    Text(L10n.string(
                        "gestureTest.trackpadDisabled"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let outcome = appState.gestureRuntime
                    .lastTrackpadOutcome
                {
                    Label(
                        trackpadOutcomeText(outcome),
                        systemImage: trackpadOutcomeSymbol(outcome)
                    )
                    .font(.caption)
                } else {
                    Text(L10n.string("gestureTest.trackpadWaiting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(L10n.string("gestureTest.rawTouchesNotStored"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text(L10n.string("gestureTest.trackpadTitle"))
                .font(.headline)
        }
    }

    private func decisionView(
        _ result: GestureRecognitionEvaluation,
        rawPointCount: Int
    ) -> some View {
        let accepted = result.decision == .accepted
        return VStack(alignment: .leading, spacing: 4) {
            Label(
                L10n.string("gestureTest.decision.\(result.decision.rawValue)"),
                systemImage: accepted ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(accepted ? .green : .orange)

            Text(
                String(
                    format: L10n.string("gestureTest.pathMetrics"),
                    locale: L10n.locale,
                    Int(result.pathLength.rounded()),
                    rawPointCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                String(
                    format: L10n.string("gestureTest.policyMetrics"),
                    locale: L10n.locale,
                    Int((result.policy.matchThreshold * 100).rounded()),
                    Int((result.policy.minimumLeadOverSecond * 100).rounded())
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func candidateView(
        _ candidate: GestureCandidateEvaluation,
        rank: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(rank). \(candidate.profile.name)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(candidate.score, format: .percent.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            HStack(spacing: 12) {
                diagnosticMetric("gestureTest.matchScore", value: candidate.score)
                diagnosticMetric("gestureTest.shapeScore", value: candidate.shapeScore)
            }
            if let mode = candidate.diagnostics?.mode {
                Label(
                    L10n.string("gestureTest.matchMode.\(mode.rawValue)"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            if let mismatch = candidate.structuralMismatch {
                Label(
                    L10n.string("gestureTest.structure.\(mismatch.rawValue)"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.caption)
            } else {
                Label(L10n.string("gestureTest.structurePassed"), systemImage: "checkmark")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func diagnosticMetric(_ key: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(L10n.string(key))
            Text(value, format: .percent.precision(.fractionLength(1)))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var logFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    L10n.string(didSaveLog ? "gestureTest.logSaved" : "gestureTest.logPending"),
                    systemImage: didSaveLog ? "doc.badge.checkmark" : "doc.badge.plus"
                )
                .font(.callout)
                Spacer()
                Button(L10n.string("gestureTest.revealLog")) {
                    NSWorkspace.shared.activateFileViewerSelecting([logStore.logURL])
                }
                .disabled(!didSaveLog)
                Button(L10n.string("gestureTest.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            Text(logStore.logURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
            if let logError {
                Text(L10n.string("gestureTest.logError") + ": " + logError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if inputMode == .mouseDraw {
            logFooter
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.string("gestureTest.rawTouchesNotStored"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("gestureTest.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func beginSession() {
        guard diagnosticSession == nil else { return }
        if let firstEnabled = appState.configStore.gestures.first(where: {
            guard $0.isEnabled,
                  case .drawn(let drawn) = $0.input,
                  case .mouse = drawn.activation
            else {
                return false
            }
            return true
        }), case .drawn(let drawn) = firstEnabled.input,
            case .mouse(let trigger) = drawn.activation
        {
            selectedButton = trigger.button
        }
        diagnosticSession = appState.gestureRuntime.beginDiagnostics()
    }

    private func endSession() {
        diagnosticSession?.end()
        diagnosticSession = nil
    }

    private func evaluateAndLog(_ rawPath: [CGPoint]) {
        rawPointCount = rawPath.count
        let result = appState.gestureRuntime.evaluateForTesting(
            path: rawPath,
            button: selectedButton
        )
        evaluation = result
        let entry = GestureTestLogEntry(
            sessionID: sessionID,
            rawPath: rawPath,
            evaluation: result
        )
        do {
            try logStore.append(entry)
            didSaveLog = true
            logError = nil
        } catch {
            logError = error.localizedDescription
        }
    }

    private func trackpadOutcomeText(
        _ outcome: GestureRuntimeOutcome
    ) -> String {
        switch outcome {
        case .matched(let profileID, _):
            return appState.configStore.gestures.first {
                $0.id == profileID
            }?.name ?? L10n.string("gestureTest.trackpadMatched")
        case .noMatch:
            return L10n.string("gestureTest.trackpadNoMatch")
        case .conflict(let ids):
            return String(
                format: L10n.string("gestureTest.trackpadConflict"),
                locale: L10n.locale,
                ids.count
            )
        case .rejected(let reason):
            return L10n.string(reason.displayKey)
        case .cancelled:
            return L10n.string("gestureTest.trackpadCancelled")
        case .actionFailed(let detail):
            return detail
        }
    }

    private func trackpadOutcomeSymbol(
        _ outcome: GestureRuntimeOutcome
    ) -> String {
        switch outcome {
        case .matched: return "checkmark.circle.fill"
        case .noMatch, .cancelled: return "minus.circle"
        case .conflict, .rejected, .actionFailed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func modifierSourceText(
        _ source: GestureInputSource
    ) -> String? {
        guard case .modifier(let key) = source else { return nil }
        return String(
            format: L10n.string("gestureTest.trackpadDrawSource"),
            locale: L10n.locale,
            L10n.string(key.displayKey)
        )
    }

    private var modifierDrawDiagnostic: GestureDrawDiagnostic? {
        guard let diagnostic = appState.gestureRuntime.lastDrawDiagnostic,
              isModifierSource(diagnostic.source)
        else {
            return nil
        }
        return diagnostic
    }

    private func isModifierSource(_ source: GestureInputSource?) -> Bool {
        guard let source else { return false }
        if case .modifier = source { return true }
        return false
    }
}

private struct GesturePathPreview: View {
    let path: [CGPoint]

    var body: some View {
        GeometryReader { geometry in
            let displayPoints = GesturePreviewGeometry.aspectFit(
                points: path,
                in: geometry.size,
                padding: 18
            )
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, lineWidth: 1)
                Path { path in
                    guard let first = displayPoints.first else { return }
                    path.move(to: first)
                    for point in displayPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    DrawingStyle.lineSwiftUIColor,
                    style: StrokeStyle(
                        lineWidth: DrawingStyle.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                if let start = displayPoints.first {
                    Circle()
                        .fill(DrawingStyle.startSwiftUIColor)
                        .frame(
                            width: DrawingStyle.startPointRadius * 2,
                            height: DrawingStyle.startPointRadius * 2
                        )
                        .position(start)
                }
                if displayPoints.isEmpty {
                    Text(L10n.string("gestureTest.trackpadDrawWaiting"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrackpadTouchPreview: View {
    let contacts: [TrackpadTouchContact]

    var body: some View {
        Canvas { context, size in
            let background = Path(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: 10
            )
            context.fill(
                background,
                with: .color(Color.secondary.opacity(0.10))
            )
            for contact in contacts where contact.phase.isActive {
                let point = CGPoint(
                    x: min(size.width - 10, max(10, contact.position.x * size.width)),
                    y: min(size.height - 10, max(10, (1 - contact.position.y) * size.height))
                )
                let circle = Path(
                    ellipseIn: CGRect(
                        x: point.x - 8,
                        y: point.y - 8,
                        width: 16,
                        height: 16
                    )
                )
                context.fill(circle, with: .color(.accentColor.opacity(0.75)))
                context.draw(
                    Text("\(contact.id)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white),
                    at: point
                )
            }
        }
    }
}

private extension TrackpadGestureRejection {
    var displayKey: String {
        switch self {
        case .invalidFrame: return "gestureTest.reject.invalidFrame"
        case .interrupted: return "gestureTest.reject.interrupted"
        case .contactSetChanged: return "gestureTest.reject.contactSetChanged"
        case .landingSpreadExceeded:
            return "gestureTest.reject.landingSpreadExceeded"
        case .formingTimedOut: return "gestureTest.reject.formingTimedOut"
        case .releaseTimedOut: return "gestureTest.reject.releaseTimedOut"
        case .durationExceeded: return "gestureTest.reject.durationExceeded"
        case .unsupported: return "gestureTest.reject.unsupported"
        case .ambiguous: return "gestureTest.reject.ambiguous"
        }
    }
}
