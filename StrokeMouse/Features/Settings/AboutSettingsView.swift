import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppState.self) private var appState

    private var langEpoch: UInt { appState.languageEpoch }

    private var version: String {
        appState.updaterService.currentVersionDisplay
    }

    private var isCheckingForUpdates: Bool {
        appState.updaterService.isCheckingForUpdates
    }

    var body: some View {
        let _ = langEpoch

        VStack(spacing: 16) {
            Image(nsImage: BrandIconProvider.applicationIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel(Text(L10n.string("app.name")))

            Text(L10n.string("app.name"))
                .font(.largeTitle.weight(.bold))

            Text(L10n.string("about.tagline"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(L10n.string("about.version") + " " + version)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(maxWidth: 280)

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(Constants.githubURL)
                } label: {
                    Label {
                        Text(L10n.string("about.github"))
                    } icon: {
                        Image("GitHubMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    appState.updaterService.checkForUpdates()
                } label: {
                    Label {
                        Text(L10n.string("update.checkNow"))
                    } icon: {
                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingForUpdates)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
