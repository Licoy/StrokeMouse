import AppKit
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center) {
                    Image(systemName: appState.permissionManager.isAccessibilityTrusted ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(appState.permissionManager.isAccessibilityTrusted ? .green : .orange)
                        .font(.title2)
                        .symbolEffect(
                            .bounce,
                            value: appState.permissionManager.isAccessibilityTrusted
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("permissions.accessibilityTitle"))
                            .font(.headline)
                        Text(L10n.string(appState.permissionManager.isAccessibilityTrusted
                                    ? "permissions.accessibilityGranted"
                                    : "permissions.accessibilityDenied"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !appState.permissionManager.isAccessibilityTrusted {
                        Button(L10n.string("permissions.authorizeWithGuide")) {
                            appState.permissionManager.authorizeAccessibility(
                                sourceFrameInScreen: clickSourceFrame()
                            )
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L10n.string("permissions.grant")) {
                            appState.permissionManager.requestAccessibility()
                        }
                    } else {
                        Button(L10n.string("permissions.openSettings")) {
                            appState.permissionManager.authorizeAccessibility(
                                sourceFrameInScreen: clickSourceFrame()
                            )
                        }
                    }
                }
            } header: {
                Text(L10n.string("permissions.required"))
            } footer: {
                Text(L10n.string("permissions.accessibilityFooter"))
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("permissions.automationTitle"))
                        .font(.headline)
                    Text(L10n.string("permissions.automationBody"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L10n.string("permissions.openAutomation")) {
                        appState.permissionManager.openAutomationSettings()
                    }
                }
            } header: {
                Text(L10n.string("permissions.optional"))
            }

            Section(L10n.string("permissions.engineStatus")) {
                LabeledContent(L10n.string("permissions.enabled")) {
                    Text(appState.gestureRuntime.isEnabled
                         ? L10n.string("common.yes")
                         : L10n.string("common.no"))
                }
                LabeledContent(L10n.string("permissions.status")) {
                    Text(L10n.string(appState.gestureRuntime.statusMessageKey))
                }
                channelRow(
                    L10n.string("permissions.channel.mouse"),
                    status: appState.gestureRuntime.state.inputs.mouse
                )
                channelRow(
                    L10n.string("permissions.channel.modifier"),
                    status: appState.gestureRuntime.state.inputs.modifier
                )
                channelRow(
                    L10n.string("permissions.channel.multitouch"),
                    status: appState.gestureRuntime.state.inputs.multitouch
                )
                Toggle(
                    L10n.string("trackpad.directEnabled"),
                    isOn: Binding(
                        get: {
                            UserDefaults.standard.bool(
                                forKey: PreferenceKey.directTrackpadEnabled
                            )
                        },
                        set: { setDirectTrackpadEnabled($0) }
                    )
                )
                Text(L10n.string("trackpad.experimentalWarning"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(L10n.string("permissions.restartEngine")) {
                    appState.retryGestureInputs()
                }
            }

            if let failure = appState.configStore.lastFailure {
                Section(L10n.string("permissions.configRecovery")) {
                    Text(failure.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(L10n.string("permissions.revealConfig")) {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            appState.configStore.configURL
                        ])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            appState.permissionManager.refresh()
        }
    }

    private func clickSourceFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }

    private func channelRow(
        _ title: String,
        status: GestureInputChannelStatus
    ) -> some View {
        LabeledContent(title) {
            Label(
                channelStatusText(status),
                systemImage: channelStatusSymbol(status)
            )
            .foregroundStyle(channelStatusColor(status))
        }
    }

    private func setDirectTrackpadEnabled(_ enabled: Bool) {
        if enabled,
           !UserDefaults.standard.bool(
               forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
           ),
           appState.configStore.gestures.contains(where: {
               guard $0.isEnabled, case .trackpad = $0.input else {
                   return false
               }
               return true
           })
        {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("trackpad.consent.title")
            alert.informativeText = L10n.string("trackpad.consent.message")
            alert.addButton(
                withTitle: L10n.string("trackpad.consent.accept")
            )
            alert.addButton(withTitle: L10n.string("common.cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(
                true,
                forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
            )
        }
        appState.setDirectTrackpadEnabled(enabled)
    }

    private func channelStatusText(
        _ status: GestureInputChannelStatus
    ) -> String {
        switch status {
        case .notRequested:
            return L10n.string("permissions.channel.notRequested")
        case .stopped:
            return L10n.string("permissions.channel.stopped")
        case .listening:
            return L10n.string("permissions.channel.listening")
        case .failed(let failure):
            return L10n.string(failure.displayKey)
        }
    }

    private func channelStatusSymbol(
        _ status: GestureInputChannelStatus
    ) -> String {
        switch status {
        case .listening: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .notRequested, .stopped: return "pause.circle"
        }
    }

    private func channelStatusColor(
        _ status: GestureInputChannelStatus
    ) -> Color {
        switch status {
        case .listening: return .green
        case .failed: return .orange
        case .notRequested, .stopped: return .secondary
        }
    }
}

private extension GestureInputFailure {
    var displayKey: String {
        switch self {
        case .accessibilityRequired:
            return "permissions.failure.accessibility"
        case .mouseEventTapCreationFailed:
            return "permissions.failure.mouseTap"
        case .modifierEventTapCreationFailed:
            return "permissions.failure.modifierTap"
        case .multitouchFrameworkUnavailable:
            return "permissions.failure.multitouchFramework"
        case .multitouchSymbolMissing:
            return "permissions.failure.multitouchSymbol"
        case .multitouchDeviceUnavailable:
            return "permissions.failure.multitouchDevice"
        case .multitouchInvalidDimensions:
            return "permissions.failure.multitouchDimensions"
        case .multitouchInvalidFrame:
            return "permissions.failure.multitouchFrame"
        case .multitouchStartFailed:
            return "permissions.failure.multitouchStart"
        }
    }
}
