import Foundation

enum BackupConfigSide: Equatable, Sendable {
    case local
    case backup
}

enum BackupMergePlannerError: Error, Equatable, Sendable {
    case unsupportedConfigVersion(side: BackupConfigSide, version: Int)
    case duplicateGestureID(side: BackupConfigSide, id: UUID)
    case unresolvedGestureConflicts([UUID])
    case unresolvedSettingConflicts([String])
    case generatedDuplicateGestureID(UUID)
}

enum BackupGestureConflictDecision: Equatable, Hashable, Sendable {
    case keepLocal
    case useBackup
    case keepBoth
}

enum BackupSettingConflictDecision: Equatable, Hashable, Sendable {
    case keepLocal
    case useBackup
}

enum BackupContentDuplicatePolicy: Equatable, Hashable, Sendable {
    case skip
    case keepDisabledCopy
}

struct BackupMergeDecisions: Sendable {
    var gestures: [UUID: BackupGestureConflictDecision] = [:]
    var contentDuplicates: [UUID: BackupContentDuplicatePolicy] = [:]
    var settings: [String: BackupSettingConflictDecision] = [:]
}

struct BackupGestureConflict: Equatable, Sendable {
    let id: UUID
    let local: GestureProfile
    let backup: GestureProfile
}

struct BackupSettingConflict<Value: Equatable & Sendable>: Equatable, Sendable {
    let key: String
    let local: Value
    let backup: Value
}

struct BackupMergeResult<Value: Equatable & Sendable>: Equatable, Sendable {
    let gestureFile: GestureConfigFile
    let settings: [String: Value]
}

struct BackupMergePlan<Value: Equatable & Sendable>: Sendable {
    let gestureConflicts: [BackupGestureConflict]
    let settingConflicts: [BackupSettingConflict<Value>]

    private let local: GestureConfigFile
    private let backup: GestureConfigFile
    private let localSettings: [String: Value]
    private let backupSettings: [String: Value]

    fileprivate init(
        local: GestureConfigFile,
        backup: GestureConfigFile,
        localSettings: [String: Value],
        backupSettings: [String: Value]
    ) {
        self.local = local
        self.backup = backup
        self.localSettings = localSettings
        self.backupSettings = backupSettings

        let localByID = Dictionary(
            uniqueKeysWithValues: local.gestures.map { ($0.id, $0) }
        )
        gestureConflicts = backup.gestures.compactMap { backupProfile in
            guard let localProfile = localByID[backupProfile.id],
                  localProfile != backupProfile
            else {
                return nil
            }
            return BackupGestureConflict(
                id: backupProfile.id,
                local: localProfile,
                backup: backupProfile
            )
        }

        settingConflicts = backupSettings.keys.sorted().compactMap { key in
            guard let localValue = localSettings[key],
                  let backupValue = backupSettings[key],
                  localValue != backupValue
            else {
                return nil
            }
            return BackupSettingConflict(
                key: key,
                local: localValue,
                backup: backupValue
            )
        }
    }

    func resolve(
        decisions: BackupMergeDecisions = .init(),
        duplicatePolicy: BackupContentDuplicatePolicy = .skip,
        makeUUID: () -> UUID = UUID.init
    ) throws -> BackupMergeResult<Value> {
        let missingGestureDecisions = gestureConflicts.compactMap { conflict in
            decisions.gestures[conflict.id] == nil ? conflict.id : nil
        }
        guard missingGestureDecisions.isEmpty else {
            throw BackupMergePlannerError.unresolvedGestureConflicts(
                missingGestureDecisions
            )
        }

        let missingSettingDecisions = settingConflicts.compactMap { conflict in
            decisions.settings[conflict.key] == nil ? conflict.key : nil
        }
        guard missingSettingDecisions.isEmpty else {
            throw BackupMergePlannerError.unresolvedSettingConflicts(
                missingSettingDecisions
            )
        }

        var mergedGestures = local.gestures
        for backupProfile in backup.gestures {
            if let localIndex = mergedGestures.firstIndex(
                where: { $0.id == backupProfile.id }
            ) {
                guard mergedGestures[localIndex] != backupProfile else {
                    continue
                }
                switch decisions.gestures[backupProfile.id] {
                case .keepLocal:
                    continue
                case .useBackup:
                    mergedGestures[localIndex] = backupProfile
                case .keepBoth:
                    try appendDisabledCopy(
                        of: backupProfile,
                        to: &mergedGestures,
                        makeUUID: makeUUID
                    )
                case nil:
                    preconditionFailure("Conflict decisions were prevalidated")
                }
                continue
            }

            if mergedGestures.contains(where: {
                $0.isContentEqual(to: backupProfile)
            }) {
                let resolvedDuplicatePolicy = decisions.contentDuplicates[
                    backupProfile.id
                ] ?? duplicatePolicy
                if resolvedDuplicatePolicy == .keepDisabledCopy {
                    try appendDisabledCopy(
                        of: backupProfile,
                        to: &mergedGestures,
                        makeUUID: makeUUID
                    )
                }
                continue
            }

            mergedGestures.append(backupProfile)
        }

        var mergedSettings = localSettings
        for key in backupSettings.keys.sorted() {
            guard let backupValue = backupSettings[key] else { continue }
            guard let localValue = localSettings[key] else {
                mergedSettings[key] = backupValue
                continue
            }
            guard localValue != backupValue else { continue }
            if decisions.settings[key] == .useBackup {
                mergedSettings[key] = backupValue
            }
        }

        // Groups merge by id and policies by bundle identifier; the local copy
        // wins when both sides define one, so a merge never rewrites local rules.
        let localGroupIDs = Set(local.appGroups.map(\.id))
        let mergedGroups = local.appGroups + backup.appGroups.filter {
            !localGroupIDs.contains($0.id)
        }
        let localPolicyKeys = Set(local.appPolicies.map {
            $0.bundleIdentifier.lowercased()
        })
        let mergedPolicies = local.appPolicies + backup.appPolicies.filter {
            !localPolicyKeys.contains($0.bundleIdentifier.lowercased())
        }

        return BackupMergeResult(
            gestureFile: GestureConfigFile(
                version: Constants.configVersion,
                gestures: mergedGestures,
                appPolicies: mergedPolicies,
                appGroups: mergedGroups
            ),
            settings: mergedSettings
        )
    }

    private func appendDisabledCopy(
        of profile: GestureProfile,
        to gestures: inout [GestureProfile],
        makeUUID: () -> UUID
    ) throws {
        let newID = makeUUID()
        guard !gestures.contains(where: { $0.id == newID }) else {
            throw BackupMergePlannerError.generatedDuplicateGestureID(newID)
        }
        var copy = profile
        copy.id = newID
        copy.isEnabled = false
        gestures.append(copy)
    }
}

enum BackupMergePlanner {
    static func plan<Value: Equatable & Sendable>(
        local: GestureConfigFile,
        backup: GestureConfigFile,
        localSettings: [String: Value],
        backupSettings: [String: Value]
    ) throws -> BackupMergePlan<Value> {
        guard local.version == Constants.configVersion else {
            throw BackupMergePlannerError.unsupportedConfigVersion(
                side: .local,
                version: local.version
            )
        }
        guard backup.version == Constants.configVersion else {
            throw BackupMergePlannerError.unsupportedConfigVersion(
                side: .backup,
                version: backup.version
            )
        }
        try validateUniqueIDs(local.gestures, side: .local)
        try validateUniqueIDs(backup.gestures, side: .backup)
        return BackupMergePlan(
            local: local,
            backup: backup,
            localSettings: localSettings,
            backupSettings: backupSettings
        )
    }

    private static func validateUniqueIDs(
        _ gestures: [GestureProfile],
        side: BackupConfigSide
    ) throws {
        var ids = Set<UUID>()
        for gesture in gestures where !ids.insert(gesture.id).inserted {
            throw BackupMergePlannerError.duplicateGestureID(
                side: side,
                id: gesture.id
            )
        }
    }
}
