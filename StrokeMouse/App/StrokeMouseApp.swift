import AppKit
import SwiftUI

@main
struct StrokeMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage(PreferenceKey.menuBarIconStyle) private var menuBarIconStyle = MenuBarIconStyle.default

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(\.locale, appState.resolvedLocale)
        } label: {
            let _ = appState.languageEpoch
            ZStack {
                Image(nsImage: BrandIconProvider.menuBarIcon(for: menuBarIconStyle))
                    .accessibilityLabel(Text(L10n.string("app.name")))
                SettingsWindowOpener()
                    .environment(appState)
            }
            .frame(
                width: BrandIconProvider.menuBarPointSize.width,
                height: BrandIconProvider.menuBarPointSize.height
            )
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
