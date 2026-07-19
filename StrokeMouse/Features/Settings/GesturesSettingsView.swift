import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum GestureEnabledFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "gestures.filter.all"
        case .enabled: return "gestures.filter.enabled"
        case .disabled: return "gestures.filter.disabled"
        }
    }
}

struct GesturesSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection = Set<GestureProfile.ID>()
    @State private var editorProfile: GestureProfile?
    @State private var isShowingGestureTest = false
    @State private var isShowingAddApp = false
    @State private var searchText = ""
    @State private var enabledFilter: GestureEnabledFilter = .all
    @State private var sortOrder = [KeyPathComparator(\GestureProfile.name)]
    @State private var alertMessage: AlertMessage?
    @State private var pendingDeleteIDs = Set<GestureProfile.ID>()
    @State private var isConfirmingDelete = false
    @State private var pendingRemoveAppBundleId: String?
    @State private var isConfirmingRemoveApp = false
    @State private var sidebarSelection: GestureSidebarItem = .global
    @State private var pinnedAppBundleIds: [String] = GesturesSettingsView.loadPinnedApps()
    @State private var isAddAppHovered = false

    private var sidebarAppIds: [String] {
        let ids = GestureSidebarCatalog.sidebarAppBundleIds(
            gestures: appState.configStore.gestures,
            pinnedBundleIds: pinnedAppBundleIds
        )
        return ids.sorted {
            let left = AppInfoLookup.info(forBundleId: $0).name
            let right = AppInfoLookup.info(forBundleId: $1).name
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private var displayedGestures: [GestureProfile] {
        var items = GestureSidebarCatalog.gestures(
            in: sidebarSelection,
            from: appState.configStore.gestures
        )

        switch enabledFilter {
        case .all: break
        case .enabled: items = items.filter(\.isEnabled)
        case .disabled: items = items.filter { !$0.isEnabled }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter { gesture in
                gesture.name.localizedCaseInsensitiveContains(q)
                    || gesture.action.detail.localizedCaseInsensitiveContains(q)
                    || gesture.notes.localizedCaseInsensitiveContains(q)
                    || gesture.pattern.summary.localizedCaseInsensitiveContains(q)
                    || L10n.string(gesture.action.summaryKey).localizedCaseInsensitiveContains(q)
            }
        }

        return items.sorted(using: sortOrder)
    }

    private var allDisplayedSelected: Bool {
        let ids = Set(displayedGestures.map(\.id))
        return !ids.isEmpty && ids.isSubset(of: selection)
    }

    private func gestureCount(for sidebar: GestureSidebarItem) -> Int {
        GestureSidebarCatalog.gestures(in: sidebar, from: appState.configStore.gestures).count
    }

    /// Shared bottom chrome height so left/right horizontal dividers align exactly.
    private let bottomChromeHeight: CGFloat = 52
    private let sidebarWidth: CGFloat = 200

    var body: some View {
        let _ = appState.languageEpoch

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebarBody
                    .frame(width: sidebarWidth)
                Divider()
                detailBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // One full-width divider — cannot misalign between columns.
            Divider()

            HStack(spacing: 0) {
                addAppFooter
                    .frame(width: sidebarWidth)
                Divider()
                footerBar
                    .frame(maxWidth: .infinity)
            }
            .frame(height: bottomChromeHeight)
            .background(chromeSurfaceColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editorProfile) { profile in
            GestureEditorView(profile: profile) { updated in
                if appState.configStore.gestures.contains(where: { $0.id == updated.id }) {
                    appState.configStore.update(updated)
                } else {
                    appState.configStore.add(updated)
                }
                // Follow the gesture into its scope group after save.
                selectSidebar(for: updated.scope)
                editorProfile = nil
            } onCancel: {
                editorProfile = nil
            }
            .environment(appState)
        }
        .sheet(isPresented: $isShowingGestureTest) {
            GestureTestView()
                .environment(appState)
                .environment(\.locale, appState.resolvedLocale)
        }
        .sheet(isPresented: $isShowingAddApp) {
            InstalledAppPickerSheet(
                mode: .single(currentBundleId: nil),
                onConfirm: { apps in
                    if let app = apps.first {
                        pinApp(app.bundleId)
                        sidebarSelection = .app(app.bundleId)
                    }
                    isShowingAddApp = false
                },
                onCancel: {
                    isShowingAddApp = false
                }
            )
        }
        .alert(item: $alertMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text(L10n.string("common.ok")))
            )
        }
        .confirmationDialog(
            L10n.string("gestures.deleteConfirmTitle"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.string("gestures.delete"), role: .destructive) {
                deleteSelected(pendingDeleteIDs)
                pendingDeleteIDs = []
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingDeleteIDs = []
            }
        } message: {
            Text(deleteConfirmMessage)
        }
        .confirmationDialog(
            L10n.string("gestures.sidebarRemoveAppConfirmTitle"),
            isPresented: $isConfirmingRemoveApp,
            titleVisibility: .visible
        ) {
            Button(L10n.string("gestures.sidebarRemoveAppConfirmButton"), role: .destructive) {
                if let bundleId = pendingRemoveAppBundleId {
                    confirmRemoveAppAndGestures(bundleId)
                }
                pendingRemoveAppBundleId = nil
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                pendingRemoveAppBundleId = nil
            }
        } message: {
            Text(removeAppConfirmMessage)
        }
        .onChange(of: appState.configStore.gestures) { _, _ in
            // Drop selection entries that no longer exist.
            let valid = Set(appState.configStore.gestures.map(\.id))
            selection = selection.intersection(valid)
        }
    }

    private var deleteConfirmMessage: String {
        String(
            format: L10n.string("gestures.deleteConfirmMessage"),
            locale: L10n.locale,
            pendingDeleteIDs.count
        )
    }

    private var removeAppConfirmMessage: String {
        let bundleId = pendingRemoveAppBundleId ?? ""
        let plan = GestureSidebarCatalog.planRemoveApp(
            bundleId,
            from: appState.configStore.gestures
        )
        let name = AppInfoLookup.info(forBundleId: bundleId).name
        return String(
            format: L10n.string("gestures.sidebarRemoveAppConfirmMessage"),
            locale: L10n.locale,
            name,
            plan.idsToDelete.count,
            plan.profilesToUpdate.count
        )
    }

    /// Match detail pane surface: pure white in light, control background in dark.
    private var chromeSurfaceColor: Color {
        colorScheme == .light ? Color.white : Color(nsColor: .controlBackgroundColor)
    }

    // MARK: - Sidebar (list only; bottom chrome is shared with detail)

    private var sidebarBody: some View {
        VStack(spacing: 0) {
            Text(L10n.string("gestures.sidebarTitle"))
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    GestureSidebarRow(
                        title: L10n.string("scope.global"),
                        count: gestureCount(for: .global),
                        isSelected: sidebarSelection == .global,
                        icon: { Image(systemName: "globe") }
                    ) {
                        sidebarSelection = .global
                    }

                    if !sidebarAppIds.isEmpty {
                        Text(L10n.string("gestures.sidebarApps"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                            .padding(.horizontal, 10)

                        ForEach(sidebarAppIds, id: \.self) { bundleId in
                            let info = AppInfoLookup.info(forBundleId: bundleId)
                            let item = GestureSidebarItem.app(bundleId)
                            GestureSidebarRow(
                                title: info.name,
                                count: gestureCount(for: item),
                                isSelected: sidebarSelection == item,
                                icon: {
                                    Image(nsImage: AppInfoLookup.icon(for: info.path))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 16, height: 16)
                                        .cornerRadius(3)
                                }
                            ) {
                                sidebarSelection = item
                            }
                            .contextMenu {
                                Button(L10n.string("gestures.sidebarRemoveApp"), role: .destructive) {
                                    requestRemoveApp(bundleId)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(chromeSurfaceColor)
    }

    private var addAppFooter: some View {
        Button {
            isShowingAddApp = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text(L10n.string("gestures.sidebarAddApp"))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isAddAppHovered ? Color.primary.opacity(0.06) : chromeSurfaceColor)
        .onHover { isAddAppHovered = $0 }
        .help(L10n.string("gestures.sidebarAddApp"))
    }

    // MARK: - Detail (table only; bottom chrome is shared with sidebar)

    private var detailBody: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            Group {
                if appState.configStore.gestures.isEmpty, pinnedAppBundleIds.isEmpty, case .global = sidebarSelection {
                    ContentUnavailableView(
                        L10n.string("gestures.emptyTitle"),
                        systemImage: "hand.draw",
                        description: Text(L10n.string("gestures.emptySubtitle"))
                    )
                } else if displayedGestures.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptySubtitle)
                    )
                } else {
                    gestureTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chromeSurfaceColor)
        }
        .background(chromeSurfaceColor)
    }

    private var emptyTitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || enabledFilter != .all
        {
            return L10n.string("gestures.filterEmptyTitle")
        }
        switch sidebarSelection {
        case .global:
            return L10n.string("gestures.emptyGlobalTitle")
        case .app:
            return L10n.string("gestures.emptyAppTitle")
        }
    }

    private var emptySubtitle: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || enabledFilter != .all
        {
            return L10n.string("gestures.filterEmptySubtitle")
        }
        switch sidebarSelection {
        case .global:
            return L10n.string("gestures.emptyGlobalSubtitle")
        case .app:
            return L10n.string("gestures.emptyAppSubtitle")
        }
    }

    private var emptySystemImage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || enabledFilter != .all
        {
            return "line.3.horizontal.decrease.circle"
        }
        return "hand.draw"
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(detailTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    importGestures()
                } label: {
                    Label(L10n.string("gestures.import"), systemImage: "square.and.arrow.down")
                }
                Button {
                    editorProfile = makeNewProfile()
                } label: {
                    Label(L10n.string("gestures.add"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                TextField(L10n.string("gestures.searchPlaceholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Picker(L10n.string("gestures.filter.enabledState"), selection: $enabledFilter) {
                    ForEach(GestureEnabledFilter.allCases) { filter in
                        Text(L10n.string(filter.titleKey)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Spacer()

                Text(
                    String(
                        format: L10n.string("gestures.selectionCount"),
                        locale: L10n.locale,
                        selection.count,
                        displayedGestures.count
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding()
    }

    private var detailTitle: String {
        switch sidebarSelection {
        case .global:
            return L10n.string("scope.global")
        case .app(let bundleId):
            return AppInfoLookup.info(forBundleId: bundleId).name
        }
    }

    // MARK: - Table

    private var gestureTable: some View {
        Table(displayedGestures, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L10n.string("gestures.col.enabled")) { gesture in
                Toggle("", isOn: Binding(
                    get: { gesture.isEnabled },
                    set: { appState.configStore.setEnabled(id: gesture.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            .width(min: 52, ideal: 60, max: 70)

            TableColumn(L10n.string("gestures.col.pattern")) { gesture in
                GestureMiniPreview(points: gesture.pattern.freePathPoints)
                    .frame(width: 48, height: 28)
            }
            .width(min: 56, ideal: 64, max: 80)

            TableColumn(L10n.string("gestures.col.name"), value: \.name)

            TableColumn(L10n.string("gestures.col.trigger")) { gesture in
                Text(L10n.string(gesture.trigger.button.displayKey))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 80, max: 100)

            TableColumn(L10n.string("gestures.col.action")) { gesture in
                Text(actionLabel(for: gesture))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 180)

            // Scope column: useful for multi-app gestures that appear under one app.
            TableColumn(L10n.string("gestures.col.scope")) { gesture in
                GestureScopeCell(scope: gesture.scope)
            }
            .width(min: 72, ideal: 100, max: 160)
        }
        .contextMenu(forSelectionType: GestureProfile.ID.self) { ids in
            if !ids.isEmpty {
                Button(L10n.string("gestures.edit")) {
                    editSingle(from: ids)
                }
                .disabled(ids.count != 1)

                Button(L10n.string("gestures.duplicate")) {
                    duplicateSelected(ids)
                }
                .disabled(ids.count != 1)

                Divider()

                Button(L10n.string("gestures.enableSelected")) {
                    appState.configStore.setEnabled(ids: ids, enabled: true)
                }
                Button(L10n.string("gestures.disableSelected")) {
                    appState.configStore.setEnabled(ids: ids, enabled: false)
                }

                Divider()

                Button(L10n.string("gestures.export")) {
                    exportSelected(ids)
                }

                Divider()

                Button(L10n.string("gestures.delete"), role: .destructive) {
                    requestDelete(ids)
                }
            }
        } primaryAction: { ids in
            editSingle(from: ids)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button(allDisplayedSelected ? L10n.string("gestures.deselectAll") : L10n.string("gestures.selectAll")) {
                toggleSelectAllDisplayed()
            }
            .disabled(displayedGestures.isEmpty)

            Button(L10n.string("gestures.edit")) {
                editSingle(from: selection)
            }
            .disabled(selection.count != 1)

            Button(L10n.string("gestures.enableSelected")) {
                appState.configStore.setEnabled(ids: selection, enabled: true)
            }
            .disabled(selection.isEmpty)

            Button(L10n.string("gestures.disableSelected")) {
                appState.configStore.setEnabled(ids: selection, enabled: false)
            }
            .disabled(selection.isEmpty)

            Button(L10n.string("gestures.export")) {
                exportSelected(selection)
            }
            .disabled(selection.isEmpty)

            Button(L10n.string("gestures.delete"), role: .destructive) {
                requestDelete(selection)
            }
            .foregroundStyle(.red)
            .disabled(selection.isEmpty)

            Spacer()

            Button(L10n.string("gestures.test")) {
                isShowingGestureTest = true
            }

            Button(L10n.string("gestures.resetDefaults")) {
                selection.removeAll()
                appState.configStore.resetToDefaults()
                sidebarSelection = .global
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(chromeSurfaceColor)
    }

    // MARK: - Sidebar helpers

    private func makeNewProfile() -> GestureProfile {
        GestureProfile(
            name: L10n.string("gestures.newName"),
            pattern: .freePath([]),
            scope: GestureSidebarCatalog.defaultScope(for: sidebarSelection)
        )
    }

    private func selectSidebar(for scope: AppScope) {
        let item = GestureSidebarCatalog.preferredSidebarItem(for: scope)
        if case .app(let bundleId) = item {
            pinApp(bundleId)
        }
        sidebarSelection = item
    }

    private func pinApp(_ bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !pinnedAppBundleIds.contains(trimmed) {
            pinnedAppBundleIds.append(trimmed)
            Self.savePinnedApps(pinnedAppBundleIds)
        }
    }

    /// Remove an app from the sidebar.
    /// Empty pin: drop immediately. Otherwise confirm — single-app gestures are deleted;
    /// multi-app gestures only drop this bundle id from their scope.
    private func requestRemoveApp(_ bundleId: String) {
        let plan = GestureSidebarCatalog.planRemoveApp(
            bundleId,
            from: appState.configStore.gestures
        )
        if plan.isEmpty {
            removePinnedApp(bundleId)
            return
        }
        pendingRemoveAppBundleId = bundleId
        isConfirmingRemoveApp = true
    }

    private func confirmRemoveAppAndGestures(_ bundleId: String) {
        let plan = GestureSidebarCatalog.planRemoveApp(
            bundleId,
            from: appState.configStore.gestures
        )
        for profile in plan.profilesToUpdate {
            appState.configStore.update(profile)
        }
        if !plan.idsToDelete.isEmpty {
            appState.configStore.delete(ids: plan.idsToDelete)
            selection.subtract(plan.idsToDelete)
        }
        removePinnedApp(bundleId)
    }

    private func removePinnedApp(_ bundleId: String) {
        pinnedAppBundleIds.removeAll { $0 == bundleId }
        Self.savePinnedApps(pinnedAppBundleIds)
        // App drops out of the sidebar once unpinned and no remaining gestures reference it.
        if case .app(let selected) = sidebarSelection, selected == bundleId {
            let stillPresent = GestureSidebarCatalog.sidebarAppBundleIds(
                gestures: appState.configStore.gestures,
                pinnedBundleIds: pinnedAppBundleIds
            ).contains(bundleId)
            if !stillPresent {
                sidebarSelection = .global
            }
        }
    }

    private static func loadPinnedApps() -> [String] {
        UserDefaults.standard.stringArray(forKey: PreferenceKey.pinnedGestureAppBundleIds) ?? []
    }

    private static func savePinnedApps(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: PreferenceKey.pinnedGestureAppBundleIds)
    }

    // MARK: - Actions

    private func actionLabel(for gesture: GestureProfile) -> String {
        let type = L10n.string(gesture.action.summaryKey)
        return "\(type): \(gesture.action.detail)"
    }

    private func toggleSelectAllDisplayed() {
        let ids = Set(displayedGestures.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    private func editSingle(from ids: Set<GestureProfile.ID>) {
        guard ids.count == 1, let id = ids.first,
              let gesture = appState.configStore.gestures.first(where: { $0.id == id })
        else { return }
        editorProfile = gesture
    }

    private func requestDelete(_ ids: Set<GestureProfile.ID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        isConfirmingDelete = true
    }

    private func deleteSelected(_ ids: Set<GestureProfile.ID>) {
        guard !ids.isEmpty else { return }
        appState.configStore.delete(ids: ids)
        selection.subtract(ids)
    }

    private func duplicateSelected(_ ids: Set<GestureProfile.ID>) {
        guard let id = ids.first,
              let gesture = appState.configStore.gestures.first(where: { $0.id == id })
        else { return }
        var copy = gesture
        copy.id = UUID()
        copy.name = gesture.name + " " + L10n.string("gestures.copySuffix")
        appState.configStore.add(copy)
        selection = [copy.id]
    }

    // MARK: - Import / Export

    private func importGestures() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = L10n.string("gestures.import")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let analysis = try appState.configStore.analyzeImportPackage(from: data)
            let profilesToImport: [GestureProfile]
            if analysis.hasDuplicates {
                guard let policy = promptImportDuplicatePolicy(analysis) else { return }
                profilesToImport = analysis.profilesToImport(policy: policy)
            } else {
                profilesToImport = analysis.ordered
            }

            if profilesToImport.isEmpty {
                alertMessage = AlertMessage(
                    title: L10n.string("gestures.import"),
                    detail: L10n.string("gestures.importAllSkipped")
                )
                return
            }

            let newIDs = try appState.configStore.importProfiles(profilesToImport)
            selection = Set(newIDs)
            if let first = appState.configStore.gestures.first(where: { newIDs.contains($0.id) }) {
                selectSidebar(for: first.scope)
            }
        } catch {
            alertMessage = AlertMessage(
                title: L10n.string("gestures.importFailedTitle"),
                detail: importErrorDetail(error)
            )
        }
    }

    /// Returns chosen policy, or `nil` if the user cancelled.
    private func promptImportDuplicatePolicy(_ analysis: GestureImportAnalysis) -> GestureImportDuplicatePolicy? {
        let alert = NSAlert()
        alert.messageText = L10n.string("gestures.importDuplicatesTitle")
        alert.informativeText = importDuplicatesDetailText(analysis)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("gestures.importForce"))
        alert.addButton(withTitle: L10n.string("gestures.importSkipDuplicates"))
        alert.addButton(withTitle: L10n.string("common.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .forceAll
        case .alertSecondButtonReturn:
            return .skipDuplicates
        default:
            return nil
        }
    }

    private func importDuplicatesDetailText(_ analysis: GestureImportAnalysis) -> String {
        let summary = String(
            format: L10n.string("gestures.importDuplicatesMessage"),
            locale: L10n.locale,
            analysis.duplicates.count,
            analysis.totalCount
        )
        let list = duplicateNameList(analysis.duplicates)
        let footer = L10n.string("gestures.importDuplicatesFooter")
        return "\(summary)\n\n\(list)\n\n\(footer)"
    }

    /// Bullet list of duplicate names; truncates long lists for readable alerts.
    private func duplicateNameList(_ duplicates: [GestureProfile], limit: Int = 12) -> String {
        let names = duplicates.map(\.name)
        if names.count <= limit {
            return names.map { "• \($0)" }.joined(separator: "\n")
        }
        let shown = names.prefix(limit).map { "• \($0)" }
        let more = String(
            format: L10n.string("gestures.importDuplicatesMore"),
            locale: L10n.locale,
            names.count - limit
        )
        return (shown + [more]).joined(separator: "\n")
    }

    private func exportSelected(_ ids: Set<GestureProfile.ID>) {
        guard !ids.isEmpty else { return }

        let data: Data
        do {
            data = try appState.configStore.exportPackage(ids: ids)
        } catch {
            alertMessage = AlertMessage(
                title: L10n.string("gestures.exportFailedTitle"),
                detail: error.localizedDescription
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = L10n.string("gestures.export")
        panel.nameFieldStringValue = suggestedExportFilename(for: ids)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alertMessage = AlertMessage(
                title: L10n.string("gestures.exportFailedTitle"),
                detail: error.localizedDescription
            )
        }
    }

    private func suggestedExportFilename(for ids: Set<GestureProfile.ID>) -> String {
        let selected = appState.configStore.gestures.filter { ids.contains($0.id) }
        if selected.count == 1, let name = selected.first?.name {
            let sanitized = name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = sanitized.isEmpty ? L10n.string("gestures.exportDefaultFilename") : sanitized
            return "\(base).json"
        }
        return "\(L10n.string("gestures.exportDefaultFilename")).json"
    }

    private func importErrorDetail(_ error: Error) -> String {
        if let importError = error as? GestureImportExportError {
            switch importError {
            case .emptyPackage:
                return L10n.string("gestures.importEmpty")
            case .emptySelection, .persistFailed:
                return importError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Alert

private struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

// MARK: - Sidebar row (explicit light/dark selection + hover)

private struct GestureSidebarRow<Icon: View>: View {
    let title: String
    let count: Int
    let isSelected: Bool
    @ViewBuilder var icon: () -> Icon
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            // Accent tint readable in both schemes (avoids white-on-white from system sidebar style).
            return Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16)
        }
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
        }
        return .clear
    }
}

// MARK: - Scope cell (global label or app icons)

private struct GestureScopeCell: View {
    let scope: AppScope

    private let iconSize: CGFloat = 16
    private let maxVisibleIcons = 6

    var body: some View {
        switch scope {
        case .global:
            Text(L10n.string("scope.global"))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        case .apps(let bundleIds):
            if bundleIds.isEmpty {
                Text(L10n.string("scope.apps"))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                let infos = bundleIds.map { AppInfoLookup.info(forBundleId: $0) }
                let visible = Array(infos.prefix(maxVisibleIcons))
                let overflow = infos.count - visible.count

                HStack(spacing: 3) {
                    ForEach(visible) { app in
                        Image(nsImage: AppInfoLookup.icon(for: app.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: iconSize, height: iconSize)
                            .cornerRadius(3)
                            .help("\(app.name)\n\(app.displayPath)")
                    }
                    if overflow > 0 {
                        Text("+\(overflow)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .help(overflowHelp(infos: infos, skip: maxVisibleIcons))
                    }
                }
                .help(infos.map(\.name).joined(separator: ", "))
            }
        }
    }

    private func overflowHelp(infos: [AppInfoLookup.Info], skip: Int) -> String {
        infos.dropFirst(skip).map(\.name).joined(separator: ", ")
    }
}

// MARK: - Mini preview

private struct GestureMiniPreview: View {
    let points: [CodablePoint]

    @AppStorage(PreferenceKey.hudLineColor) private var lineColorHex = Constants.defaultHUDLineColorHex
    @AppStorage(PreferenceKey.hudShowStartPoint) private var showStartPoint = true
    @AppStorage(PreferenceKey.hudLineWidth) private var lineWidth = Double(Constants.defaultHUDLineWidth)

    private var lineColor: Color {
        if let ns = DrawingStyle.color(fromHex: lineColorHex) {
            return Color(nsColor: ns)
        }
        return DrawingStyle.lineSwiftUIColor
    }

    var body: some View {
        Canvas { context, size in
            let pts = points.map(\.cgPoint)
            guard !pts.isEmpty else {
                let r = CGRect(x: 4, y: size.height / 2 - 0.5, width: size.width - 8, height: 1)
                context.fill(Path(r), with: .color(.secondary.opacity(0.3)))
                return
            }
            let xs = pts.map(\.x)
            let ys = pts.map(\.y)
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 1
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 1
            let w = max(maxX - minX, 0.001)
            let h = max(maxY - minY, 0.001)
            let pad: CGFloat = 4
            let scale = min((size.width - pad * 2) / w, (size.height - pad * 2) / h)

            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(
                    x: pad + (p.x - minX) * scale,
                    y: size.height - pad - (p.y - minY) * scale
                )
            }

            if pts.count >= 2 {
                var path = Path()
                path.move(to: map(pts[0]))
                for p in pts.dropFirst() {
                    path.addLine(to: map(p))
                }
                let strokeWidth = max(1.2, min(lineWidth * 0.35, 2.5))
                context.stroke(
                    path,
                    with: .color(lineColor),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                )
            }

            if showStartPoint {
                let start = map(pts[0])
                let r: CGFloat = 3.5
                let circle = Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(.red))
                context.stroke(circle, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .id("\(lineColorHex)-\(showStartPoint)-\(lineWidth)")
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 1))
    }
}
