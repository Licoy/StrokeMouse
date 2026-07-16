import SwiftUI

struct GestureEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var profile: GestureProfile
    @State private var actionKind: ActionKind
    @State private var scopeIsGlobal = true
    @State private var scopeBundleIds: [String] = []
    @State private var pathPoints: [CodablePoint]

    var onSave: (GestureProfile) -> Void
    var onCancel: () -> Void

    enum ActionKind: String, CaseIterable, Identifiable {
        case none, shortcut, openApp, openURL, shell, media, window, appleScript
        var id: String { rawValue }
        var titleKey: String { "action.\(rawValue)" }
    }

    init(profile: GestureProfile, onSave: @escaping (GestureProfile) -> Void, onCancel: @escaping () -> Void) {
        _profile = State(initialValue: profile)
        _pathPoints = State(initialValue: profile.pattern.freePathPoints)
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
            Form {
                Section(L10n.string("editor.basic")) {
                    TextField(L10n.string("editor.name"), text: $profile.name)
                    Toggle(L10n.string("editor.enabled"), isOn: $profile.isEnabled)
                    Picker(L10n.string("editor.trigger"), selection: $profile.trigger.button) {
                        ForEach(MouseTriggerButton.allCases) { button in
                            Text(L10n.string(button.displayKey))
                                .tag(button)
                        }
                    }
                    Text(L10n.string("editor.triggerPerGestureHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    GestureRecorderView(path: $pathPoints)
                        .frame(minHeight: 220)
                    Text(L10n.string("editor.freePathHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(L10n.string("editor.pattern"))
                }

                Section(L10n.string("editor.action")) {
                    ActionPickerView(kind: $actionKind, action: $profile.action)
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

            Divider()

            HStack {
                Button(L10n.string("common.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("common.testAction")) {
                    appState.actionExecutor.execute(profile.action)
                }
                Button(L10n.string("common.save")) {
                    commitAndSave()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(pathPoints.count < 2)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 560)
        .onAppear {
            // Pause global capture/HUD so recording does not trigger gestures.
            appState.gestureEngine.pushSuppression()
        }
        .onDisappear {
            appState.gestureEngine.popSuppression()
        }
    }

    private func commitAndSave() {
        profile.pattern = .freePath(pathPoints)
        if scopeIsGlobal {
            profile.scope = .global
        } else {
            profile.scope = .apps(scopeBundleIds)
        }
        onSave(profile)
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
