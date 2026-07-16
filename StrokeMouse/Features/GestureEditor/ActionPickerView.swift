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
                HStack {
                    TextField(L10n.string("action.appName"), text: $appName)
                    TextField(L10n.string("action.bundleId"), text: $appBundleId)
                    Button(L10n.string("action.chooseApp")) {
                        chooseApp()
                    }
                }
                .onChange(of: appBundleId) { _, _ in
                    action = .openApp(bundleId: appBundleId, name: appName.isEmpty ? appBundleId : appName)
                }

            case .openURL:
                TextField("URL", text: $urlString)
                    .onChange(of: urlString) { _, newValue in
                        action = .openURL(newValue)
                    }

            case .shell:
                TextField(L10n.string("action.shell"), text: $shellCommand, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(.body, design: .monospaced))
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
                TextField(L10n.string("action.appleScript"), text: $appleScript, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(.body, design: .monospaced))
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

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url) {
                appBundleId = bundle.bundleIdentifier ?? ""
                appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                action = .openApp(bundleId: appBundleId, name: appName)
            }
        }
    }
}
