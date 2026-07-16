import AppKit
import SwiftUI

struct GestureTestView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var previewPath: [CodablePoint] = []
    @State private var selectedButton: MouseTriggerButton = .right
    @State private var evaluation: GestureRecognitionEvaluation?
    @State private var rawPointCount = 0
    @State private var sessionID = UUID()
    @State private var isSuppressingGlobalRecognition = false
    @State private var didSaveLog = false
    @State private var logError: String?

    private let logStore = GestureTestLogStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                drawingPanel
                resultPanel
                    .frame(width: 330)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            logFooter
        }
        .padding(20)
        .frame(minWidth: 860, idealWidth: 920, minHeight: 580, idealHeight: 640)
        .onAppear(perform: beginSession)
        .onDisappear(perform: endSession)
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
                Label(L10n.string("gestureTest.globalPaused"), systemImage: "pause.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }

            Picker(L10n.string("gestureTest.trigger"), selection: $selectedButton) {
                ForEach(MouseTriggerButton.allCases) { button in
                    Text(L10n.string(button.displayKey)).tag(button)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)
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

    private var resultPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let evaluation {
                    decisionView(evaluation)
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

    private func decisionView(_ result: GestureRecognitionEvaluation) -> some View {
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

    private func beginSession() {
        guard !isSuppressingGlobalRecognition else { return }
        if let firstEnabled = appState.configStore.gestures.first(where: \.isEnabled) {
            selectedButton = firstEnabled.trigger.button
        }
        appState.gestureEngine.pushSuppression()
        isSuppressingGlobalRecognition = true
    }

    private func endSession() {
        guard isSuppressingGlobalRecognition else { return }
        appState.gestureEngine.popSuppression()
        isSuppressingGlobalRecognition = false
    }

    private func evaluateAndLog(_ rawPath: [CGPoint]) {
        rawPointCount = rawPath.count
        let result = appState.gestureEngine.evaluateForTesting(
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
}
