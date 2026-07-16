import AppKit
import SwiftUI

@main
struct StrokeMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(\.locale, appState.resolvedLocale)
        } label: {
            MenuBarExtraLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        Window(L10n.string("settings.windowTitle"), id: AppState.settingsWindowID) {
            SettingsRootView()
                .environment(appState)
                .environment(\.locale, appState.resolvedLocale)
                // Never attach .id(languageEpoch) here — it closes the settings window.
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 900, height: 560)
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

/// Isolated label so AppState.menuBarIconStatus invalidates the status item image.
private struct MenuBarExtraLabel: View {
    @Environment(AppState.self) private var appState
    @AppStorage(PreferenceKey.menuBarIconStyle) private var menuBarIconStyle = MenuBarIconStyle.default

    var body: some View {
        let _ = appState.languageEpoch
        let status = appState.menuBarIconStatus
        let icon = BrandIconProvider.menuBarIcon(for: menuBarIconStyle, status: status)

        ZStack {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: BrandIconProvider.menuBarPointSize.width,
                    height: BrandIconProvider.menuBarPointSize.height
                )
                .accessibilityLabel(Text(L10n.string("app.name")))
            SettingsWindowOpener()
                .environment(appState)
        }
        .frame(
            width: BrandIconProvider.menuBarPointSize.width,
            height: BrandIconProvider.menuBarPointSize.height
        )
        // Force status-item image swap; MenuBarExtra often caches identical Image identity.
        .id("\(status)-\(menuBarIconStyle.rawValue)")
    }
}
