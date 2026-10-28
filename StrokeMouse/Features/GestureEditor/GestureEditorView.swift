import SwiftUI

struct GestureEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var profile: GestureProfile
    @State private var actionKind: ActionKind
    @State private var isSecondaryActionEnabled: Bool
    @State private var secondaryActionKind: ActionKind
    /// Kept while the toggle is off so re-enabling restores the draft.
    @State private var secondaryActionDraft: GestureAction
    @State private var scopeMode: AppScopeMode = .global
    @State private var scopeBundleIds: [String] = []
    @State private var scopeGroupID: UUID?
    @State private var sampleState: GestureSampleEditorState
    @State private var captureSuppression: GestureCaptureSuppression?

    var onSave: (GestureProfile) -> Void
    var onCancel: () -> Void

    enum ActionKind: String, CaseIterable, Identifiable {
        case none, shortcut, system, openApp, openURL, shell, media, window, appleScript
        var id: String { rawValue }
        var titleKey: String { "action.\(rawValue)" }
    }

    init(profile: GestureProfile, onSave: @escaping (GestureProfile) -> Void, onCancel: @escaping () -> Void) {
        _profile = State(initialValue: profile)
        let paths: [[CodablePoint]]
        if case .drawn(let drawn) = profile.input {
            paths = drawn.allPaths
        } else {
            paths = []
        }
        _sampleState = State(initialValue: GestureSampleEditorState(paths: paths))
        _actionKind = State(initialValue: ActionKind.from(profile.action))
        let secondaryAction = profile.secondaryAction ?? .none
        _isSecondaryActionEnabled = State(initialValue: profile.secondaryAction != nil)
        _secondaryActionKind = State(initialValue: ActionKind.from(secondaryAction))
        _secondaryActionDraft = State(initialValue: secondaryAction)
        switch profile.scope {
        case .global:
            _scopeMode = State(initialValue: .global)
            _scopeBundleIds = State(initialValue: [])
        case .group(let groupID):
            _scopeMode = State(initialValue: .group)
            _scopeGroupID = State(initialValue: groupID)
        case .apps(let ids):
            _scopeMode = State(initialValue: .apps)
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
                sampleState: $sampleState
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
                if isDragScroll {
                    Text(L10n.string("editor.dragScrollActionHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ActionPickerView(kind: $actionKind, action: $profile.action)
                }
                if !isDragScroll, profile.action.requiresCapturedTarget {
                    Text(L10n.string("editor.testActionNeedsTarget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if GestureProfile.supportsSecondaryAction(profile.input) {
                secondaryActionSection
            }

            Section(L10n.string("editor.target")) {
                if isDragScroll {
                    Text(L10n.string("editor.dragScrollTargetHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        L10n.string("editor.targetWindow"),
                        selection: $profile.targetPolicy
                    ) {
                        ForEach(GestureTargetPolicy.allCases) { policy in
                            Text(L10n.string(policy.displayKey))
                                .tag(policy)
                        }
                    }
                    Text(L10n.string(usesSystemNavigation ? "editor.systemNavigationTargetHelp" : targetHelpKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !isDragScroll, profile.targetPolicy == .windowUnderPointer,
                   usesShortcutAction
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
                AppScopeEditorView(
                    mode: $scopeMode,
                    bundleIds: $scopeBundleIds,
                    groupID: $scopeGroupID,
                    groups: appState.configStore.appGroups
                )
            }

            Section(L10n.string("editor.notes")) {
                TextField(L10n.string("editor.notes"), text: $profile.notes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .formStyle(.grouped)
    }

    private var secondaryActionSection: some View {
        Section(L10n.string("editor.secondaryAction")) {
            Toggle(
                L10n.string("editor.secondaryActionToggle"),
                isOn: $isSecondaryActionEnabled
            )
            Text(L10n.string("editor.secondaryActionHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if isSecondaryActionEnabled {
                ActionPickerView(
                    kind: $secondaryActionKind,
                    action: $secondaryActionDraft
                )
                if case .drawn(let drawn) = profile.input,
                   drawn.trackpadModifierKey != nil
                {
                    Text(L10n.string("editor.secondaryActionModifierHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if secondaryActionDraft.requiresCapturedTarget {
                    Text(L10n.string("editor.testActionNeedsTarget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(L10n.string("editor.testSecondaryAction")) {
                        testAction(secondaryActionDraft)
                    }
                }
            }
        }
    }

    /// Shortcuts, including Application Windows, bring the captured target forward first.
    private var usesShortcutAction: Bool {
        actionKind == .shortcut || postsToCapturedTarget(profile.action)
            || (isSecondaryActionEnabled
                && GestureProfile.supportsSecondaryAction(profile.input)
                && (secondaryActionKind == .shortcut || postsToCapturedTarget(secondaryActionDraft)))
    }

    private func postsToCapturedTarget(_ action: GestureAction) -> Bool {
        if case .system(let system) = action { return system.command.requiresCapturedTarget }
        return false
    }

    private func testAction(_ action: GestureAction) {
        Task { @MainActor in
            do {
                try await appState.actionExecutor.executeForTesting(action)
            } catch {
                GestureToastController.shared.showActionError(
                    error.localizedDescription
                )
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Button(L10n.string("common.cancel")) { onCancel() }
                .keyboardShortcut(.cancelAction)
            if let saveBlocker {
                Text(saveBlocker)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 8)
            }
            Spacer()
            Button(L10n.string("common.testAction")) {
                testAction(profile.action)
            }
            .disabled(isDragScroll || profile.action.requiresCapturedTarget)
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
            guard let primary = sampleState.samples.first else { return }
            drawn.points = primary
            drawn.additionalPaths = Array(sampleState.samples.dropFirst())
            profile.input = .drawn(drawn)
        }
        profile.secondaryAction = isSecondaryActionEnabled
            && GestureProfile.supportsSecondaryAction(profile.input)
            ? secondaryActionDraft
            : nil
        guard let draftScope else { return }
        profile.scope = draftScope
        if isDragScroll {
            profile.action = .none
            profile.secondaryAction = nil
            profile.targetPolicy = .windowUnderPointer
        }
        onSave(profile)
    }

    private var canSave: Bool { saveBlocker == nil }

    /// Localized reason saving is disabled.
    private var saveBlocker: String? {
        if case .drawn = profile.input, !sampleState.canSave {
            return L10n.string("editor.saveNeedsPath")
        }
        if scopeMode == .group,
           !appState.configStore.appGroups.contains(where: { $0.id == scopeGroupID })
        {
            return L10n.string("editor.saveNeedsGroup")
        }
        if let draftScope {
            let conflicts = MouseMovementConflict.conflicts(
                of: profile, scope: draftScope,
                in: appState.configStore.gestures
            )
            if !conflicts.isEmpty { return MouseMovementConflict.conflictMessage(conflicts) }
        }
        return nil
    }

    private var draftScope: AppScope? {
        switch scopeMode {
        case .global: return .global
        case .apps: return .apps(scopeBundleIds)
        case .group: return scopeGroupID.map(AppScope.group)
        }
    }

    private var isDragScroll: Bool { MouseMovementConflict.isDragScroll(profile.input) }

    private var usesSystemNavigation: Bool {
        if case .system(let system) = profile.action {
            return system.command != .applicationWindows
        }
        return false
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
        case .shortcut, .shortcutSequence: return .shortcut
        case .system: return .system
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .shell: return .shell
        case .media: return .media
        case .window: return .window
        case .applicationSwitch: return .window
        case .appleScript: return .appleScript
        }
    }
}
