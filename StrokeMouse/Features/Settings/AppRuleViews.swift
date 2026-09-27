import AppKit
import SwiftUI

// MARK: - Suppressed global inputs control

/// Switch that suppresses global gestures, plus a menu to narrow the inputs.
struct SuppressedGlobalInputsControl: View {
    let title: String
    @Binding var value: SuppressedGlobalInputs

    var body: some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: Binding(
                get: { !value.isEmpty },
                set: { value = $0 ? .all : .none }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if !value.isEmpty {
                Menu {
                    ForEach(GestureInputKind.allCases) { kind in
                        Toggle(L10n.string(kind.displayKey), isOn: Binding(
                            get: { value.contains(kind) },
                            set: { isOn in
                                var kinds = value.kinds
                                if isOn {
                                    kinds.insert(kind)
                                } else {
                                    kinds.remove(kind)
                                }
                                value = SuppressedGlobalInputs(kinds: kinds)
                            }
                        ))
                    }
                } label: {
                    Text(Self.summary(of: value))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string("appRule.inputs.help"))
            }
        }
    }

    static func summary(of value: SuppressedGlobalInputs) -> String {
        if value.kinds.count == GestureInputKind.allCases.count {
            return L10n.string("appRule.inputs.all")
        }
        let names = GestureInputKind.allCases
            .filter(value.contains)
            .map { L10n.string($0.displayKey) }
        let formatter = ListFormatter()
        formatter.locale = L10n.locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }
}

// MARK: - Rule bar above the gesture table

/// Shows the app or group rule for the selected sidebar node.
struct AppScopeRuleBar: View {
    @Environment(AppState.self) private var appState
    let item: GestureSidebarItem
    var onEditGroup: (AppGroup) -> Void

    var body: some View {
        switch item {
        case .global:
            EmptyView()
        case .app(let bundleId):
            appRule(bundleId: bundleId)
        case .group(let groupID):
            if let group = appState.configStore.appGroup(id: groupID) {
                groupRule(group)
            }
        }
    }

    private func appRule(bundleId: String) -> some View {
        let matchingGroups = matchingGroupNames(for: bundleId)
        return VStack(alignment: .leading, spacing: 4) {
            SuppressedGlobalInputsControl(
                title: L10n.string("appRule.app.suppressGlobal"),
                value: Binding(
                    get: {
                        appState.configStore
                            .appPolicy(forBundleIdentifier: bundleId)?
                            .suppressedGlobalInputs ?? .none
                    },
                    set: {
                        appState.configStore.setSuppressedGlobalInputs(
                            $0,
                            forBundleIdentifier: bundleId
                        )
                    }
                )
            )
            Text(L10n.string("appRule.suppressHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !matchingGroups.isEmpty {
                Label(
                    String(
                        format: L10n.string("appRule.app.groupNote"),
                        locale: L10n.locale,
                        Self.list(matchingGroups)
                    ),
                    systemImage: "square.stack.3d.up"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func groupRule(_ group: AppGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if group.matchers.isEmpty {
                    Label(
                        L10n.string("appRule.group.emptyMatchers"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Text(AppGroupSummary.text(for: group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(AppGroupSummary.fullText(for: group))
                }
                SuppressedGlobalInputsControl(
                    title: L10n.string("appRule.group.suppressGlobal"),
                    value: Binding(
                        get: { group.suppressedGlobalInputs },
                        set: { newValue in
                            var updated = group
                            updated.suppressedGlobalInputs = newValue
                            appState.configStore.updateAppGroup(updated)
                        }
                    )
                )
                Text(L10n.string("appRule.suppressHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(L10n.string("appRule.group.edit")) {
                onEditGroup(group)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func matchingGroupNames(for bundleId: String) -> [String] {
        let groups = appState.configStore.appGroups
        guard !groups.isEmpty else { return [] }
        let rules = GestureAppRules(policies: [], groups: groups)
        let path = AppInfoLookup.info(forBundleId: bundleId).path
        let ids = rules.matchingGroupIDs(
            bundleIdentifier: bundleId,
            path: path.isEmpty ? nil : path
        )
        return groups.filter { ids.contains($0.id) }.map(\.name)
    }

    static func list(_ names: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = L10n.locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }
}

// MARK: - Group summary text

enum AppGroupSummary {
    private static let maxItems = 3

    static func items(for group: AppGroup) -> [String] {
        group.matchers.map { matcher in
            switch matcher.kind {
            case .bundleIdentifier:
                return AppInfoLookup.info(forBundleId: matcher.value).name
            case .bundleIdentifierPattern:
                return matcher.value
            case .directory:
                return (matcher.value as NSString).abbreviatingWithTildeInPath
            }
        }
    }

    static func text(for group: AppGroup) -> String {
        let all = items(for: group)
        let visible = all.prefix(maxItems).joined(separator: " · ")
        let overflow = all.count - min(all.count, maxItems)
        return overflow > 0 ? "\(visible) · +\(overflow)" : visible
    }

    static func fullText(for group: AppGroup) -> String {
        items(for: group).joined(separator: "\n")
    }
}

// MARK: - Group editor

struct AppGroupEditorView: View {
    let isNew: Bool
    var onSave: (AppGroup) -> Void
    var onCancel: () -> Void

    @State private var draft: AppGroup
    @State private var patternText = ""
    @State private var isShowingAppPicker = false
    @State private var preview: [AppInfoLookup.Info] = []
    @State private var isLoadingPreview = false

    init(
        group: AppGroup,
        isNew: Bool,
        onSave: @escaping (AppGroup) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: group)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var appMatchers: [AppMatcher] {
        draft.matchers.filter { $0.kind == .bundleIdentifier }
    }

    private var patternMatchers: [AppMatcher] {
        draft.matchers.filter { $0.kind == .bundleIdentifierPattern }
    }

    private var directoryMatchers: [AppMatcher] {
        draft.matchers.filter { $0.kind == .directory }
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pendingPattern: String? {
        AppMatching.normalizedPattern(patternText)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.string(isNew ? "appGroup.editor.newTitle" : "appGroup.editor.editTitle"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            Form {
                Section {
                    TextField(
                        L10n.string("appGroup.editor.name"),
                        text: $draft.name,
                        prompt: Text(L10n.string("appGroup.editor.namePlaceholder"))
                    )
                }

                appsSection
                patternsSection
                directoriesSection

                Section(L10n.string("appGroup.editor.globalGestures")) {
                    SuppressedGlobalInputsControl(
                        title: L10n.string("appRule.group.suppressGlobal"),
                        value: $draft.suppressedGlobalInputs
                    )
                    Text(L10n.string("appRule.suppressHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                previewSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(L10n.string("common.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("common.save")) {
                    var saved = draft
                    saved.name = trimmedName
                    onSave(saved)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 640, idealHeight: 720)
        .sheet(isPresented: $isShowingAppPicker) {
            InstalledAppPickerSheet(
                mode: .multi(alreadySelected: Set(appMatchers.map(\.value))),
                onConfirm: { apps in
                    for app in apps {
                        add(.bundleIdentifier(app.bundleId))
                    }
                    isShowingAppPicker = false
                },
                onCancel: { isShowingAppPicker = false }
            )
        }
        .task(id: draft.matchers) {
            await refreshPreview()
        }
    }

    private var appsSection: some View {
        Section(L10n.string("appGroup.editor.apps")) {
            if appMatchers.isEmpty {
                Text(L10n.string("appGroup.editor.appsEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appMatchers, id: \.self) { matcher in
                    SelectedAppRow(
                        app: AppInfoLookup.info(forBundleId: matcher.value),
                        onRemove: { remove(matcher) }
                    )
                }
            }
            Button {
                isShowingAppPicker = true
            } label: {
                Label(L10n.string("appGroup.editor.addApps"), systemImage: "plus.circle")
            }
        }
    }

    private var patternsSection: some View {
        Section {
            ForEach(patternMatchers, id: \.self) { matcher in
                HStack {
                    Text(matcher.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    if AppMatching.isWildcardOnly(matcher.value) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(L10n.string("appGroup.editor.patternMatchesAll"))
                    }
                    Spacer()
                    removeButton { remove(matcher) }
                }
            }
            HStack {
                TextField(
                    L10n.string("appGroup.editor.patterns"),
                    text: $patternText,
                    prompt: Text(verbatim: "com.adobe.*")
                )
                .labelsHidden()
                .font(.body.monospaced())
                .onSubmit(addPattern)
                Button(L10n.string("appGroup.editor.addPattern"), action: addPattern)
                    .disabled(pendingPattern == nil)
            }
            if !patternText.isEmpty, pendingPattern == nil {
                Text(L10n.string("appGroup.editor.patternInvalid"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let pendingPattern, AppMatching.isWildcardOnly(pendingPattern) {
                Text(L10n.string("appGroup.editor.patternMatchesAll"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(L10n.string("appGroup.editor.patterns"))
        } footer: {
            Text(L10n.string("appGroup.editor.patternHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var directoriesSection: some View {
        Section {
            ForEach(directoryMatchers, id: \.self) { matcher in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text((matcher.value as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(matcher.value)
                    Spacer()
                    removeButton { remove(matcher) }
                }
            }
            Button {
                chooseDirectory()
            } label: {
                Label(L10n.string("appGroup.editor.addDirectory"), systemImage: "folder.badge.plus")
            }
        } header: {
            Text(L10n.string("appGroup.editor.directories"))
        } footer: {
            Text(L10n.string("appGroup.editor.directoryHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Section(L10n.string("appGroup.editor.preview")) {
            if isLoadingPreview {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if preview.isEmpty {
                Text(L10n.string("appGroup.editor.previewEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    String(
                        format: L10n.string("appGroup.editor.previewCount"),
                        locale: L10n.locale,
                        preview.count
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(preview, id: \.path) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: AppInfoLookup.icon(for: app.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                        Text(app.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(app.bundleId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(app.displayPath)
                }
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(L10n.string("editor.scopeRemoveApp"))
    }

    private func add(_ matcher: AppMatcher) {
        let key = matcher.value.lowercased()
        guard !draft.matchers.contains(where: {
            $0.kind == matcher.kind && $0.value.lowercased() == key
        }) else {
            return
        }
        draft.matchers.append(matcher)
    }

    private func remove(_ matcher: AppMatcher) {
        draft.matchers.removeAll { $0 == matcher }
    }

    private func addPattern() {
        guard let pattern = pendingPattern else { return }
        add(.bundleIdentifierPattern(pattern))
        patternText = ""
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = L10n.string("appGroup.editor.chooseDirectoryPrompt")
        panel.message = L10n.string("appGroup.editor.directoryHelp")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(.directory(url.standardizedFileURL.path))
        }
    }

    private func refreshPreview() async {
        let group = draft
        guard !group.matchers.isEmpty else {
            preview = []
            isLoadingPreview = false
            return
        }
        isLoadingPreview = true
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> AppInfoLookup.Info? in
            guard app.activationPolicy == .regular,
                  let url = app.bundleURL ?? app.executableURL
            else {
                return nil
            }
            return AppInfoLookup.Info(
                bundleId: app.bundleIdentifier ?? "",
                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                path: url.path
            )
        }
        let matches = await Task.detached(priority: .userInitiated) {
            AppGroupPreview.matches(for: group, running: running)
        }.value
        guard !Task.isCancelled else { return }
        preview = matches
        isLoadingPreview = false
    }
}

/// Installed (and running) applications matched by a draft group.
enum AppGroupPreview {
    static func matches(
        for group: AppGroup,
        running: [AppInfoLookup.Info]
    ) -> [AppInfoLookup.Info] {
        let rules = GestureAppRules(policies: [], groups: [group])
        let directories = group.matchers
            .filter { $0.kind == .directory }
            .compactMap { AppMatching.normalizedDirectory($0.value) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        var candidates = AppInfoLookup.scanInstalledApps()
        candidates += AppInfoLookup.scanApplications(in: directories, maxDepth: 3)
        candidates += running

        var seenPaths = Set<String>()
        var result: [AppInfoLookup.Info] = []
        for app in candidates {
            let pathKey = app.path.lowercased()
            guard !pathKey.isEmpty, seenPaths.insert(pathKey).inserted else { continue }
            let bundleIdentifier = app.bundleId.isEmpty ? nil : app.bundleId
            if rules.groupContains(
                group.id,
                bundleIdentifier: bundleIdentifier,
                path: app.path
            ) {
                result.append(app)
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
