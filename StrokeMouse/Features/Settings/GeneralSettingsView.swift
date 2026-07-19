import AppKit
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage(PreferenceKey.gesturesEnabled) private var gesturesEnabled = true
    @AppStorage(PreferenceKey.minStrokeDistance) private var minStrokeDistance = Double(Constants.defaultMinStrokeDistance)
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(PreferenceKey.menuBarIconStyle) private var menuBarIconStyle = MenuBarIconStyle.default
    @AppStorage(PreferenceKey.language) private var languageRaw = LanguageOverride.system.rawValue
    @AppStorage(PreferenceKey.hideDockIcon) private var hideDockIcon = false
    @AppStorage(PreferenceKey.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(PreferenceKey.showGestureHUD) private var showGestureHUD = true
    @AppStorage(PreferenceKey.hudLineColor) private var lineColorHex = Constants.defaultHUDLineColorHex
    @AppStorage(PreferenceKey.hudLineWidth) private var lineWidth = Double(Constants.defaultHUDLineWidth)
    @AppStorage(PreferenceKey.hudShowStartPoint) private var showStartPoint = true
    @AppStorage(PreferenceKey.hudStartPointRadius) private var startPointRadius = Double(Constants.defaultHUDStartPointRadius)
    @AppStorage(PreferenceKey.automaticallyChecksForUpdates) private var automaticallyChecksForUpdates = true

    @State private var lineColor: Color = DrawingStyle.lineSwiftUIColor
    @State private var isConfirmingDoubleHide = false
    @State private var pendingDoubleHide: DoubleHideKind?
    /// Reference-type gate so confirm applies are visible to `onChange` (SwiftUI `@State` bool is unreliable here).
    @State private var dualHideGate = DualHideGate()

    private enum DoubleHideKind {
        case hideMenuBar
        case hideDock
    }

    private final class DualHideGate {
        var isApplyingConfirmed = false
    }

    /// Touch language epoch so this form re-resolves L10n strings.
    private var langEpoch: UInt { appState.languageEpoch }

    private var runtimeStatusText: String {
        L10n.string(appState.gestureEngine.statusMessageKey)
    }

    var body: some View {
        let epoch = langEpoch

        Form {
            Section {
                Toggle(L10n.string("general.enableGestures"), isOn: $gesturesEnabled)
                    .onChange(of: gesturesEnabled) { _, newValue in
                        appState.setGesturesEnabled(newValue)
                    }

                LabeledContent(L10n.string("general.runtimeStatus")) {
                    Text(runtimeStatusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                sliderRow(
                    title: L10n.string("general.minDistance"),
                    valueText: "\(Int(minStrokeDistance)) pt",
                    value: $minStrokeDistance,
                    range: 20...120,
                    step: 5
                )
                .onChange(of: minStrokeDistance) { _, newValue in
                    appState.updateMinStrokeDistance(newValue)
                }
            } header: {
                Text(L10n.string("general.engine"))
            } footer: {
                Text(L10n.string("general.engineFooter"))
            }

            Section {
                Toggle(L10n.string("general.showHUD"), isOn: $showGestureHUD)
                    .onChange(of: showGestureHUD) { _, newValue in
                        appState.gestureEngine.setHUDEnabled(newValue)
                    }

                ColorPicker(L10n.string("general.lineColor"), selection: $lineColor, supportsOpacity: true)
                    .onChange(of: lineColor) { _, newValue in
                        DrawingStyle.lineSwiftUIColor = newValue
                        lineColorHex = DrawingStyle.lineColorHex
                    }

                sliderRow(
                    title: L10n.string("general.lineWidth"),
                    valueText: "\(String(format: "%.0f", lineWidth)) pt",
                    value: $lineWidth,
                    range: 1...16,
                    step: 1
                )

                Toggle(L10n.string("general.showStartPoint"), isOn: $showStartPoint)

                sliderRow(
                    title: L10n.string("general.startPointSize"),
                    valueText: "\(String(format: "%.0f", startPointRadius)) pt",
                    value: $startPointRadius,
                    range: 4...16,
                    step: 1
                )
                .disabled(!showStartPoint)

                HStack(spacing: 12) {
                    Text(L10n.string("general.strokePreview"))
                        .foregroundStyle(.secondary)
                    StrokeStylePreview(
                        lineColor: lineColor,
                        lineWidth: lineWidth,
                        showStart: showStartPoint,
                        startRadius: startPointRadius
                    )
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                }

                Button(L10n.string("general.resetStrokeStyle")) {
                    resetStrokeStyle()
                }
            } header: {
                Text(L10n.string("general.strokeStyle"))
            } footer: {
                Text(L10n.string("general.startPointFixedRed"))
            }

            Section {
                LaunchAtLogin.Toggle {
                    Text(L10n.string("general.launchAtLogin"))
                }
                Toggle(L10n.string("general.hideDockIcon"), isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { oldValue, newValue in
                        if dualHideGate.isApplyingConfirmed {
                            appState.applyDockVisibility()
                            return
                        }
                        // Rising edge only — avoid re-prompt / revert when reopening settings
                        // with dual-hide already saved (AppStorage / onAppear sync).
                        if newValue, !oldValue, hideMenuBarIcon {
                            // Revert until user confirms dual-hide.
                            hideDockIcon = false
                            pendingDoubleHide = .hideDock
                            isConfirmingDoubleHide = true
                            return
                        }
                        appState.applyDockVisibility()
                    }
                Toggle(L10n.string("general.hideMenuBarIcon"), isOn: $hideMenuBarIcon)
                    .onChange(of: hideMenuBarIcon) { oldValue, newValue in
                        if dualHideGate.isApplyingConfirmed {
                            appState.setHideMenuBarIcon(newValue)
                            return
                        }
                        // Rising edge only — same dual-hide reopen guard as Dock toggle.
                        if newValue, !oldValue, hideDockIcon {
                            hideMenuBarIcon = false
                            pendingDoubleHide = .hideMenuBar
                            isConfirmingDoubleHide = true
                            return
                        }
                        appState.setHideMenuBarIcon(newValue)
                    }
            } header: {
                Text(L10n.string("general.startup"))
            } footer: {
                Text(L10n.string("general.hideChromeFooter"))
            }

            Section {
                Picker(L10n.string("general.appearanceMode"), selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(L10n.string(mode.displayKey))
                            .tag(mode.rawValue)
                    }
                }
                .onChange(of: appearanceRaw) { _, _ in
                    appState.applyAppearance()
                }

                Picker(L10n.string("general.menuBarIconStyle"), selection: $menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(L10n.string(style.displayKey))
                            .tag(style)
                    }
                }

                Picker(L10n.string("general.language"), selection: $languageRaw) {
                    ForEach(LanguageOverride.allCases) { lang in
                        Text(L10n.string(lang.displayKey))
                            .tag(lang.rawValue)
                    }
                }
                .onChange(of: languageRaw) { _, _ in
                    appState.applyLanguage(keepSettingsVisible: true)
                }
            } header: {
                Text(L10n.string("general.appearance"))
            } footer: {
                Text(L10n.string("general.languageHint"))
            }

            Section {
                Toggle(L10n.string("update.automaticallyChecks"), isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        appState.updaterService.automaticallyChecksForUpdates = newValue
                    }

                LabeledContent(L10n.string("update.currentVersion")) {
                    Text(appState.updaterService.currentVersionDisplay)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.updaterService.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        if appState.updaterService.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(L10n.string("update.checkNow"))
                    }
                }
                .disabled(appState.updaterService.isCheckingForUpdates)
            } header: {
                Text(L10n.string("update.section"))
            } footer: {
                Text(L10n.string("update.sectionFooter"))
            }

            Section(L10n.string("general.config")) {
                LabeledContent(L10n.string("general.configPath")) {
                    Text(appState.configStore.configURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Button(L10n.string("general.revealConfig")) {
                    NSWorkspace.shared.activateFileViewerSelecting([appState.configStore.configURL])
                }
                if let error = appState.configStore.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Button(L10n.string("general.quitApp"), role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } footer: {
                Text(L10n.string("general.quitAppFooter"))
            }
        }
        .formStyle(.grouped)
        .padding()
        // Remount form content on language change (does not close the settings window).
        .id("general-settings-\(epoch)")
        .onAppear {
            lineColor = DrawingStyle.lineSwiftUIColor
            automaticallyChecksForUpdates = appState.updaterService.automaticallyChecksForUpdates
            hideMenuBarIcon = appState.prefersHideMenuBarIcon
        }
        .confirmationDialog(
            L10n.string("general.doubleHideTitle"),
            isPresented: $isConfirmingDoubleHide,
            titleVisibility: .visible
        ) {
            Button(L10n.string("general.doubleHideConfirm"), role: .destructive) {
                confirmDoubleHide()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingDoubleHide = nil
            }
        } message: {
            Text(L10n.string("general.doubleHideMessage"))
        }
    }

    private func confirmDoubleHide() {
        let kind = pendingDoubleHide
        pendingDoubleHide = nil
        // Class-backed flag is readable immediately inside Toggle onChange.
        dualHideGate.isApplyingConfirmed = true
        switch kind {
        case .hideMenuBar:
            // Apply engine preference first, then sync the Toggle.
            appState.setHideMenuBarIcon(true)
            hideMenuBarIcon = true
        case .hideDock:
            hideDockIcon = true
            appState.applyDockVisibility()
        case nil:
            break
        }
        // Clear after onChange has run (same turn + next runloop for safety).
        DispatchQueue.main.async {
            dualHideGate.isApplyingConfirmed = false
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(title): \(valueText)")
                .frame(minWidth: 168, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
    }

    private func resetStrokeStyle() {
        showGestureHUD = true
        lineWidth = Double(Constants.defaultHUDLineWidth)
        showStartPoint = true
        startPointRadius = Double(Constants.defaultHUDStartPointRadius)
        lineColorHex = Constants.defaultHUDLineColorHex
        lineColor = DrawingStyle.lineSwiftUIColor
        appState.gestureEngine.setHUDEnabled(true)
    }
}

private struct StrokeStylePreview: View {
    let lineColor: Color
    let lineWidth: Double
    let showStart: Bool
    let startRadius: Double

    var body: some View {
        Canvas { context, size in
            let pad: CGFloat = 10
            let start = CGPoint(x: pad + 8, y: size.height * 0.7)
            let mid = CGPoint(x: size.width * 0.45, y: size.height * 0.25)
            let end = CGPoint(x: size.width - pad, y: size.height * 0.55)

            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: mid)
            context.stroke(
                path,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            if showStart {
                let r = CGFloat(startRadius) * 0.7
                let circle = Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(.red))
                context.stroke(circle, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
    }
}
