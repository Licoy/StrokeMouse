import SwiftUI

struct SyncSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var provider = SyncProviderKind.defaultSelection
    @State private var gistIDOrURL = ""
    @State private var webDAVURL = ""
    @State private var webDAVUsername = ""
    @State private var deviceName = Host.current().localizedName
        ?? ProcessInfo.processInfo.hostName
    @State private var scope = SyncScope.gesturesOnly
    @State private var encryption = BackupEncryptionKind.none
    @State private var automaticBackupEnabled = false
    @State private var providerSecret = ""
    @State private var encryptionPassword = ""
    @State private var encryptionPasswordConfirmation = ""
    @State private var confirmsPlaintextRisk = false
    @State private var confirmsGistVisibilityRisk = false
    @State private var confirmsInsecureHTTP = false
    @State private var confirmedInsecureHTTPURL: String?
    @State private var showsHTTPRiskConfirmation = false
    @State private var confirmsDisconnect = false
    @State private var selectedDeviceID: UUID?

    @State private var gestureDecisions: [UUID: BackupGestureConflictDecision] = [:]
    @State private var duplicateDecisions: [UUID: BackupContentDuplicatePolicy] = [:]
    @State private var settingDecisions: [String: BackupSettingConflictDecision] = [:]
    @State private var pendingRestoreKind: PendingRestoreKind?
    @State private var showsRestoreConfirmation = false
    @State private var confirmsScriptRestore = false
    @State private var confirmsTrackpadRestore = false

    @State private var showsPasswordPrompt = false
    @State private var decryptionPassword = ""
    @State private var decryptionError: String?
    @State private var remembersDecryptionPassword = true

    private var sync: ConfigurationSync { appState.configurationSync }

    var body: some View {
        Form {
            connectionSection
            backupPolicySection
            statusSection
            historySection
            previewSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: hydrateDraft)
        .onChange(of: sync.state.connection) { _, _ in hydrateDraft() }
        .onChange(of: sync.state.pendingDecryptionID) { _, value in
            showsPasswordPrompt = value != nil
            if value == nil { decryptionError = nil }
        }
        .onChange(of: sync.history.preview?.backupID) { _, _ in
            initializeMergeDecisions()
        }
        .confirmationDialog(
            L10n.string("sync.disconnect.title"),
            isPresented: $confirmsDisconnect,
            titleVisibility: .visible
        ) {
            Button(L10n.string("sync.disconnect.confirm"), role: .destructive) {
                Task { _ = await sync.handle(.disconnect) }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("sync.disconnect.message"))
        }
        .confirmationDialog(
            L10n.string("sync.webdav.httpTitle"),
            isPresented: $showsHTTPRiskConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                L10n.string("sync.webdav.httpContinue"),
                role: .destructive
            ) {
                confirmsInsecureHTTP = true
                confirmedInsecureHTTPURL = normalizedWebDAVURL
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("sync.webdav.httpWarning"))
        }
        .sheet(isPresented: $showsPasswordPrompt) {
            decryptionSheet
        }
        .sheet(isPresented: $showsRestoreConfirmation) {
            restoreConfirmationSheet
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            Picker(L10n.string("sync.provider"), selection: $provider) {
                Text(L10n.string("sync.provider.gist"))
                    .tag(SyncProviderKind.githubGist)
                Text(L10n.string("sync.provider.webdav"))
                    .tag(SyncProviderKind.webDAV)
            }
            .disabled(sync.state.connection != nil)

            if provider == .githubGist {
                TextField(
                    L10n.string("sync.gist.id"),
                    text: $gistIDOrURL,
                    prompt: Text(L10n.string("sync.gist.idPrompt"))
                )
                SecureField(
                    L10n.string("sync.gist.token"),
                    text: $providerSecret,
                    prompt: secretPrompt
                )
                Text(L10n.string("sync.gist.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !gistIDOrURL.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Toggle(
                        L10n.string("sync.gist.visibilityConfirmation"),
                        isOn: $confirmsGistVisibilityRisk
                    )
                    .toggleStyle(.checkbox)
                }
            } else {
                TextField(
                    L10n.string("sync.webdav.url"),
                    text: webDAVURLBinding,
                    prompt: Text("https://dav.example.com/user/")
                )
                TextField(
                    L10n.string("sync.webdav.username"),
                    text: $webDAVUsername
                )
                SecureField(
                    L10n.string("sync.webdav.password"),
                    text: $providerSecret,
                    prompt: secretPrompt
                )
                Text(L10n.string("sync.webdav.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isInsecureWebDAVURL {
                    Toggle(
                        L10n.string("sync.webdav.httpConfirmation"),
                        isOn: insecureHTTPConfirmationBinding
                    )
                    .toggleStyle(.checkbox)
                    Text(L10n.string("sync.webdav.httpWarning"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            TextField(L10n.string("sync.deviceName"), text: $deviceName)

            HStack {
                Button(L10n.string("sync.saveConnection")) {
                    saveConnection(backsUpImmediately: false)
                }
                Button(L10n.string("sync.connectAndBackup")) {
                    saveConnection(backsUpImmediately: true)
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(!canSaveConnection || sync.state.isBusy)
        } header: {
            Text(L10n.string("sync.connection"))
        } footer: {
            Text(L10n.string("sync.singleProviderFooter"))
        }
    }

    @ViewBuilder
    private var backupPolicySection: some View {
        Section {
            Picker(L10n.string("sync.scope"), selection: $scope) {
                Text(L10n.string("sync.scope.gestures"))
                    .tag(SyncScope.gesturesOnly)
                Text(L10n.string("sync.scope.all"))
                    .tag(SyncScope.allConfiguration)
            }

            Picker(L10n.string("sync.encryption"), selection: $encryption) {
                Text(L10n.string("sync.encryption.none"))
                    .tag(BackupEncryptionKind.none)
                Text(L10n.string("sync.encryption.aes"))
                    .tag(BackupEncryptionKind.aes256GCM)
            }

            if encryption == .none {
                Text(L10n.string("sync.plaintext.warning"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Toggle(
                    L10n.string("sync.plaintext.confirmation"),
                    isOn: $confirmsPlaintextRisk
                )
                .toggleStyle(.checkbox)
            } else {
                SecureField(
                    L10n.string("sync.encryption.password"),
                    text: $encryptionPassword,
                    prompt: encryptionSecretPrompt
                )
                SecureField(
                    L10n.string("sync.encryption.confirmPassword"),
                    text: $encryptionPasswordConfirmation
                )
                Text(L10n.string("sync.encryption.passwordHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !passwordsMatch {
                    Text(L10n.string("sync.encryption.passwordMismatch"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Toggle(
                L10n.string("sync.automatic"),
                isOn: $automaticBackupEnabled
            )
            Text(L10n.string("sync.automatic.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.string("sync.remoteGrowthWarning"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.string("sync.backupPolicy"))
        } footer: {
            Text(L10n.string("sync.uploadOnlyFooter"))
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if let connection = sync.state.connection {
                LabeledContent(L10n.string("sync.status.connection")) {
                    Text(providerTitle(connection.provider))
                }
                LabeledContent(L10n.string("sync.status.destination")) {
                    Text(connection.destination)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent(L10n.string("sync.status.secret")) {
                    Text(connection.hasStoredProviderSecret
                         ? L10n.string("sync.status.saved")
                         : L10n.string("sync.status.missing"))
                }
            } else {
                Text(L10n.string("sync.status.disconnected"))
                    .foregroundStyle(.secondary)
            }

            LabeledContent(L10n.string("sync.status.pending")) {
                Text(sync.state.hasPendingBackup
                     ? L10n.string("sync.status.pendingYes")
                     : L10n.string("sync.status.pendingNo"))
            }
            if let success = sync.state.lastSuccess {
                LabeledContent(L10n.string("sync.status.lastSuccess")) {
                    Text(format(success.date))
                }
            }
            if let next = sync.state.nextHourlyCheck {
                LabeledContent(L10n.string("sync.status.nextCheck")) {
                    Text(format(next))
                }
            }
            if let failure = sync.state.lastFailure {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("sync.status.lastError"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(failure.message)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            if let rollback = sync.state.lastRollbackURL {
                LabeledContent(L10n.string("sync.status.rollback")) {
                    Text(rollback.path)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Button(L10n.string("sync.backupNow")) {
                    Task { _ = await sync.handle(.backupNow) }
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.string("sync.refreshHistory")) {
                    refreshHistory()
                }
                Button(L10n.string("sync.disconnect"), role: .destructive) {
                    confirmsDisconnect = true
                }
                Spacer()
                if sync.state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text(activityTitle(sync.state.activity))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(sync.state.connection == nil || sync.state.isBusy)
        } header: {
            Text(L10n.string("sync.status"))
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if !historyDevices.isEmpty {
                Picker(
                    L10n.string("sync.history.deviceFilter"),
                    selection: $selectedDeviceID
                ) {
                    Text(L10n.string("sync.history.allDevices"))
                        .tag(nil as UUID?)
                    ForEach(historyDevices, id: \.id) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
            }

            if filteredHistory.isEmpty {
                Text(L10n.string("sync.history.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredHistory) { item in
                    historyRow(item)
                }
            }
            if sync.history.nextCursor != nil {
                Button(L10n.string("sync.history.loadMore")) {
                    loadMoreHistory()
                }
                .disabled(sync.state.isBusy)
            }
        } header: {
            Text(L10n.string("sync.history"))
        } footer: {
            Text(L10n.string("sync.history.footer"))
        }
    }

    @ViewBuilder
    private func historyRow(_ item: RemoteBackupHistoryItem) -> some View {
        Button {
            preview(item.id, attempt: nil)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.encryption == .aes256GCM
                      ? "lock.fill" : "doc.text")
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if let metadata = item.metadata {
                        Text(metadata.deviceName)
                        Text(historyDetail(metadata, encryption: item.encryption))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(format(item.providerCreatedAt))
                        if let error = item.inspectionError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sync.state.isBusy
                  || (item.metadata == nil && item.inspectionError != nil))
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = sync.history.preview {
            Section {
                LabeledContent(L10n.string("sync.preview.device")) {
                    Text(preview.metadata.deviceName)
                }
                LabeledContent(L10n.string("sync.preview.time")) {
                    Text(format(preview.metadata.createdAt))
                }
                LabeledContent(L10n.string("sync.preview.gestures")) {
                    Text("\(preview.backupGestureCount)")
                }
                LabeledContent(L10n.string("sync.preview.localGestures")) {
                    Text("\(preview.localGestureCount)")
                }
                LabeledContent(L10n.string("sync.preview.addedByMerge")) {
                    Text("\(preview.gesturesAddedByMerge)")
                }
                if preview.metadata.scope == .allConfiguration {
                    Text(L10n.string("sync.preview.includesSettings"))
                        .foregroundStyle(.secondary)
                }
                if preview.containsScripts {
                    Label(
                        L10n.string("sync.preview.scriptWarning"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                if preview.containsExperimentalTrackpadGestures {
                    Label(
                        L10n.string("sync.preview.trackpadWarning"),
                        systemImage: "hand.raised.fingers.spread.fill"
                    )
                    .foregroundStyle(.orange)
                }

                mergeControls(preview)

                HStack {
                    Button(L10n.string("sync.restore.overwrite"), role: .destructive) {
                        beginRestore(.overwrite)
                    }
                    Button(L10n.string("sync.restore.merge")) {
                        beginRestore(.merge)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!mergeDecisionsComplete(preview))
                }
                .disabled(sync.state.isBusy)
            } header: {
                Text(L10n.string("sync.preview"))
            } footer: {
                Text(L10n.string("sync.restore.footer"))
            }
        }
    }

    @ViewBuilder
    private func mergeControls(_ preview: BackupPreviewState) -> some View {
        if !preview.gestureConflicts.isEmpty {
            Text(L10n.string("sync.merge.gestureConflicts"))
                .font(.headline)
            ForEach(preview.gestureConflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(L10n.string("sync.merge.localValue")) {
                        Text(conflict.localName)
                    }
                    LabeledContent(L10n.string("sync.merge.backupValue")) {
                        Text(conflict.backupName)
                    }
                    Picker(
                        "",
                        selection: optionalGestureDecisionBinding(conflict.id)
                    ) {
                        Text(L10n.string("sync.merge.choose"))
                            .tag(nil as BackupGestureConflictDecision?)
                        Text(L10n.string("sync.merge.keepLocal"))
                            .tag(Optional(BackupGestureConflictDecision.keepLocal))
                        Text(L10n.string("sync.merge.useBackup"))
                            .tag(Optional(BackupGestureConflictDecision.useBackup))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }

        if !preview.contentDuplicates.isEmpty {
            Text(L10n.string("sync.merge.contentDuplicates"))
                .font(.headline)
            ForEach(preview.contentDuplicates) { duplicate in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(L10n.string("sync.merge.localValue")) {
                        Text(duplicate.matchingLocalName)
                    }
                    LabeledContent(L10n.string("sync.merge.backupValue")) {
                        Text(duplicate.backupName)
                    }
                    Picker("", selection: duplicateDecisionBinding(duplicate.id)) {
                        Text(L10n.string("sync.merge.skipDuplicate"))
                            .tag(BackupContentDuplicatePolicy.skip)
                        Text(L10n.string("sync.merge.addDisabledCopy"))
                            .tag(BackupContentDuplicatePolicy.keepDisabledCopy)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }

        if !preview.settingConflicts.isEmpty {
            Text(L10n.string("sync.merge.settingConflicts"))
                .font(.headline)
            ForEach(preview.settingConflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(settingTitle(conflict.key))
                        .font(.subheadline.weight(.medium))
                    LabeledContent(L10n.string("sync.merge.localValue")) {
                        Text(settingValue(conflict.localValue, key: conflict.key))
                            .textSelection(.enabled)
                    }
                    LabeledContent(L10n.string("sync.merge.backupValue")) {
                        Text(settingValue(conflict.backupValue, key: conflict.key))
                            .textSelection(.enabled)
                    }
                    Picker("", selection: settingDecisionBinding(conflict.key)) {
                        Text(L10n.string("sync.merge.keepLocal"))
                            .tag(BackupSettingConflictDecision.keepLocal)
                        Text(L10n.string("sync.merge.useBackup"))
                            .tag(BackupSettingConflictDecision.useBackup)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var decryptionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("sync.password.title"))
                .font(.title2.weight(.semibold))
            Text(L10n.string("sync.password.message"))
                .foregroundStyle(.secondary)
            SecureField(
                L10n.string("sync.password.field"),
                text: $decryptionPassword
            )
            if let decryptionError {
                Text(decryptionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle(
                L10n.string("sync.password.remember"),
                isOn: $remembersDecryptionPassword
            )
            HStack {
                Spacer()
                Button(L10n.string("common.cancel")) {
                    showsPasswordPrompt = false
                    decryptionPassword = ""
                    decryptionError = nil
                }
                Button(L10n.string("sync.password.retry")) {
                    retryDecryption()
                }
                .buttonStyle(.borderedProminent)
                .disabled(decryptionPassword.isEmpty || sync.state.isBusy)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var restoreConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(restoreConfirmationTitle)
                .font(.title2.weight(.semibold))
            Text(L10n.string("sync.restore.confirmMessage"))
                .foregroundStyle(.secondary)
            if let preview = sync.history.preview, preview.containsScripts {
                Text(privilegedGestureRiskSummary(preview))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(privilegedGestureNameList(preview))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                Toggle(
                    L10n.string("sync.restore.confirmScripts"),
                    isOn: $confirmsScriptRestore
                )
                .toggleStyle(.checkbox)
            }
            if requiresTrackpadRestoreConfirmation {
                Text(L10n.string("trackpad.consent.message"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(
                    L10n.string("sync.restore.confirmTrackpad"),
                    isOn: $confirmsTrackpadRestore
                )
                .toggleStyle(.checkbox)
            }
            Text(L10n.string("sync.restore.rollbackHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.string("common.cancel")) {
                    showsRestoreConfirmation = false
                }
                Button(
                    pendingRestoreKind == .overwrite
                        ? L10n.string("sync.restore.overwrite")
                        : L10n.string("sync.restore.merge"),
                    role: pendingRestoreKind == .overwrite ? .destructive : nil
                ) {
                    performRestore()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!restoreRisksConfirmed || sync.state.isBusy)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var secretPrompt: Text {
        Text(sync.state.connection?.hasStoredProviderSecret == true
             ? L10n.string("sync.secret.savedPrompt")
             : L10n.string("sync.secret.requiredPrompt"))
    }

    private var encryptionSecretPrompt: Text {
        Text(sync.state.connection?.encryption == .aes256GCM
             ? L10n.string("sync.secret.keepEncryptionPrompt")
             : L10n.string("sync.secret.requiredPrompt"))
    }

    private var isInsecureWebDAVURL: Bool {
        normalizedWebDAVURL
            .lowercased().hasPrefix("http://")
    }

    private var normalizedWebDAVURL: String {
        webDAVURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var webDAVURLBinding: Binding<String> {
        Binding(
            get: { webDAVURL },
            set: { value in
                guard value != webDAVURL else { return }
                webDAVURL = value
                confirmsInsecureHTTP = false
                confirmedInsecureHTTPURL = nil
            }
        )
    }

    private var insecureHTTPConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                confirmsInsecureHTTP
                    && confirmedInsecureHTTPURL == normalizedWebDAVURL
            },
            set: { value in
                if value {
                    showsHTTPRiskConfirmation = true
                } else {
                    confirmsInsecureHTTP = false
                    confirmedInsecureHTTPURL = nil
                }
            }
        )
    }

    private var passwordsMatch: Bool {
        encryptionPassword == encryptionPasswordConfirmation
    }

    private var canSaveConnection: Bool {
        guard !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              passwordsMatch
        else { return false }
        if provider == .webDAV {
            guard !webDAVURL.isEmpty, !webDAVUsername.isEmpty else { return false }
        }
        if sync.state.connection?.hasStoredProviderSecret != true,
           providerSecret.isEmpty
        {
            return false
        }
        if encryption == .aes256GCM,
           sync.state.connection?.encryption != .aes256GCM,
           encryptionPassword.isEmpty
        {
            return false
        }
        return encryption == .none ? confirmsPlaintextRisk : true
    }

    private var filteredHistory: [RemoteBackupHistoryItem] {
        guard let selectedDeviceID else { return sync.history.items }
        return sync.history.items.filter {
            $0.metadata?.deviceID == selectedDeviceID
        }
    }

    private var historyDevices: [(id: UUID, name: String)] {
        var values: [UUID: String] = [:]
        for item in sync.history.items {
            if let metadata = item.metadata {
                values[metadata.deviceID] = metadata.deviceName
            }
        }
        return values.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var restoreRisksConfirmed: Bool {
        guard let preview = sync.history.preview else { return false }
        return (!preview.containsScripts || confirmsScriptRestore)
            && (!requiresTrackpadRestoreConfirmation
                || confirmsTrackpadRestore)
    }

    private var requiresTrackpadRestoreConfirmation: Bool {
        sync.history.preview?.containsExperimentalTrackpadGestures == true
            && !UserDefaults.standard.bool(
                forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
            )
    }

    private var restoreConfirmationTitle: String {
        pendingRestoreKind == .overwrite
            ? L10n.string("sync.restore.overwriteTitle")
            : L10n.string("sync.restore.mergeTitle")
    }

    private func hydrateDraft() {
        guard let connection = sync.state.connection else { return }
        provider = connection.provider
        gistIDOrURL = connection.gistID ?? ""
        webDAVURL = connection.webDAVBaseURL ?? ""
        webDAVUsername = connection.webDAVUsername ?? ""
        deviceName = connection.deviceName
        scope = connection.scope
        encryption = connection.encryption
        automaticBackupEnabled = connection.automaticBackupEnabled
        confirmsPlaintextRisk = connection.encryption == .none
        confirmsGistVisibilityRisk = connection.gistID != nil
        confirmsInsecureHTTP = connection.usesInsecureHTTP
        confirmedInsecureHTTPURL = connection.usesInsecureHTTP
            ? connection.webDAVBaseURL : nil
        providerSecret = ""
        encryptionPassword = ""
        encryptionPasswordConfirmation = ""
    }

    private func makeDraft() -> SyncConnectionDraft {
        SyncConnectionDraft(
            provider: provider,
            gistIDOrURL: gistIDOrURL,
            webDAVURL: webDAVURL,
            webDAVUsername: webDAVUsername,
            deviceName: deviceName,
            scope: scope,
            encryption: encryption,
            automaticBackupEnabled: automaticBackupEnabled,
            confirmsPlaintextRisk: confirmsPlaintextRisk,
            confirmsExistingGistVisibilityRisk: confirmsGistVisibilityRisk,
            confirmsInsecureHTTP: confirmsInsecureHTTP,
            confirmedInsecureHTTPURL: confirmedInsecureHTTPURL
        )
    }

    private func saveConnection(backsUpImmediately: Bool) {
        let secrets = SyncSecretChanges(
            providerSecret: providerSecret.isEmpty ? nil : providerSecret,
            encryptionPassword: encryptionPassword.isEmpty
                ? nil : encryptionPassword
        )
        let draft = makeDraft()
        Task {
            let result = await sync.handle(.saveConnection(draft, secrets))
            guard case .success = result else { return }
            providerSecret = ""
            encryptionPassword = ""
            encryptionPasswordConfirmation = ""
            if backsUpImmediately {
                _ = await sync.handle(.backupNow)
            }
        }
    }

    private func refreshHistory() {
        Task {
            _ = await sync.handle(.loadHistory(BackupHistoryQuery(limit: 20)))
        }
    }

    private func loadMoreHistory() {
        guard let cursor = sync.history.nextCursor else { return }
        Task {
            _ = await sync.handle(.loadHistory(
                BackupHistoryQuery(cursor: cursor, limit: 20)
            ))
        }
    }

    private func preview(
        _ id: RemoteBackupID,
        attempt: DecryptionAttempt?
    ) {
        Task {
            let result = await sync.handle(.preview(id, attempt))
            if case .requiresDecryption = result {
                decryptionError = nil
                showsPasswordPrompt = true
            }
        }
    }

    private func retryDecryption() {
        guard let id = sync.state.pendingDecryptionID else { return }
        let attempt = DecryptionAttempt(
            password: decryptionPassword,
            savesOnThisMac: remembersDecryptionPassword
        )
        Task {
            let result = await sync.handle(.preview(id, attempt))
            switch result {
            case .success:
                decryptionPassword = ""
                decryptionError = nil
                showsPasswordPrompt = false
            case .failure(let message):
                decryptionError = message
            default:
                break
            }
        }
    }

    private func initializeMergeDecisions() {
        gestureDecisions = [:]
        duplicateDecisions = [:]
        settingDecisions = [:]
        guard let preview = sync.history.preview else { return }
        for duplicate in preview.contentDuplicates {
            duplicateDecisions[duplicate.id] = .skip
        }
        for setting in preview.settingConflicts {
            settingDecisions[setting.key] = .keepLocal
        }
    }

    private func optionalGestureDecisionBinding(
        _ id: UUID
    ) -> Binding<BackupGestureConflictDecision?> {
        Binding(
            get: { gestureDecisions[id] },
            set: { gestureDecisions[id] = $0 }
        )
    }

    private func duplicateDecisionBinding(
        _ id: UUID
    ) -> Binding<BackupContentDuplicatePolicy> {
        Binding(
            get: { duplicateDecisions[id] ?? .skip },
            set: { duplicateDecisions[id] = $0 }
        )
    }

    private func settingDecisionBinding(
        _ key: String
    ) -> Binding<BackupSettingConflictDecision> {
        Binding(
            get: { settingDecisions[key] ?? .keepLocal },
            set: { settingDecisions[key] = $0 }
        )
    }

    private func mergeDecisionsComplete(_ preview: BackupPreviewState) -> Bool {
        preview.gestureConflicts.allSatisfy {
            gestureDecisions[$0.id] != nil
        }
    }

    private func beginRestore(_ kind: PendingRestoreKind) {
        pendingRestoreKind = kind
        confirmsScriptRestore = false
        confirmsTrackpadRestore = false
        showsRestoreConfirmation = true
    }

    private func performRestore() {
        guard let preview = sync.history.preview,
              let pendingRestoreKind
        else { return }
        let mode: SyncRestoreMode
        switch pendingRestoreKind {
        case .overwrite:
            mode = .overwrite
        case .merge:
            var decisions = BackupMergeDecisions()
            decisions.gestures = gestureDecisions
            decisions.contentDuplicates = duplicateDecisions
            decisions.settings = settingDecisions
            mode = .merge(
                decisions: decisions,
                defaultDuplicatePolicy: .skip
            )
        }
        let request = RestoreRequest(
            backupID: preview.backupID,
            mode: mode,
            confirmsScriptRisk: confirmsScriptRestore,
            confirmsExperimentalTrackpadRisk: confirmsTrackpadRestore
        )
        showsRestoreConfirmation = false
        Task { _ = await sync.handle(.restore(request)) }
    }

    private func providerTitle(_ provider: SyncProviderKind) -> String {
        L10n.string(provider == .githubGist
                    ? "sync.provider.gist" : "sync.provider.webdav")
    }

    private func activityTitle(_ activity: SyncActivity) -> String {
        L10n.string("sync.activity.\(activity.rawValue)")
    }

    private func format(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(appState.resolvedLocale)
        )
    }

    private func historyDetail(
        _ metadata: BackupMetadataV1,
        encryption: BackupEncryptionKind?
    ) -> String {
        let kind = L10n.string("sync.kind.\(metadata.kind.rawValue)")
        let scope = L10n.string(metadata.scope == .gesturesOnly
                                ? "sync.scope.gestures" : "sync.scope.all")
        return "\(format(metadata.createdAt)) · \(kind) · \(scope) · \(encryptionTitle(encryption)) · v\(metadata.appVersion)"
    }

    private func encryptionTitle(_ encryption: BackupEncryptionKind?) -> String {
        switch encryption {
        case .some(.none):
            return L10n.string("sync.encryption.none")
        case .some(.aes256GCM):
            return L10n.string("sync.encryption.aes")
        case nil:
            return L10n.string("sync.encryption.unknown")
        }
    }

    private func settingTitle(_ key: String) -> String {
        let existingKeys: [String: String] = [
            "minStrokeDistance": "general.minDistance",
            "matchThreshold": "general.matchThreshold",
            "ambiguityResolution": "general.ambiguityResolution",
            "appearance": "general.appearanceMode",
            "menuBarIconStyle": "general.menuBarIconStyle",
            "language": "general.language",
            "showGestureHUD": "general.showHUD",
            "includeGestureHUDInCaptures": "general.includeHUDInCaptures",
            "directTrackpadEnabled": "trackpad.directEnabled",
            "hudLineColor": "general.lineColor",
            "hudLineWidth": "general.lineWidth",
            "hudShowStartPoint": "general.showStartPoint",
            "hudStartPointRadius": "general.startPointSize",
            "showMatchToast": "general.showMatchToast",
            "showMissToast": "general.showMissToast",
            "showLiveMismatchFeedback": "general.showLiveMismatchFeedback",
            "hudMismatchLineColor": "general.mismatchLineColor",
            "pinnedGestureAppBundleIds": "sync.setting.pinnedApps",
        ]
        return L10n.string(existingKeys[key] ?? "sync.setting.unknown")
    }

    private func settingValue(
        _ value: PortableSettingValue,
        key: String
    ) -> String {
        switch value {
        case .bool(let value):
            return L10n.string(value ? "common.yes" : "common.no")
        case .number(let value):
            return value.formatted(
                .number.precision(.fractionLength(0...3))
                    .locale(appState.resolvedLocale)
            )
        case .string(let value):
            if key == "ambiguityResolution",
               let resolution = GestureAmbiguityResolution(rawValue: value)
            {
                return L10n.string(
                    "general.ambiguityResolution.\(resolution.rawValue)"
                )
            }
            return value.isEmpty ? L10n.string("sync.value.empty") : value
        case .strings(let values):
            return values.isEmpty
                ? L10n.string("sync.value.empty")
                : values.joined(separator: ", ")
        }
    }

    private func privilegedGestureRiskSummary(
        _ preview: BackupPreviewState
    ) -> String {
        String(
            format: L10n.string("gestures.importPrivilegedMessage"),
            locale: L10n.locale,
            preview.privilegedGestureNames.count
        )
    }

    private func privilegedGestureNameList(
        _ preview: BackupPreviewState
    ) -> String {
        preview.privilegedGestureNames
            .map { "• \($0)" }
            .joined(separator: "\n")
    }

    private enum PendingRestoreKind: Equatable {
        case overwrite
        case merge
    }
}
