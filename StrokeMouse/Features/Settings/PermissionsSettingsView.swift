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
                LabeledContent(L10n.string("permissions.listening")) {
                    Text(appState.gestureEngine.isListening
                         ? L10n.string("common.yes")
                         : L10n.string("common.no"))
                }
                LabeledContent(L10n.string("permissions.enabled")) {
                    Text(appState.gestureEngine.isEnabled
                         ? L10n.string("common.yes")
                         : L10n.string("common.no"))
                }
                LabeledContent(L10n.string("permissions.status")) {
                    Text(L10n.string(appState.gestureEngine.statusMessageKey))
                }
                Button(L10n.string("permissions.restartEngine")) {
                    appState.permissionManager.refresh()
                    appState.gestureEngine.restart()
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
}
