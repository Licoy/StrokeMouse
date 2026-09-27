import AppKit
import SwiftUI

enum AppScopeMode: String, CaseIterable, Identifiable {
    case global
    case apps
    case group

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .global: return "scope.global"
        case .apps: return "scope.apps"
        case .group: return "scope.group"
        }
    }
}

/// Application scope editor: global / selected apps (with icons) / app group.
struct AppScopeEditorView: View {
    @Binding var mode: AppScopeMode
    @Binding var bundleIds: [String]
    @Binding var groupID: UUID?
    let groups: [AppGroup]

    @State private var showPicker = false

    private var entries: [AppInfoLookup.Info] {
        bundleIds.map { AppInfoLookup.info(forBundleId: $0) }
    }

    var body: some View {
        Group {
            Picker(L10n.string("editor.scopeMode"), selection: $mode) {
                ForEach(AppScopeMode.allCases) { mode in
                    Text(L10n.string(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .global:
                Text(L10n.string("editor.scopeGlobalHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .group:
                groupPicker
            case .apps:
                appsEditor
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

    @ViewBuilder
    private var groupPicker: some View {
        if groups.isEmpty {
            Text(L10n.string("editor.scopeGroupEmpty"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker(L10n.string("scope.group"), selection: $groupID) {
                if groupID == nil {
                    Text(L10n.string("editor.scopeGroupNone")).tag(UUID?.none)
                }
                ForEach(groups) { group in
                    Text(group.name).tag(UUID?.some(group.id))
                }
            }
            if let group = groups.first(where: { $0.id == groupID }),
               !group.matchers.isEmpty
            {
                Text(AppGroupSummary.text(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        Text(L10n.string("editor.scopeGroupHelp"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var appsEditor: some View {
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
