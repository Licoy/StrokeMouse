import SwiftUI

struct GestureEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var profile: GestureProfile
    @State private var actionKind: ActionKind
    @State private var scopeIsGlobal = true
    @State private var scopeBundleIds: [String] = []
    @State private var pathPoints: [CodablePoint]
    @State private var captureSuppression: GestureCaptureSuppression?

    var onSave: (GestureProfile) -> Void
    var onCancel: () -> Void

    enum ActionKind: String, CaseIterable, Identifiable {
        case none, shortcut, openApp, openURL, shell, media, window, appleScript
        var id: String { rawValue }
        var titleKey: String { "action.\(rawValue)" }
    }

    init(profile: GestureProfile, onSave: @escaping (GestureProfile) -> Void, onCancel: @escaping () -> Void) {
        _profile = State(initialValue: profile)
        let points: [CodablePoint]
        if case .drawn(let drawn) = profile.input {
            points = drawn.points
        } else {
            points = []
        }
        _pathPoints = State(initialValue: points)
        _actionKind = State(initialValue: ActionKind.from(profile.action))
        switch profile.scope {
        case .global:
            _scopeIsGlobal = State(initialValue: true)
            _scopeBundleIds = State(initialValue: [])
        case .apps(let ids):
            _scopeIsGlobal = State(initialValue: false)
            // Preserve order, drop empties/duplicates.
            var seen = Set<String>()
            var unique: [String] = []
            for id in ids {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                unique.append(trimmed)
            }
            _scopeBundleIds = State(initialValue: unique)
        }
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                patternPane
                    .frame(width: 340)
                Divider()
                settingsForm
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerBar
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            // Pause global capture/HUD so recording does not trigger gestures.
            guard captureSuppression == nil else { return }
            captureSuppression = appState.gestureRuntime.suppress(
                reason: .gestureEditor
            )
        }
        .onDisappear {
            captureSuppression?.release()
            captureSuppression = nil
        }
    }

    /// Left pane: how the gesture is triggered — mouse button + drawn path,
    /// always visible while the rest of the form is edited.
    private var patternPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("editor.pattern"))
                .font(.headline)

            GestureInputEditorView(
                input: $profile.input,
                pathPoints: $pathPoints
            )
            .frame(maxHeight: .infinity)
        }
        .padding(16)
    }

    private var settingsForm: some View {
        Form {
            Section(L10n.string("editor.basic")) {
                TextField(L10n.string("editor.name"), text: $profile.name)
                Toggle(L10n.string("editor.enabled"), isOn: $profile.isEnabled)
            }

            Section(L10n.string("editor.action")) {
                ActionPickerView(kind: $actionKind, action: $profile.action)
                if profile.action.requiresCapturedTarget {
                    Text(L10n.string("editor.testActionNeedsTarget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.string("editor.target")) {
                Picker(
                    L10n.string("editor.targetWindow"),
                    selection: $profile.targetPolicy
                ) {
                    ForEach(GestureTargetPolicy.allCases) { policy in
                        Text(L10n.string(policy.displayKey))
                            .tag(policy)
                    }
                }
                Text(L10n.string(targetHelpKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile.targetPolicy == .windowUnderPointer,
                   actionKind == .shortcut
                {
                    Label(
                        L10n.string("editor.targetPointerShortcutWarning"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section(L10n.string("editor.scope")) {
                AppScopeEditorView(isGlobal: $scopeIsGlobal, bundleIds: $scopeBundleIds)
            }

            Section(L10n.string("editor.notes")) {
                TextField(L10n.string("editor.notes"), text: $profile.notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .formStyle(.grouped)
    }

    private var footerBar: some View {
        HStack {
            Button(L10n.string("common.cancel")) { onCancel() }
                .keyboardShortcut(.cancelAction)
            if !canSave {
                Text(L10n.string("editor.saveNeedsPath"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 8)
            }
            Spacer()
            Button(L10n.string("common.testAction")) {
                Task { @MainActor in
                    do {
                        try await appState.actionExecutor.executeForTesting(profile.action)
                    } catch {
                        GestureToastController.shared.showActionError(
                            error.localizedDescription
                        )
                    }
                }
            }
            .disabled(profile.action.requiresCapturedTarget)
            Button(L10n.string("common.save")) {
                commitAndSave()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding()
    }

    private func commitAndSave() {
        if case .drawn(var drawn) = profile.input {
            drawn.points = pathPoints
            profile.input = .drawn(drawn)
        }
        if scopeIsGlobal {
            profile.scope = .global
        } else {
            profile.scope = .apps(scopeBundleIds)
        }
        onSave(profile)
    }

    private var canSave: Bool {
        switch profile.input {
        case .drawn:
            return pathPoints.count >= 2
        case .trackpad:
            return true
        }
    }

    private var targetHelpKey: String {
        switch profile.targetPolicy {
        case .frontmostWindow:
            return "editor.targetHelp.frontmostWindow"
        case .windowUnderPointer:
            return "editor.targetHelp.windowUnderPointer"
        }
    }
}

private extension GestureEditorView.ActionKind {
    static func from(_ action: GestureAction) -> Self {
        switch action {
        case .none: return .none
        case .shortcut: return .shortcut
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .shell: return .shell
        case .media: return .media
        case .window: return .window
        case .appleScript: return .appleScript
        }
    }
}
