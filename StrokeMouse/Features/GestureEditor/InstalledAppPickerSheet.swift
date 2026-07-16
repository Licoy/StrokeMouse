import AppKit
import SwiftUI

// MARK: - Selected app row (shared by scope + open-app)

/// Icon + name + path row used when displaying a chosen app.
struct SelectedAppRow: View {
    let app: AppInfoLookup.Info
    var onRemove: (() -> Void)?

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

            if let onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.string("editor.scopeRemoveApp"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Card chrome for selected apps list

struct SelectedAppsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - Installed app picker sheet

/// Multi-add or single-pick sheet over scanned Applications folders.
struct InstalledAppPickerSheet: View {
    enum Mode {
        /// Multi-select apps to add. `alreadySelected` shows an “Added” badge.
        case multi(alreadySelected: Set<String>)
        /// Single app pick; optional current selection is pre-highlighted.
        case single(currentBundleId: String?)
    }

    let mode: Mode
    var onConfirm: ([AppInfoLookup.Info]) -> Void
    var onCancel: () -> Void

    @State private var apps: [AppInfoLookup.Info] = []
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var isLoading = true

    private var alreadySelected: Set<String> {
        if case .multi(let set) = mode { return set }
        return []
    }

    private var allowsMultiple: Bool {
        if case .multi = mode { return true }
        return false
    }

    private var titleKey: String {
        switch mode {
        case .multi: return "editor.scopePickerTitle"
        case .single: return "action.openAppPickerTitle"
        }
    }

    private var confirmKey: String {
        switch mode {
        case .multi: return "editor.scopeConfirm"
        case .single: return "action.openAppConfirm"
        }
    }

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
                Text(L10n.string(titleKey))
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
                                rowLabel(for: app)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    guard !allowsMultiple else { return }
                                    selection = [app.bundleId]
                                    confirmSelection()
                                }
                            )
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

                if allowsMultiple {
                    Text(
                        String(
                            format: L10n.string("editor.scopeSelectedCount"),
                            locale: L10n.locale,
                            selection.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button(L10n.string("common.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string(confirmKey)) {
                    confirmSelection()
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

    @ViewBuilder
    private func rowLabel(for app: AppInfoLookup.Info) -> some View {
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

    private func toggleSelection(_ bundleId: String) {
        if allowsMultiple {
            if selection.contains(bundleId) {
                selection.remove(bundleId)
            } else {
                selection.insert(bundleId)
            }
        } else {
            selection = [bundleId]
        }
    }

    private func confirmSelection() {
        let chosen = apps.filter { selection.contains($0.bundleId) }
        onConfirm(chosen)
    }

    private func loadApps() async {
        isLoading = true
        let scanned = await Task.detached(priority: .userInitiated) {
            AppInfoLookup.scanInstalledApps()
        }.value
        apps = scanned
        if case .single(let current) = mode, let current, !current.isEmpty {
            selection = [current]
        }
        isLoading = false
    }

    private func browseFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = L10n.string(confirmKey)
        panel.message = L10n.string(titleKey)

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let info = AppInfoLookup.info(fromAppURL: url) else { continue }
            if !apps.contains(where: { $0.bundleId == info.bundleId }) {
                apps.append(info)
                apps.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
            if allowsMultiple {
                selection.insert(info.bundleId)
            } else {
                selection = [info.bundleId]
            }
        }
    }
}
