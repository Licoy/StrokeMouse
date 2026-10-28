import AppKit
import CryptoKit
import Foundation
import Observation

typealias SyncAdapterFactory = @MainActor (
    SyncConnectionDescriptor,
    String
) throws -> any BackupRemoteAdapter

private struct CredentialMutation {
    let account: String
    let value: Data?
}

private struct CredentialSnapshot {
    let account: String
    let value: Data?
}

@MainActor
@Observable
final class ConfigurationSync {
    private(set) var state = SyncState()
    private(set) var history = BackupHistoryState()

    var isApplyingLocalRestore: Bool { isApplyingRestore }

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let vault: any CredentialVault
    @ObservationIgnored private let persistence: any ConfigurationSyncPersisting
    @ObservationIgnored private let adapterFactory: SyncAdapterFactory
    @ObservationIgnored private let restoreEngine: ConfigurationRestoreEngine
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let debounceInterval: TimeInterval
    @ObservationIgnored private let hourlyInterval: TimeInterval

    @ObservationIgnored private var configuration: StoredSyncConfiguration?
    @ObservationIgnored private var adapter: (any BackupRemoteAdapter)?
    @ObservationIgnored private var preparedRestore: PreparedConfigurationRestore?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var hourlyTask: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var lastObservedContentHash: Data?
    @ObservationIgnored private var lastObservedSettings: PortableSettingsV1?
    @ObservationIgnored private var queuedBackup: (BackupKind, Bool)?
    @ObservationIgnored private var pendingRestoredFromSnapshotID: UUID?
    @ObservationIgnored private var isApplyingRestore = false
    @ObservationIgnored private var changedWhileApplyingRestore = false
    @ObservationIgnored private var isActivated = false
    @ObservationIgnored private var isHourlyAuditRunning = false
    @ObservationIgnored private var connectionGeneration: UInt64 = 0
    @ObservationIgnored private var isLocalCredentialStateUncertain = false
    @ObservationIgnored private var uncertainCredentialAccounts = Set<String>()

    init(
        configStore: ConfigStore,
        defaults: UserDefaults = .standard,
        credentialVault: (any CredentialVault)? = nil,
        persistence: (any ConfigurationSyncPersisting)? = nil,
        adapterFactory: SyncAdapterFactory? = nil,
        debounceInterval: TimeInterval = 60,
        hourlyInterval: TimeInterval = 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
        applyConfiguration: @escaping () throws -> Void = {}
    ) {
        self.configStore = configStore
        self.defaults = defaults
        vault = credentialVault ?? KeychainCredentialVault(
            service: "\(Bundle.main.bundleIdentifier ?? Constants.bundleID).configuration-sync"
        )
        self.persistence = persistence
            ?? ConfigurationSyncPersistence(defaults: defaults)
        self.adapterFactory = adapterFactory ?? Self.productionAdapter
        self.debounceInterval = debounceInterval
        self.hourlyInterval = hourlyInterval
        self.now = now
        restoreEngine = ConfigurationRestoreEngine(
            configStore: configStore,
            defaults: defaults,
            applyConfiguration: applyConfiguration
        )
    }

    func activate() {
        guard !isActivated else { return }
        isActivated = true
        installObservers()
        do {
            configuration = try persistence.loadConfiguration()
            refreshConnectionState(hasStoredSecret: false)
            guard let activationConfiguration = configuration else { return }
            let activationGeneration = connectionGeneration
            Task { [weak self] in
                await self?.finishActivation(
                    connection: activationConfiguration.connection,
                    generation: activationGeneration
                )
            }
            lastObservedContentHash = try currentContentHash()
            state.hasPendingBackup = lastObservedContentHash
                != configuration?.lastSuccessfulContentHash
        } catch {
            recordFailure(error)
        }
    }

    /// Called only after ConfigStore has durably persisted a gesture mutation.
    func noteLocalConfigurationChanged() {
        guard configuration != nil else { return }
        if isApplyingRestore {
            changedWhileApplyingRestore = true
            return
        }
        do {
            let hash = try currentContentHash()
            guard hash != lastObservedContentHash else { return }
            lastObservedContentHash = hash
            state.hasPendingBackup = true
            scheduleDebouncedBackup()
        } catch {
            recordFailure(error)
        }
    }

    /// UserDefaults reports every key, including window frames and local-only
    /// scroll preferences. Rehashing the whole library for each of those is
    /// main-thread work with no effect, so only portable settings changes count.
    private func noteLocalSettingsChanged() {
        let settings = PortableSettingsV1.capture(from: defaults)
        guard settings != lastObservedSettings else { return }
        lastObservedSettings = settings
        noteLocalConfigurationChanged()
    }

    func handle(_ intent: SyncIntent) async -> SyncResult {
        do {
            try requireSafeCredentialState(for: intent)
            switch intent {
            case .saveConnection(let draft, let secrets):
                try requireIdle()
                try await saveConnection(draft, secrets: secrets)
                return .success
            case .disconnect:
                try requireIdle()
                try await disconnect()
                return .success
            case .backupNow:
                return await requestBackup(kind: .manual, force: true)
            case .loadHistory(let query):
                try requireIdle()
                try await loadHistory(query)
                return .success
            case .preview(let id, let attempt):
                try requireIdle()
                return try await preview(id, attempt: attempt)
            case .restore(let request):
                try requireIdle()
                try await restore(request)
                return .success
            }
        } catch {
            captureRollbackURL(from: error)
            if error as? ConfigurationSyncError == .operationInProgress {
                recordFailure(error, resetsActivity: false)
                return .failure(message(for: error))
            }
            if error as? ConfigurationSyncError
                == .localTransactionCompensationFailed
            {
                enterUncertainCredentialState(error)
                return .failure(message(for: error))
            }
            state.activity = .idle
            recordFailure(error)
            drainQueuedBackupIfNeeded()
            return .failure(message(for: error))
        }
    }

    private func finishActivation(
        connection: SyncConnectionDescriptor,
        generation: UInt64
    ) async {
        do {
            let secret = try await providerSecret(for: connection)
            guard connectionGeneration == generation,
                  let currentConfiguration = configuration,
                  currentConfiguration.connection == connection
            else { return }
            adapter = try adapterFactory(connection, secret)
            refreshConnectionState(hasStoredSecret: true)
            if isHourlyCheckDue(currentConfiguration) {
                await hourlyAudit()
            } else {
                scheduleHourlyCheck()
            }
        } catch {
            guard connectionGeneration == generation,
                  configuration?.connection == connection
            else { return }
            recordFailure(error)
            refreshConnectionState(hasStoredSecret: false)
        }
    }

    private func saveConnection(
        _ draft: SyncConnectionDraft,
        secrets: SyncSecretChanges
    ) async throws {
        state.activity = .validating
        let deviceName = try validatedDeviceName(draft.deviceName)
        let descriptor = try connectionDescriptor(from: draft)
        if let existing = configuration?.connection,
           existing.provider != descriptor.provider
        {
            throw ConfigurationSyncError.providerSwitchRequiresDisconnect
        }
        if draft.encryption == .none, !draft.confirmsPlaintextRisk {
            throw ConfigurationSyncError.plaintextConfirmationRequired
        }
        if isLocalCredentialStateUncertain,
           secrets.providerSecret == nil
        {
            throw ConfigurationSyncError.providerSecretRequired
        }
        let candidateContentHash = try contentHash(for: makeCurrentPayload(
            scope: draft.scope,
            restoredFrom: nil
        ))

        let secret = try await resolvedProviderSecret(
            secrets.providerSecret,
            descriptor: descriptor
        )
        let candidateAdapter = try adapterFactory(descriptor, secret)
        try await candidateAdapter.validateConnection()

        var currentKeyID = configuration?.currentEncryptionKeyID
        var knownKeyIDs = configuration?.knownEncryptionKeyIDs ?? []
        var newlyDerivedKey: BackupDerivedKey?
        if draft.encryption == .aes256GCM {
            if isLocalCredentialStateUncertain,
               secrets.encryptionPassword == nil
            {
                throw ConfigurationSyncError.encryptionPasswordRequired
            }
            if let password = secrets.encryptionPassword {
                let derived = try await Task.detached {
                    try BackupCodec.deriveKey(password: password)
                }.value
                currentKeyID = derived.keyID
                if !knownKeyIDs.contains(derived.keyID) {
                    knownKeyIDs.append(derived.keyID)
                }
                newlyDerivedKey = derived
            } else if let keyID = currentKeyID {
                _ = try await loadDerivedKey(keyID: keyID)
            } else {
                throw ConfigurationSyncError.encryptionPasswordRequired
            }
        } else {
            currentKeyID = nil
        }

        let previous = configuration
        let shouldResetHash = previous?.connection != descriptor
            || previous?.scope != draft.scope
            || previous?.encryption != draft.encryption
            || previous?.deviceName != deviceName
        let stored = StoredSyncConfiguration(
            connection: descriptor,
            deviceID: previous?.deviceID ?? persistence.stableDeviceID(),
            deviceName: deviceName,
            scope: draft.scope,
            encryption: draft.encryption,
            currentEncryptionKeyID: currentKeyID,
            knownEncryptionKeyIDs: knownKeyIDs,
            automaticBackupEnabled: draft.automaticBackupEnabled,
            lastSuccessfulContentHash: shouldResetHash
                ? nil : previous?.lastSuccessfulContentHash,
            lastSuccess: shouldResetHash ? nil : previous?.lastSuccess,
            lastHourlyCheck: previous?.lastHourlyCheck
        )
        let providerAccount = providerCredentialAccount(descriptor.provider)
        var activeAccounts: Set<String> = [providerAccount]
        if let currentKeyID {
            activeAccounts.insert(encryptionKeyAccount(currentKeyID))
        }
        var credentialMutations = uncertainCredentialAccounts
            .subtracting(activeAccounts)
            .sorted()
            .map { CredentialMutation(account: $0, value: nil) }
        if let newlyDerivedKey {
            credentialMutations.append(CredentialMutation(
                account: encryptionKeyAccount(newlyDerivedKey.keyID),
                value: try ConfigurationSyncPersistence.encodeDerivedKey(
                    newlyDerivedKey
                )
            ))
        }
        if let replacement = secrets.providerSecret {
            credentialMutations.append(CredentialMutation(
                account: providerAccount,
                value: Data(replacement.utf8)
            ))
        }
        try await commitLocalTransaction(
            credentialMutations: credentialMutations
        ) {
            try persistence.saveConfiguration(stored)
        }
        connectionGeneration &+= 1
        isLocalCredentialStateUncertain = false
        uncertainCredentialAccounts.removeAll()
        if previous?.connection != descriptor {
            history = BackupHistoryState()
            preparedRestore = nil
            state.pendingDecryptionID = nil
        }
        configuration = stored
        adapter = candidateAdapter
        lastObservedContentHash = candidateContentHash
        state.hasPendingBackup = lastObservedContentHash
            != stored.lastSuccessfulContentHash
        state.activity = .idle
        state.lastFailure = nil
        refreshConnectionState(hasStoredSecret: true)
        scheduleHourlyCheck()
        drainQueuedBackupIfNeeded()
    }

    private func disconnect() async throws {
        guard let configuration else {
            throw ConfigurationSyncError.notConnected
        }
        state.activity = .disconnecting
        let currentKeyID = configuration.currentEncryptionKeyID
        var keyIDs = Set(configuration.knownEncryptionKeyIDs)
        if let currentKeyID {
            keyIDs.insert(currentKeyID)
        }
        let providerAccount = providerCredentialAccount(
            configuration.connection.provider
        )
        var accounts = uncertainCredentialAccounts
        accounts.insert(providerAccount)
        accounts.formUnion(keyIDs.map(encryptionKeyAccount))
        let currentKeyAccount = currentKeyID.map(encryptionKeyAccount)
        let orderedAccounts = accounts.sorted { lhs, rhs in
            let lhsPriority = lhs == providerAccount
                ? 0 : (lhs == currentKeyAccount ? 2 : 1)
            let rhsPriority = rhs == providerAccount
                ? 0 : (rhs == currentKeyAccount ? 2 : 1)
            return lhsPriority == rhsPriority
                ? lhs < rhs : lhsPriority < rhsPriority
        }
        let credentialMutations = orderedAccounts.map {
            CredentialMutation(account: $0, value: nil)
        }
        try await commitLocalTransaction(
            credentialMutations: credentialMutations
        ) {
            try persistence.removeConfiguration()
        }
        connectionGeneration &+= 1
        isLocalCredentialStateUncertain = false
        uncertainCredentialAccounts.removeAll()
        debounceTask?.cancel()
        hourlyTask?.cancel()
        self.configuration = nil
        adapter = nil
        preparedRestore = nil
        pendingRestoredFromSnapshotID = nil
        lastObservedContentHash = nil
        queuedBackup = nil
        history = BackupHistoryState()
        state = SyncState()
    }

    private func requestBackup(
        kind: BackupKind,
        force: Bool
    ) async -> SyncResult {
        guard !isLocalCredentialStateUncertain else {
            let error = ConfigurationSyncError
                .localTransactionCompensationFailed
            recordFailure(error)
            return .failure(message(for: error))
        }
        guard configuration != nil else {
            let error = ConfigurationSyncError.notConnected
            recordFailure(error)
            return .failure(message(for: error))
        }
        if state.activity == .backingUp {
            mergeQueuedBackup(kind: kind, force: force)
            return .queued
        }
        guard state.activity == .idle else {
            mergeQueuedBackup(kind: kind, force: force)
            return .queued
        }
        do {
            try await performBackup(kind: kind, force: force)
            drainQueuedBackupIfNeeded()
            return .success
        } catch {
            state.activity = .idle
            recordFailure(error)
            drainQueuedBackupIfNeeded()
            return .failure(message(for: error))
        }
    }

    private func performBackup(kind: BackupKind, force: Bool) async throws {
        guard var configuration else {
            throw ConfigurationSyncError.notConnected
        }
        if kind != .manual, !configuration.automaticBackupEnabled {
            return
        }
        let payload = try makeCurrentPayload(
            scope: configuration.scope,
            restoredFrom: pendingRestoredFromSnapshotID
        )
        let contentHash = try contentHash(for: payload)
        if !force,
           pendingRestoredFromSnapshotID == nil,
           contentHash == configuration.lastSuccessfulContentHash
        {
            state.hasPendingBackup = false
            state.activity = .idle
            return
        }

        if pendingRestoredFromSnapshotID != nil
            || contentHash != configuration.lastSuccessfulContentHash
        {
            state.hasPendingBackup = true
        }
        state.activity = .backingUp
        let createdAt = now()
        let metadata = makeMetadata(
            configuration: configuration,
            kind: kind,
            createdAt: createdAt
        )
        let document = try await encode(
            payload: payload,
            metadata: metadata,
            configuration: configuration
        )
        let remote = try await ensureAdapter(configuration: configuration)
        let backupID = try await remote.storeBackup(document, createdAt: createdAt)

        if case .githubGist(let gistID) = configuration.connection,
           gistID == nil
        {
            configuration.connection = .githubGist(
                gistID: backupID.containerID
            )
        }
        configuration.lastSuccessfulContentHash = contentHash
        configuration.lastSuccess = SyncOperationRecord(
            date: createdAt,
            backupID: backupID,
            kind: kind
        )
        try persistence.saveConfiguration(configuration)
        self.configuration = configuration
        pendingRestoredFromSnapshotID = nil
        let currentHash = try currentContentHash()
        lastObservedContentHash = currentHash
        state.hasPendingBackup = currentHash != contentHash
        state.lastSuccess = configuration.lastSuccess
        state.lastFailure = nil
        state.activity = .idle
        refreshConnectionState(hasStoredSecret: true)
        if state.hasPendingBackup {
            scheduleDebouncedBackup()
        }
    }

    private func loadHistory(_ query: BackupHistoryQuery) async throws {
        guard let configuration else {
            throw ConfigurationSyncError.notConnected
        }
        state.activity = .loadingHistory
        let remote = try await ensureAdapter(configuration: configuration)
        let page: BackupHistoryPage
        do {
            page = try await remote.listHistory(query)
        } catch BackupRemoteError.notConfigured {
            history = BackupHistoryState()
            state.activity = .idle
            drainQueuedBackupIfNeeded()
            return
        }

        var inspected: [RemoteBackupHistoryItem] = []
        for summary in page.backups {
            if let byteCount = summary.byteCount,
               byteCount > BackupRemoteLimits.maximumPayloadByteCount
            {
                let error = BackupRemoteError.payloadTooLarge(
                    limit: BackupRemoteLimits.maximumPayloadByteCount,
                    actual: byteCount
                )
                inspected.append(RemoteBackupHistoryItem(
                    id: summary.id,
                    providerCreatedAt: summary.createdAt,
                    byteCount: byteCount,
                    metadata: nil,
                    encryption: nil,
                    inspectionError: message(for: error)
                ))
                continue
            }
            do {
                let data = try await remote.fetchBackup(summary.id)
                let envelope = try await Task.detached {
                    try BackupCodec.decodeEnvelope(from: data)
                }.value
                inspected.append(RemoteBackupHistoryItem(
                    id: summary.id,
                    providerCreatedAt: summary.createdAt,
                    byteCount: summary.byteCount ?? data.count,
                    metadata: envelope.metadata,
                    encryption: envelope.encryption.kind,
                    inspectionError: nil
                ))
            } catch {
                inspected.append(RemoteBackupHistoryItem(
                    id: summary.id,
                    providerCreatedAt: summary.createdAt,
                    byteCount: summary.byteCount,
                    metadata: nil,
                    encryption: nil,
                    inspectionError: message(for: error)
                ))
            }
        }
        if query.cursor == nil {
            history.items = inspected
        } else {
            var known = Set(history.items.map(\.id))
            history.items.append(contentsOf: inspected.filter {
                known.insert($0.id).inserted
            })
        }
        history.items.sort { lhs, rhs in
            (lhs.metadata?.createdAt ?? lhs.providerCreatedAt)
                > (rhs.metadata?.createdAt ?? rhs.providerCreatedAt)
        }
        history.nextCursor = page.nextCursor
        state.activity = .idle
        state.lastFailure = nil
        drainQueuedBackupIfNeeded()
    }

    private func preview(
        _ id: RemoteBackupID,
        attempt: DecryptionAttempt?
    ) async throws -> SyncResult {
        guard let configuration else {
            throw ConfigurationSyncError.notConnected
        }
        state.activity = .previewing
        state.pendingDecryptionID = nil
        let remote = try await ensureAdapter(configuration: configuration)
        let data = try await remote.fetchBackup(id)
        let envelope = try await Task.detached {
            try BackupCodec.decodeEnvelope(from: data)
        }.value

        let decoded: BackupDecodedBackup
        switch envelope.encryption.kind {
        case .none:
            decoded = try await Task.detached {
                try BackupCodec.decode(data)
            }.value
        case .aes256GCM:
            guard let keyID = envelope.encryption.keyID else {
                throw BackupCodecError.invalidEncryptionDescriptor
            }
            if let attempt {
                do {
                    let result = try await decodeEncrypted(
                        data,
                        envelope: envelope,
                        password: attempt.password
                    )
                    decoded = result.decoded
                    if attempt.savesOnThisMac {
                        try await saveDerivedKey(result.key)
                        try rememberEncryptionKeyID(result.key.keyID)
                    }
                } catch {
                    state.pendingDecryptionID = isDecryptionRetryError(error)
                        ? id : nil
                    state.activity = .idle
                    throw error
                }
            } else if let key = try await optionalDerivedKey(keyID: keyID) {
                do {
                    decoded = try await Task.detached {
                        try BackupCodec.decode(data, derivedKey: key)
                    }.value
                } catch {
                    if isDecryptionRetryError(error) {
                        state.pendingDecryptionID = id
                        state.activity = .idle
                        drainQueuedBackupIfNeeded()
                        return .requiresDecryption(id)
                    }
                    state.pendingDecryptionID = nil
                    throw error
                }
            } else {
                state.pendingDecryptionID = id
                state.activity = .idle
                drainQueuedBackupIfNeeded()
                return .requiresDecryption(id)
            }
        }

        let prepared = try restoreEngine.prepare(
            backupID: id,
            decoded: decoded
        )
        preparedRestore = prepared
        history.preview = prepared.preview
        state.pendingDecryptionID = nil
        state.activity = .idle
        state.lastFailure = nil
        if let index = history.items.firstIndex(where: { $0.id == id }) {
            history.items[index].metadata = envelope.metadata
            history.items[index].encryption = envelope.encryption.kind
            history.items[index].inspectionError = nil
        }
        drainQueuedBackupIfNeeded()
        return .success
    }

    private func restore(_ request: RestoreRequest) async throws {
        guard let configuration else {
            throw ConfigurationSyncError.notConnected
        }
        guard let preparedRestore,
              preparedRestore.backupID == request.backupID
        else {
            throw ConfigurationSyncError.previewRequired
        }
        state.activity = .restoring
        let rollbackPayload = BackupPayloadV1(
            gestures: preparedRestore.localGestures,
            settings: preparedRestore.localSettings,
            restoredFromSnapshotID: nil
        )
        let rollbackMetadata = makeMetadata(
            configuration: configuration,
            kind: .preRestore,
            createdAt: now(),
            scope: .allConfiguration
        )
        let rollbackDocument = try await encode(
            payload: rollbackPayload,
            metadata: rollbackMetadata,
            configuration: configuration
        )

        isApplyingRestore = true
        changedWhileApplyingRestore = false
        do {
            let rollbackURL = try restoreEngine.restore(
                preparedRestore,
                request: request,
                rollbackDocument: rollbackDocument
            )
            isApplyingRestore = false
            changedWhileApplyingRestore = false
            pendingRestoredFromSnapshotID = preparedRestore
                .decoded.envelope.snapshotID
            lastObservedContentHash = try currentContentHash()
            state.hasPendingBackup = true
            state.lastRollbackURL = rollbackURL
            state.activity = .idle
            scheduleDebouncedBackup()
        } catch {
            isApplyingRestore = false
            changedWhileApplyingRestore = false
            throw error
        }
        drainQueuedBackupIfNeeded()
    }

    private func hourlyAudit() async {
        guard !isHourlyAuditRunning else { return }
        guard !isLocalCredentialStateUncertain else { return }
        guard var configuration,
              configuration.automaticBackupEnabled
        else { return }
        guard isHourlyCheckDue(configuration) else {
            scheduleHourlyCheck()
            return
        }
        isHourlyAuditRunning = true
        defer { isHourlyAuditRunning = false }
        configuration.lastHourlyCheck = now()
        do {
            try persistence.saveConfiguration(configuration)
            self.configuration = configuration
            scheduleHourlyCheck()
            _ = await requestBackup(kind: .hourly, force: false)
        } catch {
            recordFailure(error)
            scheduleHourlyCheck()
        }
    }

    private func scheduleDebouncedBackup() {
        debounceTask?.cancel()
        guard !isLocalCredentialStateUncertain else { return }
        guard configuration?.automaticBackupEnabled == true else { return }
        let nanoseconds = UInt64(max(0, debounceInterval) * 1_000_000_000)
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                _ = await self?.requestBackup(kind: .automaticChange, force: false)
            } catch is CancellationError {
                return
            } catch {
                self?.recordFailure(error)
            }
        }
    }

    private func scheduleHourlyCheck() {
        hourlyTask?.cancel()
        guard !isLocalCredentialStateUncertain else {
            state.nextHourlyCheck = nil
            return
        }
        guard let configuration,
              configuration.automaticBackupEnabled
        else {
            state.nextHourlyCheck = nil
            return
        }
        let last = configuration.lastHourlyCheck ?? now()
        let next = max(last.addingTimeInterval(hourlyInterval), now())
        state.nextHourlyCheck = next
        let delay = max(0, next.timeIntervalSince(now()))
        let nanoseconds = UInt64(delay * 1_000_000_000)
        hourlyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self?.hourlyAudit()
            } catch is CancellationError {
                return
            } catch {
                self?.recordFailure(error)
            }
        }
    }

    private func installObservers() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.noteLocalSettingsChanged()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let configuration = self.configuration,
                      self.isHourlyCheckDue(configuration)
                else { return }
                await self.hourlyAudit()
            }
        }
    }

    private func isHourlyCheckDue(
        _ configuration: StoredSyncConfiguration
    ) -> Bool {
        guard configuration.automaticBackupEnabled else { return false }
        guard let last = configuration.lastHourlyCheck else { return true }
        return now().timeIntervalSince(last) >= hourlyInterval
    }

    private func makeCurrentPayload(
        scope: SyncScope,
        restoredFrom: UUID?
    ) throws -> BackupPayloadV1 {
        BackupPayloadV1(
            gestures: try configStore.makeBackupGestureFile(),
            settings: scope == .allConfiguration
                ? PortableSettingsV1.capture(from: defaults) : nil,
            restoredFromSnapshotID: restoredFrom
        )
    }

    private func currentContentHash() throws -> Data {
        guard let configuration else {
            throw ConfigurationSyncError.notConnected
        }
        return try contentHash(for: makeCurrentPayload(
            scope: configuration.scope,
            restoredFrom: nil
        ))
    }

    private func contentHash(for payload: BackupPayloadV1) throws -> Data {
        var content = payload
        content.restoredFromSnapshotID = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Data(SHA256.hash(data: try encoder.encode(content)))
    }

    private func encode(
        payload: BackupPayloadV1,
        metadata: BackupMetadataV1,
        configuration: StoredSyncConfiguration
    ) async throws -> Data {
        switch configuration.encryption {
        case .none:
            return try await Task.detached {
                try BackupCodec.encodePlaintext(
                    payload: payload,
                    metadata: metadata
                ).data
            }.value
        case .aes256GCM:
            guard let keyID = configuration.currentEncryptionKeyID else {
                throw ConfigurationSyncError.missingEncryptionKey
            }
            let key = try await loadDerivedKey(keyID: keyID)
            return try await Task.detached {
                try BackupCodec.encodeEncrypted(
                    payload: payload,
                    metadata: metadata,
                    derivedKey: key
                ).data
            }.value
        }
    }

    private func makeMetadata(
        configuration: StoredSyncConfiguration,
        kind: BackupKind,
        createdAt: Date,
        scope: SyncScope? = nil
    ) -> BackupMetadataV1 {
        BackupMetadataV1(
            snapshotID: UUID(),
            createdAt: createdAt,
            kind: kind,
            deviceID: configuration.deviceID,
            deviceName: configuration.deviceName,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0",
            appBuild: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "0",
            scope: scope ?? configuration.scope
        )
    }

    private func ensureAdapter(
        configuration: StoredSyncConfiguration
    ) async throws -> any BackupRemoteAdapter {
        if let adapter { return adapter }
        let value = try adapterFactory(
            configuration.connection,
            try await providerSecret(for: configuration.connection)
        )
        adapter = value
        return value
    }

    private func decodedConnectionSummary(
        _ configuration: StoredSyncConfiguration,
        hasStoredSecret: Bool
    ) -> SyncConnectionSummary {
        let destination: String
        let insecure: Bool
        let gistID: String?
        let webDAVBaseURL: String?
        let webDAVUsername: String?
        switch configuration.connection {
        case .githubGist(let configuredGistID):
            destination = configuredGistID
                ?? L10n.string("sync.destination.newGist")
            insecure = false
            gistID = configuredGistID
            webDAVBaseURL = nil
            webDAVUsername = nil
        case .webDAV(let baseURL, let username):
            destination = baseURL.absoluteString
            insecure = baseURL.scheme?.lowercased() == "http"
            gistID = nil
            webDAVBaseURL = baseURL.absoluteString
            webDAVUsername = username
        }
        return SyncConnectionSummary(
            provider: configuration.connection.provider,
            destination: destination,
            deviceName: configuration.deviceName,
            deviceID: configuration.deviceID,
            scope: configuration.scope,
            encryption: configuration.encryption,
            automaticBackupEnabled: configuration.automaticBackupEnabled,
            hasStoredProviderSecret: hasStoredSecret,
            usesInsecureHTTP: insecure,
            gistID: gistID,
            webDAVBaseURL: webDAVBaseURL,
            webDAVUsername: webDAVUsername
        )
    }

    private func refreshConnectionState(hasStoredSecret: Bool) {
        guard let configuration else {
            state.connection = nil
            return
        }
        state.connection = decodedConnectionSummary(
            configuration,
            hasStoredSecret: hasStoredSecret
        )
        state.lastSuccess = configuration.lastSuccess
    }

    private func connectionDescriptor(
        from draft: SyncConnectionDraft
    ) throws -> SyncConnectionDescriptor {
        switch draft.provider {
        case .githubGist:
            let gistID = try normalizedGistID(draft.gistIDOrURL)
            if gistID != nil, !draft.confirmsExistingGistVisibilityRisk {
                throw ConfigurationSyncError.gistVisibilityConfirmationRequired
            }
            return .githubGist(gistID: gistID)
        case .webDAV:
            guard let url = URL(string: draft.webDAVURL),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil,
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil
            else {
                throw ConfigurationSyncError.invalidWebDAVURL
            }
            if scheme == "http" {
                let confirmedURL = draft.confirmedInsecureHTTPURL
                    .flatMap(URL.init(string:))
                guard draft.confirmsInsecureHTTP,
                      confirmedURL?.absoluteString == url.absoluteString
                else {
                    throw ConfigurationSyncError
                        .insecureHTTPConfirmationRequired
                }
            }
            return .webDAV(baseURL: url, username: draft.webDAVUsername)
        }
    }

    private func normalizedGistID(_ value: String) throws -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: String
        if let url = URL(string: trimmed), url.scheme != nil {
            guard url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  host == "gist.github.com" || host == "api.github.com"
            else { throw ConfigurationSyncError.invalidGistIdentifier }
            candidate = url.pathComponents.last ?? ""
        } else {
            candidate = trimmed
        }
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
              })
        else { throw ConfigurationSyncError.invalidGistIdentifier }
        return candidate
    }

    private func validatedDeviceName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else { throw ConfigurationSyncError.invalidDeviceName }
        return name
    }

    private func resolvedProviderSecret(
        _ replacement: String?,
        descriptor: SyncConnectionDescriptor
    ) async throws -> String {
        if let replacement {
            guard !replacement.isEmpty else {
                throw ConfigurationSyncError.providerSecretRequired
            }
            return replacement
        }
        return try await providerSecret(for: descriptor)
    }

    private func providerSecret(
        for descriptor: SyncConnectionDescriptor
    ) async throws -> String {
        guard let data = try await vault.credential(
            for: providerCredentialAccount(descriptor.provider)
        ), let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { throw ConfigurationSyncError.providerSecretRequired }
        return value
    }

    private func providerCredentialAccount(_ provider: SyncProviderKind) -> String {
        "provider.\(provider.rawValue)"
    }

    private func encryptionKeyAccount(_ keyID: UUID) -> String {
        "encryption.\(keyID.uuidString.lowercased())"
    }

    private func saveDerivedKey(_ key: BackupDerivedKey) async throws {
        try await vault.setCredential(
            try ConfigurationSyncPersistence.encodeDerivedKey(key),
            for: encryptionKeyAccount(key.keyID)
        )
    }

    private func commitLocalTransaction(
        credentialMutations: [CredentialMutation],
        persistenceMutation: () throws -> Void
    ) async throws {
        let storedBeforeMutation = try persistence.loadConfiguration()
        var seenAccounts = Set<String>()
        var credentialSnapshots: [CredentialSnapshot] = []
        for mutation in credentialMutations
            where seenAccounts.insert(mutation.account).inserted
        {
            credentialSnapshots.append(CredentialSnapshot(
                account: mutation.account,
                value: try await vault.credential(for: mutation.account)
            ))
        }

        do {
            for mutation in credentialMutations {
                try await applyCredentialMutation(mutation)
            }
            try persistenceMutation()
        } catch {
            let originalError = error
            let compensationFailed = await compensateLocalTransaction(
                credentials: credentialSnapshots,
                configuration: storedBeforeMutation
            )
            if compensationFailed {
                uncertainCredentialAccounts.formUnion(
                    credentialSnapshots.map(\.account)
                )
                throw ConfigurationSyncError
                    .localTransactionCompensationFailed
            }
            throw originalError
        }
    }

    private func compensateLocalTransaction(
        credentials: [CredentialSnapshot],
        configuration: StoredSyncConfiguration?
    ) async -> Bool {
        var failed = false
        for snapshot in credentials.reversed() {
            do {
                try await applyCredentialMutation(CredentialMutation(
                    account: snapshot.account,
                    value: snapshot.value
                ))
            } catch {
                failed = true
            }
        }
        do {
            if let configuration {
                try persistence.saveConfiguration(configuration)
            } else {
                try persistence.removeConfiguration()
            }
        } catch {
            failed = true
        }
        return failed
    }

    private func applyCredentialMutation(
        _ mutation: CredentialMutation
    ) async throws {
        if let value = mutation.value {
            try await vault.setCredential(value, for: mutation.account)
        } else {
            try await vault.deleteCredential(for: mutation.account)
        }
    }

    private func optionalDerivedKey(
        keyID: UUID
    ) async throws -> BackupDerivedKey? {
        guard let data = try await vault.credential(
            for: encryptionKeyAccount(keyID)
        ) else { return nil }
        return try ConfigurationSyncPersistence.decodeDerivedKey(data)
    }

    private func loadDerivedKey(keyID: UUID) async throws -> BackupDerivedKey {
        guard let key = try await optionalDerivedKey(keyID: keyID) else {
            throw ConfigurationSyncError.missingEncryptionKey
        }
        return key
    }

    private func rememberEncryptionKeyID(_ keyID: UUID) throws {
        guard var configuration else { return }
        if !configuration.knownEncryptionKeyIDs.contains(keyID) {
            configuration.knownEncryptionKeyIDs.append(keyID)
            try persistence.saveConfiguration(configuration)
            self.configuration = configuration
        }
    }

    private func decodeEncrypted(
        _ data: Data,
        envelope: BackupEnvelopeV1,
        password: String
    ) async throws -> (decoded: BackupDecodedBackup, key: BackupDerivedKey) {
        guard let keyID = envelope.encryption.keyID,
              let salt = envelope.encryption.salt,
              let iterations = envelope.encryption.iterations
        else { throw BackupCodecError.invalidEncryptionDescriptor }
        return try await Task.detached {
            let key = try BackupCodec.deriveKey(
                password: password,
                salt: salt,
                keyID: keyID,
                iterations: iterations
            )
            return (
                try BackupCodec.decode(data, derivedKey: key),
                key
            )
        }.value
    }

    private func isDecryptionRetryError(_ error: Error) -> Bool {
        guard let error = error as? BackupCodecError else { return false }
        switch error {
        case .decryptionFailed, .encryptionKeyMismatch,
             .decryptionKeyRequired:
            return true
        default:
            return false
        }
    }

    private func requireIdle() throws {
        guard state.activity == .idle else {
            throw ConfigurationSyncError.operationInProgress
        }
    }

    private func requireSafeCredentialState(for intent: SyncIntent) throws {
        guard isLocalCredentialStateUncertain else { return }
        switch intent {
        case .saveConnection, .disconnect:
            return
        default:
            throw ConfigurationSyncError.localTransactionCompensationFailed
        }
    }

    private func mergeQueuedBackup(kind: BackupKind, force: Bool) {
        guard let queuedBackup else {
            self.queuedBackup = (kind, force)
            return
        }
        let shouldUseNew = force && !queuedBackup.1
        self.queuedBackup = shouldUseNew ? (kind, force) : queuedBackup
    }

    private func drainQueuedBackupIfNeeded() {
        guard state.activity == .idle,
              let queuedBackup
        else { return }
        self.queuedBackup = nil
        Task { [weak self] in
            _ = await self?.requestBackup(
                kind: queuedBackup.0,
                force: queuedBackup.1
            )
        }
    }

    private func recordFailure(
        _ error: Error,
        resetsActivity: Bool = true
    ) {
        state.lastFailure = SyncFailureRecord(
            date: now(),
            message: message(for: error)
        )
        if resetsActivity, state.activity != .idle {
            state.activity = .idle
        }
    }

    private func enterUncertainCredentialState(_ error: Error) {
        isLocalCredentialStateUncertain = true
        adapter = nil
        debounceTask?.cancel()
        debounceTask = nil
        hourlyTask?.cancel()
        hourlyTask = nil
        queuedBackup = nil
        state.nextHourlyCheck = nil
        recordFailure(error)
        refreshConnectionState(hasStoredSecret: false)
    }

    private func message(for error: Error) -> String {
        if let error = error as? ConfigurationSyncError {
            switch error {
            case .notConnected: return L10n.string("sync.error.notConnected")
            case .operationInProgress: return L10n.string("sync.error.busy")
            case .providerSwitchRequiresDisconnect:
                return L10n.string("sync.error.disconnectBeforeSwitch")
            case .invalidDeviceName: return L10n.string("sync.error.deviceName")
            case .invalidGistIdentifier: return L10n.string("sync.error.gistID")
            case .invalidWebDAVURL: return L10n.string("sync.error.webdavURL")
            case .insecureHTTPConfirmationRequired:
                return L10n.string("sync.error.confirmHTTP")
            case .plaintextConfirmationRequired:
                return L10n.string("sync.error.confirmPlaintext")
            case .gistVisibilityConfirmationRequired:
                return L10n.string("sync.error.confirmGistVisibility")
            case .providerSecretRequired:
                return L10n.string("sync.error.providerSecret")
            case .encryptionPasswordRequired, .missingEncryptionKey:
                return L10n.string("sync.error.encryptionPassword")
            case .previewRequired: return L10n.string("sync.error.previewRequired")
            case .previewOutdated: return L10n.string("sync.error.previewOutdated")
            case .backupMismatch: return L10n.string("sync.error.backupMismatch")
            case .scriptConfirmationRequired:
                return L10n.string("sync.error.confirmScripts")
            case .experimentalTrackpadConfirmationRequired:
                return L10n.string("sync.error.confirmTrackpad")
            case .rollbackFailed:
                return L10n.string("sync.error.rollback")
            case .restoreFailed:
                return L10n.string("sync.error.operationFailed")
            case .compensationFailed:
                return L10n.string("sync.error.compensation")
            case .localTransactionCompensationFailed:
                return L10n.string(
                    "sync.error.localTransactionCompensation"
                )
            case .invalidStoredConfiguration:
                return L10n.string("sync.error.storedConfiguration")
            }
        }
        if let error = error as? BackupCodecError {
            switch error {
            case .decryptionFailed, .encryptionKeyMismatch,
                 .decryptionKeyRequired:
                return L10n.string("sync.error.wrongPassword")
            case .passwordTooShort, .passwordTooLong:
                return L10n.string("sync.error.encryptionPassword")
            case .sizeLimitExceeded:
                return L10n.string("sync.error.tooLarge")
            case .unsupportedFormatVersion, .unsupportedGestureConfigVersion:
                return L10n.string("sync.error.futureVersion")
            default:
                return L10n.string("sync.error.invalidBackup")
            }
        }
        if let error = error as? BackupRemoteError {
            switch error {
            case .authenticationRequired: return L10n.string("sync.error.authentication")
            case .forbidden: return L10n.string("sync.error.forbidden")
            case .notFound: return L10n.string("sync.error.notFound")
            case .conflict: return L10n.string("sync.error.remoteConflict")
            case .rateLimited: return L10n.string("sync.error.rateLimited")
            case .payloadTooLarge: return L10n.string("sync.error.tooLarge")
            case .unsafeRedirect: return L10n.string("sync.error.unsafeRedirect")
            default: return L10n.string("sync.error.remote")
            }
        }
        if error is PortableSettingsValidationError
            || error is BackupMergePlannerError
            || error is ConfigStoreFailure
        {
            return L10n.string("sync.error.invalidBackup")
        }
        return L10n.string("sync.error.operationFailed")
    }

    private func captureRollbackURL(from error: Error) {
        guard let error = error as? ConfigurationSyncError else { return }
        switch error {
        case .restoreFailed(_, let rollbackURL),
             .compensationFailed(_, _, let rollbackURL):
            state.lastRollbackURL = rollbackURL
        default:
            break
        }
    }

    private static func productionAdapter(
        descriptor: SyncConnectionDescriptor,
        secret: String
    ) throws -> any BackupRemoteAdapter {
        switch descriptor {
        case .githubGist(let gistID):
            return try GitHubGistBackupAdapter(
                personalAccessToken: secret,
                gistID: gistID
            )
        case .webDAV(let baseURL, let username):
            return try WebDAVBackupAdapter(
                baseURL: baseURL,
                username: username,
                password: secret
            )
        }
    }
}
