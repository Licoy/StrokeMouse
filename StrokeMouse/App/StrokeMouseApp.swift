import AppKit
import SwiftUI

@main
struct StrokeMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        // Settings are presented via AppKit `SettingsWindowController` (not a SwiftUI
        // Window scene) so hide-menu-bar mode can open settings without remounting
        // MenuBarExtra / flashing the status item.
        MenuBarExtra(isInserted: menuBarInsertedBinding) {
            MenuBarView()
                .environment(appState)
                .environment(\.locale, appState.resolvedLocale)
        } label: {
            MenuBarExtraLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)
    }

    /// Two-way binding for MenuBarExtra; writes hide preference when user removes the item.
    private var menuBarInsertedBinding: Binding<Bool> {
        Binding(
            get: { appState.menuBarExtraInserted },
            set: { appState.handleMenuBarExtraInsertedChange($0) }
        )
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

        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(
                width: BrandIconProvider.menuBarPointSize.width,
                height: BrandIconProvider.menuBarPointSize.height
            )
            .accessibilityLabel(Text(L10n.string("app.name")))
            // Force status-item image swap; MenuBarExtra often caches identical Image identity.
            .id("\(status)-\(menuBarIconStyle.rawValue)")
    }
}
