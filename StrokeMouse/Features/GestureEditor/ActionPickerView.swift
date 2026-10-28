import AppKit
import SwiftUI

private enum WindowActionSelection: Hashable, Identifiable {
    case window(WindowCommand)
    case applicationSwitch(ApplicationSwitchCommand)

    static let allCases: [WindowActionSelection] =
        WindowCommand.allCases.map(WindowActionSelection.window)
        + ApplicationSwitchCommand.allCases.map(WindowActionSelection.applicationSwitch)

    var id: String {
        switch self {
        case .window(let command):
            return "window.\(command.rawValue)"
        case .applicationSwitch(let command):
            return "applicationSwitch.\(command.rawValue)"
        }
    }

    var displayKey: String {
        switch self {
        case .window(let command):
            return command.displayKey
        case .applicationSwitch(let command):
            return command.displayKey
        }
    }

    var action: GestureAction {
        switch self {
        case .window(let command):
            return .window(command)
        case .applicationSwitch(let command):
            return .applicationSwitch(command)
        }
    }
}

struct ActionPickerView: View {
    @Binding var kind: GestureEditorView.ActionKind
    @Binding var action: GestureAction

    @State private var shortcutDisplay = ""
    @State private var keyCode: UInt16 = 0
    @State private var modifiers: UInt = 0
    @State private var orderedChord: ShortcutChord?
    /// Chords pressed in order after `orderedChord`.
    @State private var followingChords: [ShortcutChord] = []
    @State private var isRecordingFollowUp = false
    @State private var appBundleId = ""
    @State private var appName = ""
    @State private var urlString = "https://"
    @State private var shellCommand = "echo 'Hello from StrokeMouse'"
    @State private var mediaCommand: MediaCommand = .playPause
    @State private var windowActionSelection: WindowActionSelection = .window(.minimize)
    @State private var systemAction = SystemAction(command: .missionControl)
    @State private var appleScriptPreset: AppleScriptPreset = .sleep
    @State private var appleScript = AppleScriptPreset.sleep.source ?? ""
    /// Draft kept while the user is on a built-in so switching back to Custom restores it.
    @State private var customAppleScriptDraft = "display notification \"StrokeMouse\" with title \"Gesture\""
    @State private var isRecordingShortcut = false
    @State private var shortcutLivePreview = ""
    @State private var didHydrate = false
    @State private var releaseShortcutModifiers = false
    @State private var recorderFailed = false
    @State private var unsupportedShortcutModifier = false
    @State private var showOpenAppPicker = false

    private var isRecordingPrimaryShortcut: Bool {
        isRecordingShortcut && !isRecordingFollowUp
    }

    private var canAddFollowingChord: Bool {
        orderedChord != nil && 1 + followingChords.count < Constants.shortcutSequenceMaxSteps
    }

    @ViewBuilder
    private var shortcutSequenceEditor: some View {
        ForEach(Array(followingChords.enumerated()), id: \.offset) { index, chord in
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                Text(KeyCodeNames.shortcutDisplay(chord: chord))
                    .font(.body.monospaced())
                Spacer()
                Button {
                    removeFollowingChord(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("action.shortcutRemoveStep"))
            }
        }

        if isRecordingFollowUp {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                Text(shortcutLivePreview.isEmpty
                     ? L10n.string("action.shortcutListening")
                     : shortcutLivePreview)
                    .font(.body.monospaced())
                    .foregroundStyle(shortcutLivePreview.isEmpty ? .secondary : .primary)
                Spacer()
            }
        }

        HStack {
            Button {
                if isRecordingFollowUp {
                    stopRecording()
                } else {
                    startRecording(followUp: true)
                }
            } label: {
                Label(
                    L10n.string(isRecordingFollowUp ? "action.shortcutStop" : "action.shortcutAddStep"),
                    systemImage: isRecordingFollowUp ? "stop.circle" : "plus.circle"
                )
            }
            .disabled(!isRecordingFollowUp && !canAddFollowingChord)
            Spacer()
        }

        Text(String(
            format: L10n.string("action.shortcutSequenceHelp"),
            Constants.shortcutSequenceMaxSteps
        ))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var displayedShortcut: String {
        kind == .system ? KeyCodeNames.shortcutDisplay(chord: systemAction.effectiveChord) : shortcutDisplay
    }

    private var shortcutRecorderControl: some View {
        HStack(spacing: 10) {
            // Click-to-record field with live key feedback.
            Button {
                if isRecordingPrimaryShortcut {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 8) {
                    if isRecordingPrimaryShortcut {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                        Text(shortcutLivePreview.isEmpty
                             ? L10n.string("action.shortcutListening")
                             : shortcutLivePreview)
                            .font(.body.monospaced())
                            .foregroundStyle(shortcutLivePreview.isEmpty ? .secondary : .primary)
                    } else {
                        Text(displayedShortcut.isEmpty
                             ? L10n.string("action.shortcutEmpty")
                             : displayedShortcut)
                            .font(.body.monospaced())
                            .foregroundStyle(displayedShortcut.isEmpty ? .secondary : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecordingPrimaryShortcut
                          ? Color.accentColor.opacity(0.08)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isRecordingPrimaryShortcut ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isRecordingPrimaryShortcut ? 1.5 : 1
                    )
            )

            Button(isRecordingPrimaryShortcut
                   ? L10n.string("action.shortcutStop")
                   : L10n.string("action.shortcutRecord")) {
                if isRecordingPrimaryShortcut {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecordingPrimaryShortcut ? .red : .accentColor)
        }
    }

    @ViewBuilder
    private var shortcutRecordingStatus: some View {
        if isRecordingShortcut {
            Text(L10n.string("action.shortcutRecordingHint"))
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text(L10n.string("action.shortcutHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if releaseShortcutModifiers {
            Text(L10n.string("action.shortcutReleaseModifiers"))
                .font(.caption)
                .foregroundStyle(.red)
        }

        if recorderFailed {
            Text(L10n.string("action.shortcutRecorderNeedPermission"))
                .font(.caption)
                .foregroundStyle(.red)
        }

        if unsupportedShortcutModifier {
            Text(L10n.string("action.shortcutUnsupportedModifier"))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var openAppInfo: AppInfoLookup.Info? {
        let trimmed = appBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved = AppInfoLookup.info(forBundleId: trimmed)
        // Use disk-resolved name when the app is installed; otherwise fall back to stored name.
        if !resolved.path.isEmpty {
            return resolved
        }
        let displayName = appName.isEmpty ? trimmed : appName
        return AppInfoLookup.Info(bundleId: trimmed, name: displayName, path: "")
    }

    @ViewBuilder
    private var openAppEditor: some View {
        if let app = openAppInfo {
            SelectedAppsCard {
                SelectedAppRow(app: app, onRemove: clearOpenApp)
            }
        } else {
            Text(L10n.string("action.openAppEmpty"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack {
            Button {
                showOpenAppPicker = true
            } label: {
                Label(
                    L10n.string(openAppInfo == nil ? "action.openAppChoose" : "action.openAppChange"),
                    systemImage: openAppInfo == nil ? "plus.circle" : "arrow.triangle.2.circlepath"
                )
            }
            Spacer()
        }

        Text(L10n.string("action.openAppHelp"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        Group {
            Picker(L10n.string("action.type"), selection: $kind) {
                ForEach(GestureEditorView.ActionKind.allCases) { item in
                    Text(L10n.string(item.titleKey))
                        .tag(item)
                }
            }
            .onChange(of: kind) { _, newValue in
                if isRecordingShortcut {
                    stopRecording()
                }
                applyKind(newValue)
            }

            switch kind {
            case .none:
                Text(L10n.string("action.noneHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .shortcut:
                shortcutRecorderControl

                // Legacy shortcuts without an ordered chord must be re-recorded first.
                if orderedChord != nil {
                    shortcutSequenceEditor
                }

                shortcutRecordingStatus

            case .system:
                Picker(L10n.string("action.systemCommand"), selection: Binding(
                    get: { systemAction.command },
                    set: { command in
                        stopRecording()
                        systemAction = SystemAction(command: command)
                        action = .system(systemAction)
                    }
                )) {
                    ForEach(SystemCommand.allCases) { command in
                        Text(L10n.string(command.displayKey)).tag(command)
                    }
                }
                shortcutRecorderControl
                Button(L10n.string("action.systemResetShortcut")) {
                    stopRecording()
                    systemAction.shortcutOverride = nil
                    action = .system(systemAction)
                }
                .disabled(systemAction.shortcutOverride == nil)
                Text(L10n.string("action.systemShortcutHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                shortcutRecordingStatus

            case .openApp:
                openAppEditor

            case .openURL:
                TextField("URL", text: $urlString)
                    .onChange(of: urlString) { _, newValue in
                        action = .openURL(newValue)
                    }

            case .shell:
                Text(L10n.string("action.shell"))
                    .font(.body)
                ScriptTextArea(
                    text: $shellCommand,
                    language: .shell,
                    minHeight: 100,
                    placeholder: L10n.string("action.shellPlaceholder")
                )
                .onChange(of: shellCommand) { _, newValue in
                    action = .shell(newValue)
                }
                Text(L10n.string("action.shellWarning"))
                    .font(.caption)
                    .foregroundStyle(.orange)

            case .media:
                Picker(L10n.string("action.media"), selection: $mediaCommand) {
                    ForEach(MediaCommand.allCases) { cmd in
                        Text(L10n.string(cmd.displayKey)).tag(cmd)
                    }
                }
                .onChange(of: mediaCommand) { _, newValue in
                    action = .media(newValue)
                }

            case .window:
                Picker(L10n.string("action.window"), selection: $windowActionSelection) {
                    ForEach(WindowActionSelection.allCases) { selection in
                        Text(L10n.string(selection.displayKey)).tag(selection)
                    }
                }
                .onChange(of: windowActionSelection) { _, newValue in
                    action = newValue.action
                }

            case .appleScript:
                Picker(L10n.string("action.appleScriptCommand"), selection: $appleScriptPreset) {
                    ForEach(AppleScriptPreset.allCases) { preset in
                        Text(L10n.string(preset.displayKey)).tag(preset)
                    }
                }
                .onChange(of: appleScriptPreset) { oldValue, newValue in
                    if oldValue == .custom {
                        customAppleScriptDraft = appleScript
                    }
                    applyAppleScriptPreset(newValue)
                }

                if appleScriptPreset == .custom {
                    ScriptTextArea(
                        text: $appleScript,
                        language: .appleScript,
                        minHeight: 140,
                        placeholder: L10n.string("action.appleScriptPlaceholder")
                    )
                    .onChange(of: appleScript) { _, newValue in
                        customAppleScriptDraft = newValue
                        action = .appleScript(newValue)
                    }
                    Text(L10n.string("action.appleScriptWarning"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            guard !didHydrate else { return }
            didHydrate = true
            hydrate(from: action)
        }
        .onDisappear {
            stopRecording()
        }
        .sheet(isPresented: $showOpenAppPicker) {
            InstalledAppPickerSheet(
                mode: .single(currentBundleId: appBundleId.isEmpty ? nil : appBundleId),
                onConfirm: { selected in
                    if let app = selected.first {
                        applyOpenApp(app)
                    }
                    showOpenAppPicker = false
                },
                onCancel: { showOpenAppPicker = false }
            )
        }
    }

    private func applyOpenApp(_ app: AppInfoLookup.Info) {
        appBundleId = app.bundleId
        appName = app.name
        action = .openApp(bundleId: app.bundleId, name: app.name)
    }

    private func clearOpenApp() {
        appBundleId = ""
        appName = ""
        action = .openApp(bundleId: "", name: "")
    }

    // MARK: - Recording

    private func startRecording(followUp: Bool = false) {
        recorderFailed = false
        releaseShortcutModifiers = false
        unsupportedShortcutModifier = false
        shortcutLivePreview = ""
        let tap = ShortcutRecorderTap.shared
        // The editor can show two pickers; let the current owner reset first.
        tap.onCancel?()
        tap.onPreview = { display in
            shortcutLivePreview = display
        }
        tap.onCapture = { chord, display in
            if kind == .system {
                systemAction.shortcutOverride = chord
                action = .system(systemAction)
                stopRecording()
                return
            }
            if followUp {
                followingChords.append(chord)
            } else {
                keyCode = chord.legacyKeyCode
                modifiers = chord.legacyModifiers
                orderedChord = chord
                shortcutDisplay = display
            }
            applyShortcutAction()
            stopRecording()
        }
        tap.onCancel = {
            stopRecording()
        }
        tap.onUnsupportedModifier = {
            unsupportedShortcutModifier = true
            stopRecording()
        }
        switch tap.start() {
        case .started:
            isRecordingShortcut = true
            isRecordingFollowUp = followUp
        case .heldModifiers:
            stopRecording()
            releaseShortcutModifiers = true
        case .unavailable:
            stopRecording()
            recorderFailed = true
        }
    }

    private func stopRecording() {
        ShortcutRecorderTap.shared.stop()
        ShortcutRecorderTap.shared.onCapture = nil
        ShortcutRecorderTap.shared.onCancel = nil
        ShortcutRecorderTap.shared.onUnsupportedModifier = nil
        ShortcutRecorderTap.shared.onPreview = nil
        isRecordingShortcut = false
        isRecordingFollowUp = false
        shortcutLivePreview = ""
    }

    private func removeFollowingChord(at index: Int) {
        guard followingChords.indices.contains(index) else { return }
        followingChords.remove(at: index)
        applyShortcutAction()
    }

    private func applyShortcutAction() {
        if let orderedChord {
            action = .shortcut(chords: [orderedChord] + followingChords)
            return
        }
        let display = shortcutDisplay.isEmpty
            ? KeyCodeNames.shortcutDisplay(
                keyCode: keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
            )
            : shortcutDisplay
        action = .shortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            display: display.isEmpty ? "—" : display
        )
    }

    private func hydrate(from action: GestureAction) {
        switch action {
        case .none:
            break
        case .shortcut(let code, let mods, let display, let chord):
            orderedChord = chord
            if let chord {
                let resolved = KeyCodeNames.shortcutDisplay(chord: chord)
                keyCode = chord.legacyKeyCode
                modifiers = chord.legacyModifiers
                shortcutDisplay = resolved
                if code != keyCode || mods != modifiers || display != resolved {
                    self.action = .shortcut(chord: chord)
                }
            } else {
                keyCode = code
                modifiers = mods
                // Re-resolve display so old "Key12" configs upgrade to proper names.
                let flags = NSEvent.ModifierFlags(rawValue: mods)
                let resolved = KeyCodeNames.shortcutDisplay(keyCode: code, modifiers: flags)
                shortcutDisplay = display.hasPrefix("Key") ? resolved : (display.isEmpty ? resolved : display)
                if display.hasPrefix("Key") {
                    self.action = .shortcut(keyCode: code, modifiers: mods, display: resolved)
                }
            }
        case .openApp(let bundleId, let name):
            appBundleId = bundleId
            appName = name
        case .openURL(let url):
            urlString = url
        case .shell(let command):
            shellCommand = command
        case .media(let command):
            mediaCommand = command
        case .window(let command):
            windowActionSelection = .window(command)
        case .applicationSwitch(let command):
            windowActionSelection = .applicationSwitch(command)
        case .system(let system):
            systemAction = system
        case .shortcutSequence(let chords):
            guard let first = chords.first else { break }
            orderedChord = first
            keyCode = first.legacyKeyCode
            modifiers = first.legacyModifiers
            shortcutDisplay = KeyCodeNames.shortcutDisplay(chord: first)
            followingChords = Array(chords.dropFirst())
        case .appleScript(let source):
            let preset = AppleScriptPreset.matching(source: source)
            // Set draft before preset so any onChange → custom restore uses the hydrated script.
            if preset == .custom {
                customAppleScriptDraft = source
            }
            appleScript = source
            appleScriptPreset = preset
        }
    }

    private func applyKind(_ kind: GestureEditorView.ActionKind) {
        switch kind {
        case .none:
            action = .none
        case .shortcut:
            applyShortcutAction()
        case .openApp:
            action = .openApp(bundleId: appBundleId, name: appName)
        case .openURL:
            action = .openURL(urlString)
        case .shell:
            action = .shell(shellCommand)
        case .media:
            action = .media(mediaCommand)
        case .window:
            action = windowActionSelection.action
        case .system:
            action = .system(systemAction)
        case .appleScript:
            applyAppleScriptPreset(appleScriptPreset)
        }
    }

    private func applyAppleScriptPreset(_ preset: AppleScriptPreset) {
        if let source = preset.source {
            appleScript = source
            action = .appleScript(source)
        } else {
            appleScript = customAppleScriptDraft
            action = .appleScript(appleScript)
        }
    }

}
