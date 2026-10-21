import Foundation

struct PreparedConfigurationRestore: Sendable {
    var backupID: RemoteBackupID
    var decoded: BackupDecodedBackup
    var preview: BackupPreviewState
    var localGestures: GestureConfigFile
    var localSettings: PortableSettingsV1
    var mergePlan: BackupMergePlan<PortableSettingValue>
}

@MainActor
final class ConfigurationRestoreEngine {
    private let configStore: ConfigStore
    private let defaults: UserDefaults
    private let applyConfiguration: () throws -> Void

    init(
        configStore: ConfigStore,
        defaults: UserDefaults,
        applyConfiguration: @escaping () throws -> Void
    ) {
        self.configStore = configStore
        self.defaults = defaults
        self.applyConfiguration = applyConfiguration
    }

    func prepare(
        backupID: RemoteBackupID,
        decoded: BackupDecodedBackup
    ) throws -> PreparedConfigurationRestore {
        try configStore.validateBackupGestureFile(decoded.payload.gestures)
        try decoded.payload.settings?.validate()

        let localGestures = try configStore.makeBackupGestureFile()
        let localSettings = PortableSettingsV1.capture(from: defaults)
        try localSettings.validate()
        let backupSettings = decoded.payload.settings?.mergeValues ?? [:]
        let plan = try BackupMergePlanner.plan(
            local: localGestures,
            backup: decoded.payload.gestures,
            localSettings: localSettings.mergeValues,
            backupSettings: backupSettings
        )
        let duplicates = contentDuplicates(
            local: localGestures.gestures,
            backup: decoded.payload.gestures.gestures
        )
        let localIDs = Set(localGestures.gestures.map(\.id))
        let duplicateIDs = Set(duplicates.map(\.id))
        let conflictIDs = Set(plan.gestureConflicts.map(\.id))
        let addedCount = decoded.payload.gestures.gestures.filter {
            !localIDs.contains($0.id)
                && !duplicateIDs.contains($0.id)
                && !conflictIDs.contains($0.id)
        }.count
        let privilegedGestureNames = decoded.payload.gestures.gestures
            .filter(\.containsPrivilegedAction)
            .map(\.name)

        let preview = BackupPreviewState(
            backupID: backupID,
            metadata: decoded.envelope.metadata,
            localGestureCount: localGestures.gestures.count,
            backupGestureCount: decoded.payload.gestures.gestures.count,
            gesturesAddedByMerge: addedCount,
            gestureConflicts: plan.gestureConflicts.map {
                BackupGestureConflictSummary(
                    id: $0.id,
                    localName: $0.local.name,
                    backupName: $0.backup.name
                )
            },
            contentDuplicates: duplicates,
            settingConflicts: plan.settingConflicts.map {
                BackupSettingConflictSummary(
                    key: $0.key,
                    localValue: $0.local,
                    backupValue: $0.backup
                )
            },
            privilegedGestureNames: privilegedGestureNames,
            containsExperimentalTrackpadGestures:
                decoded.payload.gestures.gestures.contains {
                    if case .trackpad = $0.input { return true }
                    return false
                } || decoded.payload.settings?.directTrackpadEnabled == true
        )
        return PreparedConfigurationRestore(
            backupID: backupID,
            decoded: decoded,
            preview: preview,
            localGestures: localGestures,
            localSettings: localSettings,
            mergePlan: plan
        )
    }

    func restore(
        _ prepared: PreparedConfigurationRestore,
        request: RestoreRequest,
        rollbackDocument: Data
    ) throws -> URL {
        guard request.backupID == prepared.backupID else {
            throw ConfigurationSyncError.backupMismatch
        }
        let currentGestures = try configStore.makeBackupGestureFile()
        let currentSettings = PortableSettingsV1.capture(from: defaults)
        guard currentGestures == prepared.localGestures,
              currentSettings == prepared.localSettings
        else {
            throw ConfigurationSyncError.previewOutdated
        }
        let recordsTrackpadRiskAcceptance = try validateRiskConfirmations(
            prepared.preview,
            request: request
        )
        let candidate = try makeCandidate(prepared, mode: request.mode)
        try configStore.validateBackupGestureFile(candidate.gestures)
        try candidate.settings?.validate()

        let rollbackURL = try writeRollback(
            rollbackDocument,
            snapshotID: prepared.decoded.envelope.snapshotID
        )
        do {
            try configStore.replaceFromBackup(candidate.gestures)
            try candidate.settings?.apply(to: defaults)
            try applyConfiguration()
            if recordsTrackpadRiskAcceptance {
                defaults.set(
                    true,
                    forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
                )
            }
            return rollbackURL
        } catch {
            let originalDescription = error.localizedDescription
            do {
                try configStore.replaceFromBackup(prepared.localGestures)
                try prepared.localSettings.apply(to: defaults)
                try applyConfiguration()
            } catch {
                throw ConfigurationSyncError.compensationFailed(
                    original: originalDescription,
                    rollback: error.localizedDescription,
                    rollbackURL: rollbackURL
                )
            }
            throw ConfigurationSyncError.restoreFailed(
                originalDescription,
                rollbackURL: rollbackURL
            )
        }
    }

    private func makeCandidate(
        _ prepared: PreparedConfigurationRestore,
        mode: SyncRestoreMode
    ) throws -> (gestures: GestureConfigFile, settings: PortableSettingsV1?) {
        switch mode {
        case .overwrite:
            return (
                prepared.decoded.payload.gestures,
                prepared.decoded.payload.settings
            )
        case .merge(let decisions, let defaultDuplicatePolicy):
            let result = try prepared.mergePlan.resolve(
                decisions: decisions,
                duplicatePolicy: defaultDuplicatePolicy
            )
            let settings = prepared.decoded.payload.settings == nil
                ? nil
                : try prepared.localSettings.replacingMergeValues(
                    result.settings
                )
            return (result.gestureFile, settings)
        }
    }

    private func validateRiskConfirmations(
        _ preview: BackupPreviewState,
        request: RestoreRequest
    ) throws -> Bool {
        if preview.containsScripts, !request.confirmsScriptRisk {
            throw ConfigurationSyncError.scriptConfirmationRequired
        }
        let acceptedTrackpadRisk = defaults.bool(
            forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
        )
        if preview.containsExperimentalTrackpadGestures,
           !acceptedTrackpadRisk,
           !request.confirmsExperimentalTrackpadRisk
        {
            throw ConfigurationSyncError.experimentalTrackpadConfirmationRequired
        }
        return preview.containsExperimentalTrackpadGestures
            && !acceptedTrackpadRisk
            && request.confirmsExperimentalTrackpadRisk
    }

    private func writeRollback(
        _ data: Data,
        snapshotID: UUID
    ) throws -> URL {
        let directory = configStore.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("Rollbacks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let uniqueID = UUID().uuidString.lowercased()
            let name = "\(Self.rollbackDateFormatter.string(from: Date()))--\(snapshotID.uuidString.lowercased())--\(uniqueID).strokemouse-backup"
            let url = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ConfigurationSyncError.rollbackFailed(
                error.localizedDescription
            )
        }
    }

    private func contentDuplicates(
        local: [GestureProfile],
        backup: [GestureProfile]
    ) -> [BackupContentDuplicateSummary] {
        let localIDs = Set(local.map(\.id))
        return backup.compactMap { backupGesture in
            guard !localIDs.contains(backupGesture.id),
                  let match = local.first(where: {
                      $0.isContentEqual(to: backupGesture)
                  })
            else { return nil }
            return BackupContentDuplicateSummary(
                id: backupGesture.id,
                backupName: backupGesture.name,
                matchingLocalName: match.name
            )
        }
    }

    private static let rollbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter
    }()
}
