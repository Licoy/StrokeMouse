import AppKit
import SwiftUI

struct ActionPickerView: View {
    @Binding var kind: GestureEditorView.ActionKind
    @Binding var action: GestureAction

    @State private var shortcutDisplay = ""
    @State private var keyCode: UInt16 = 0
    @State private var modifiers: UInt = 0
    @State private var appBundleId = ""
    @State private var appName = ""
    @State private var urlString = "https://"
    @State private var shellCommand = "echo 'Hello from StrokeMouse'"
    @State private var mediaCommand: MediaCommand = .playPause
    @State private var windowCommand: WindowCommand = .minimize
    @State private var appleScript = "display notification \"StrokeMouse\" with title \"Gesture\""
    @State private var isRecordingShortcut = false
    @State private var didHydrate = false
    @State private var recorderFailed = false
    @State private var showOpenAppPicker = false

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
                HStack(spacing: 10) {
                    // Read-only display (not editable).
                    Text(shortcutDisplay.isEmpty ? L10n.string("action.shortcutEmpty") : shortcutDisplay)
                        .font(.body.monospaced())
                        .foregroundStyle(shortcutDisplay.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isRecordingShortcut ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: isRecordingShortcut ? 1.5 : 1
                                )
                        )

                    Button(isRecordingShortcut
                           ? L10n.string("action.shortcutListening")
                           : L10n.string("action.shortcutRecord")) {
                        if isRecordingShortcut {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecordingShortcut ? .red : .accentColor)
                }

                if isRecordingShortcut {
                    Text(L10n.string("action.shortcutRecordingHint"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(L10n.string("action.shortcutHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if recorderFailed {
                    Text(L10n.string("action.shortcutRecorderNeedPermission"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

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
                Picker(L10n.string("action.window"), selection: $windowCommand) {
                    ForEach(WindowCommand.allCases) { cmd in
                        Text(L10n.string(cmd.displayKey)).tag(cmd)
                    }
                }
                .onChange(of: windowCommand) { _, newValue in
                    action = .window(newValue)
                }

            case .appleScript:
                Text(L10n.string("action.appleScript"))
                    .font(.body)
                ScriptTextArea(
                    text: $appleScript,
                    language: .appleScript,
                    minHeight: 140,
                    placeholder: L10n.string("action.appleScriptPlaceholder")
                )
                .onChange(of: appleScript) { _, newValue in
                    action = .appleScript(newValue)
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

    private func startRecording() {
        recorderFailed = false
        let tap = ShortcutRecorderTap.shared
        tap.onCapture = { code, flags, display in
            keyCode = code
            modifiers = flags
            shortcutDisplay = display
            action = .shortcut(keyCode: code, modifiers: flags, display: display)
            stopRecording()
        }
        tap.onCancel = {
            stopRecording()
        }
        let ok = tap.start()
        if ok {
            isRecordingShortcut = true
        } else {
            recorderFailed = true
            isRecordingShortcut = false
        }
    }

    private func stopRecording() {
        ShortcutRecorderTap.shared.stop()
        ShortcutRecorderTap.shared.onCapture = nil
        ShortcutRecorderTap.shared.onCancel = nil
        isRecordingShortcut = false
    }

    private func hydrate(from action: GestureAction) {
        switch action {
        case .none:
            break
        case .shortcut(let code, let mods, let display):
            keyCode = code
            modifiers = mods
            // Re-resolve display so old "Key12" configs upgrade to proper names.
            let flags = NSEvent.ModifierFlags(rawValue: mods)
            let resolved = KeyCodeNames.shortcutDisplay(keyCode: code, modifiers: flags)
            shortcutDisplay = display.hasPrefix("Key") ? resolved : (display.isEmpty ? resolved : display)
            if display.hasPrefix("Key") {
                self.action = .shortcut(keyCode: code, modifiers: mods, display: resolved)
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
            windowCommand = command
        case .appleScript(let source):
            appleScript = source
        }
    }

    private func applyKind(_ kind: GestureEditorView.ActionKind) {
        switch kind {
        case .none:
            action = .none
        case .shortcut:
            let display = shortcutDisplay.isEmpty
                ? KeyCodeNames.shortcutDisplay(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
                : shortcutDisplay
            action = .shortcut(keyCode: keyCode, modifiers: modifiers, display: display.isEmpty ? "—" : display)
        case .openApp:
            action = .openApp(bundleId: appBundleId, name: appName)
        case .openURL:
            action = .openURL(urlString)
        case .shell:
            action = .shell(shellCommand)
        case .media:
            action = .media(mediaCommand)
        case .window:
            action = .window(windowCommand)
        case .appleScript:
            action = .appleScript(appleScript)
        }
    }

}
