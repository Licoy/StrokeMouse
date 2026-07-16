import AppKit
import SwiftUI

/// Application scope editor: global toggle + multi-select app list with icons.
struct AppScopeEditorView: View {
    @Binding var isGlobal: Bool
    @Binding var bundleIds: [String]

    @State private var showPicker = false

    private var entries: [AppInfoLookup.Info] {
        bundleIds.map { AppInfoLookup.info(forBundleId: $0) }
    }

    var body: some View {
        Group {
            Toggle(L10n.string("editor.scopeGlobal"), isOn: $isGlobal)

            if !isGlobal {
                if entries.isEmpty {
                    Text(L10n.string("editor.scopeEmpty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SelectedAppsCard {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, app in
                                SelectedAppRow(
                                    app: app,
                                    onRemove: { remove(bundleId: app.bundleId) }
                                )
                                if index < entries.count - 1 {
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        showPicker = true
                    } label: {
                        Label(L10n.string("editor.scopeAddApps"), systemImage: "plus.circle")
                    }
                    Spacer()
                    if !entries.isEmpty {
                        Text(
                            String(
                                format: L10n.string("editor.scopeAppCount"),
                                locale: L10n.locale,
                                entries.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.string("editor.scopeHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPicker) {
            InstalledAppPickerSheet(
                mode: .multi(alreadySelected: Set(bundleIds)),
                onConfirm: { selected in
                    mergeSelected(selected)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    private func remove(bundleId: String) {
        bundleIds.removeAll { $0 == bundleId }
    }

    private func mergeSelected(_ selected: [AppInfoLookup.Info]) {
        var seen = Set(bundleIds)
        for app in selected where !seen.contains(app.bundleId) {
            bundleIds.append(app.bundleId)
            seen.insert(app.bundleId)
        }
    }
}
