import AppKit
import SwiftUI

struct ScrollSettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage(PreferenceKey.scrollEnhancementEnabled) private var enabled = true
    @AppStorage(PreferenceKey.scrollReverseMouseVertical) private var reverseMouseVertical = false
    @AppStorage(PreferenceKey.scrollReverseMouseHorizontal) private var reverseMouseHorizontal = false
    @AppStorage(PreferenceKey.scrollReverseTrackpadVertical) private var reverseTrackpadVertical = false
    @AppStorage(PreferenceKey.scrollReverseTrackpadHorizontal) private var reverseTrackpadHorizontal = false
    @AppStorage(PreferenceKey.scrollSmoothEnabled) private var smoothEnabled = false
    @AppStorage(PreferenceKey.scrollSmoothPreset) private var presetRaw = ScrollSmoothPreset.standard.rawValue
    @AppStorage(PreferenceKey.scrollSmoothCustomStep) private var customStep = ScrollSmoothPreset.standardStep
    @AppStorage(PreferenceKey.scrollSmoothCustomDurationMs) private var customDurationMs = ScrollSmoothPreset.standardDurationMs
    @AppStorage(PreferenceKey.scrollSmoothCustomAcceleration) private var customAcceleration = ScrollSmoothPreset.standardAcceleration

    @State private var showPicker = false

    private var langEpoch: UInt { appState.languageEpoch }

    private var preset: ScrollSmoothPreset {
        ScrollSmoothPreset(rawValue: presetRaw) ?? .standard
    }

    private var effectiveParameters: ScrollSmoothParameters {
        if let fixed = preset.fixedParameters { return fixed }
        return ScrollSmoothParameters(
            stepPixels: customStep,
            durationMs: customDurationMs,
            acceleration: customAcceleration
        ).clamped()
    }

    private var excludedApps: [AppInfoLookup.Info] {
        appState.scrollEngine.configuration.excludedBundleIds.map {
            AppInfoLookup.info(forBundleId: $0)
        }
    }

    var body: some View {
        let epoch = langEpoch

        Form {
            Section {
                Toggle(L10n.string("scroll.enabled"), isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        appState.applyScrollConfiguration()
                    }
                LabeledContent(L10n.string("scroll.status")) {
                    Text(L10n.string(appState.scrollEngine.status.messageKey))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text(L10n.string("scroll.section.main"))
            } footer: {
                Text(L10n.string("scroll.main.footer"))
            }

            Section {
                reverseGroup(
                    title: L10n.string("scroll.group.mouse"),
                    vertical: $reverseMouseVertical,
                    horizontal: $reverseMouseHorizontal
                )
                reverseGroup(
                    title: L10n.string("scroll.group.trackpad"),
                    vertical: $reverseTrackpadVertical,
                    horizontal: $reverseTrackpadHorizontal
                )
            } header: {
                Text(L10n.string("scroll.section.reverse"))
            } footer: {
                Text(L10n.string("scroll.reverse.footer"))
            }

            Section {
                Toggle(L10n.string("scroll.smooth.enabled"), isOn: $smoothEnabled)
                    .onChange(of: smoothEnabled) { _, _ in
                        appState.applyScrollConfiguration()
                    }
                Picker(L10n.string("scroll.preset"), selection: $presetRaw) {
                    ForEach(ScrollSmoothPreset.allCases, id: \.rawValue) { item in
                        Text(L10n.string(item.displayKey)).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!smoothEnabled)
                .onChange(of: presetRaw) { _, _ in
                    appState.applyScrollConfiguration()
                }

                DisclosureGroup(L10n.string("scroll.advanced")) {
                    sliderRow(
                        title: L10n.string("scroll.step"),
                        valueText: valueText(effectiveParameters.stepPixels, unit: "scroll.unit.px"),
                        value: stepBinding,
                        range: Constants.scrollStepRange,
                        step: Constants.scrollStepIncrement
                    )
                    sliderRow(
                        title: L10n.string("scroll.duration"),
                        valueText: valueText(effectiveParameters.durationMs, unit: "scroll.unit.ms"),
                        value: durationBinding,
                        range: Constants.scrollDurationRangeMs,
                        step: Constants.scrollDurationIncrementMs
                    )
                    sliderRow(
                        title: L10n.string("scroll.acceleration"),
                        valueText: String(format: "%.2f", effectiveParameters.acceleration),
                        value: accelerationBinding,
                        range: Constants.scrollAccelerationRange,
                        step: Constants.scrollAccelerationIncrement
                    )
                }
                .disabled(!smoothEnabled)
            } header: {
                Text(L10n.string("scroll.section.smooth"))
            } footer: {
                Text(L10n.string("scroll.smooth.footer"))
            }

            Section {
                if excludedApps.isEmpty {
                    Text(L10n.string("scroll.exclude.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SelectedAppsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(excludedApps.enumerated()), id: \.element.id) { index, app in
                                SelectedAppRow(app: app) {
                                    removeExcluded(app.bundleId)
                                }
                                if index < excludedApps.count - 1 {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                    }
                }
                Button {
                    showPicker = true
                } label: {
                    Label(L10n.string("scroll.exclude.add"), systemImage: "plus.circle")
                }
            } header: {
                Text(L10n.string("scroll.section.excluded"))
            } footer: {
                Text(L10n.string("scroll.exclude.footer"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .id("scroll-settings-\(epoch)")
        .sheet(isPresented: $showPicker) {
            InstalledAppPickerSheet(
                mode: .multi(alreadySelected: Set(excludedApps.map(\.bundleId))),
                onConfirm: { selected in
                    mergeExcluded(selected)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    private var stepBinding: Binding<Double> {
        parameterBinding(\.stepPixels) { customStep = $0 }
    }

    private var durationBinding: Binding<Double> {
        parameterBinding(\.durationMs) { customDurationMs = $0 }
    }

    private var accelerationBinding: Binding<Double> {
        parameterBinding(\.acceleration) { customAcceleration = $0 }
    }

    private func reverseGroup(
        title: String,
        vertical: Binding<Bool>,
        horizontal: Binding<Bool>
    ) -> some View {
        Group {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle(L10n.string("scroll.reverse.vertical"), isOn: vertical)
                .onChange(of: vertical.wrappedValue) { _, _ in
                    appState.applyScrollConfiguration()
                }
            Toggle(L10n.string("scroll.reverse.horizontal"), isOn: horizontal)
                .onChange(of: horizontal.wrappedValue) { _, _ in
                    appState.applyScrollConfiguration()
                }
        }
    }

    private func parameterBinding(
        _ keyPath: KeyPath<ScrollSmoothParameters, Double>,
        assign: @escaping (Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { effectiveParameters[keyPath: keyPath] },
            set: { newValue in
                adoptCustomIfNeeded()
                assign(newValue)
                appState.applyScrollConfiguration()
            }
        )
    }

    /// Named presets keep their own numbers. The first drag copies them into
    /// the custom slot, then applies the dragged value on top.
    private func adoptCustomIfNeeded() {
        guard preset != .custom else { return }
        let fixed = preset.fixedParameters ?? effectiveParameters
        customStep = fixed.stepPixels
        customDurationMs = fixed.durationMs
        customAcceleration = fixed.acceleration
        presetRaw = ScrollSmoothPreset.custom.rawValue
    }

    private func valueText(_ value: Double, unit: String) -> String {
        "\(Int(value.rounded())) \(L10n.string(unit))"
    }

    private func removeExcluded(_ bundleId: String) {
        let remaining = appState.scrollEngine.configuration.excludedBundleIds
            .filter { $0 != bundleId }
        appState.setScrollExcludedBundleIds(remaining)
    }

    private func mergeExcluded(_ selected: [AppInfoLookup.Info]) {
        var ids = appState.scrollEngine.configuration.excludedBundleIds
        var seen = Set(ids)
        for app in selected where seen.insert(app.bundleId).inserted {
            ids.append(app.bundleId)
        }
        appState.setScrollExcludedBundleIds(ids)
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
}
