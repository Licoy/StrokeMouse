import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        // Observe language without remounting the NSWindow scene.
        let epoch = appState.languageEpoch

        TabView(selection: $appState.settingsTab) {
            GesturesSettingsView()
                .tabItem {
                    Label(L10n.string("tab.gestures"), systemImage: SettingsTab.gestures.systemImage)
                }
                .tag(SettingsTab.gestures)

            GeneralSettingsView()
                .tabItem {
                    Label(L10n.string("tab.general"), systemImage: SettingsTab.general.systemImage)
                }
                .tag(SettingsTab.general)

            PermissionsSettingsView()
                .tabItem {
                    Label(L10n.string("tab.permissions"), systemImage: SettingsTab.permissions.systemImage)
                }
                .tag(SettingsTab.permissions)

            AboutSettingsView()
                .tabItem {
                    Label(L10n.string("tab.about"), systemImage: SettingsTab.about.systemImage)
                }
                .tag(SettingsTab.about)
        }
        // Refresh tab contents/labels; keep Window identity stable.
        .id("settings-tabs-\(epoch)")
        .environment(\.locale, appState.resolvedLocale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environment(appState)
        }
        .onDisappear {
            appState.applyDockVisibility()
        }
    }
}
