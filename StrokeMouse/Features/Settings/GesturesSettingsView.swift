import SwiftUI

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

    @State private var selection = Set<GestureProfile.ID>()
    @State private var editorProfile: GestureProfile?
    @State private var isShowingGestureTest = false
    @State private var searchText = ""
    @State private var enabledFilter: GestureEnabledFilter = .all
    @State private var sortOrder = [KeyPathComparator(\GestureProfile.name)]

    private var displayedGestures: [GestureProfile] {
        var items = appState.configStore.gestures

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

    var body: some View {
        let _ = appState.languageEpoch

        VStack(spacing: 0) {
            toolbar
            Divider()

            Group {
                if appState.configStore.gestures.isEmpty {
                    ContentUnavailableView(
                        L10n.string("gestures.emptyTitle"),
                        systemImage: "hand.draw",
                        description: Text(L10n.string("gestures.emptySubtitle"))
                    )
                } else if displayedGestures.isEmpty {
                    ContentUnavailableView(
                        L10n.string("gestures.filterEmptyTitle"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(L10n.string("gestures.filterEmptySubtitle"))
                    )
                } else {
                    gestureTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editorProfile) { profile in
            GestureEditorView(profile: profile) { updated in
                if appState.configStore.gestures.contains(where: { $0.id == updated.id }) {
                    appState.configStore.update(updated)
                } else {
                    appState.configStore.add(updated)
                }
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(L10n.string("gestures.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    editorProfile = GestureProfile(
                        name: L10n.string("gestures.newName"),
                        pattern: .freePath([])
                    )
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

    // MARK: - Table

    private var gestureTable: some View {
        Table(displayedGestures, selection: $selection, sortOrder: $sortOrder) {
            // Content-only columns (struct rows cannot use value: + custom content together).
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

            TableColumn(L10n.string("gestures.col.scope")) { gesture in
                Text(L10n.string(gesture.scope.summaryKey))
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 90)
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

                Button(L10n.string("gestures.delete"), role: .destructive) {
                    deleteSelected(ids)
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

            Button(L10n.string("gestures.delete"), role: .destructive) {
                deleteSelected(selection)
            }
            .disabled(selection.isEmpty)

            Spacer()

            Button(L10n.string("gestures.test")) {
                isShowingGestureTest = true
            }

            Button(L10n.string("gestures.resetDefaults")) {
                selection.removeAll()
                appState.configStore.resetToDefaults()
            }
        }
        .padding()
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

    private func deleteSelected(_ ids: Set<GestureProfile.ID>) {
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
