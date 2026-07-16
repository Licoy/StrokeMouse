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
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, app in
                            ScopedAppRow(
                                app: app,
                                onRemove: { remove(bundleId: app.bundleId) }
                            )
                            if index < entries.count - 1 {
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
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
                alreadySelected: Set(bundleIds),
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

// MARK: - Selected app row

private struct ScopedAppRow: View {
    let app: AppInfoLookup.Info
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfoLookup.icon(for: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                Text(app.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(app.displayPath)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.string("editor.scopeRemoveApp"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Multi-select picker sheet

private struct InstalledAppPickerSheet: View {
    let alreadySelected: Set<String>
    var onConfirm: ([AppInfoLookup.Info]) -> Void
    var onCancel: () -> Void

    @State private var apps: [AppInfoLookup.Info] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [AppInfoLookup.Info] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleId.localizedCaseInsensitiveContains(q)
                || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("editor.scopePickerTitle"))
                    .font(.headline)
                Spacer()
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.string("editor.scopeSearch"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(
                            L10n.string("editor.scopePickerEmpty"),
                            systemImage: "app.dashed"
                        )
                    }
                } else {
                    List {
                        ForEach(filtered) { app in
                            Button {
                                toggleSelection(app.bundleId)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName: selection.contains(app.bundleId)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .font(.title3)
                                    .foregroundStyle(
                                        selection.contains(app.bundleId)
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.55)
                                    )
                                    .frame(width: 22)

                                    Image(nsImage: AppInfoLookup.icon(for: app.path))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 28, height: 28)
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(app.displayPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer(minLength: 4)

                                    if alreadySelected.contains(app.bundleId) {
                                        Text(L10n.string("editor.scopeAlreadyAdded"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule().fill(Color.secondary.opacity(0.12))
                                            )
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button(L10n.string("editor.scopeBrowse")) {
                    browseFromPanel()
                }
                .disabled(isLoading)

                Spacer()

                Text(
                    String(
                        format: L10n.string("editor.scopeSelectedCount"),
                        locale: L10n.locale,
                        selection.count
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(L10n.string("common.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("editor.scopeConfirm")) {
                    let chosen = apps.filter { selection.contains($0.bundleId) }
                    onConfirm(chosen)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 460)
        .task {
            await loadApps()
        }
    }

    private func toggleSelection(_ bundleId: String) {
        if selection.contains(bundleId) {
            selection.remove(bundleId)
        } else {
            selection.insert(bundleId)
        }
    }

    private func loadApps() async {
        isLoading = true
        let scanned = await Task.detached(priority: .userInitiated) {
            AppInfoLookup.scanInstalledApps()
        }.value
        apps = scanned
        isLoading = false
    }

    private func browseFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = L10n.string("editor.scopeConfirm")
        panel.message = L10n.string("editor.scopePickerTitle")

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let info = AppInfoLookup.info(fromAppURL: url) else { continue }
            if !apps.contains(where: { $0.bundleId == info.bundleId }) {
                apps.append(info)
                apps.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
            selection.insert(info.bundleId)
        }
    }
}

