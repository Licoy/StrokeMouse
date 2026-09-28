import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ConfigStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "ConfigStore"
    )

    private(set) var gestures: [GestureProfile] = []
    /// Exact-application overrides, e.g. suppressing global gestures.
    private(set) var appPolicies: [AppGesturePolicy] = []
    private(set) var appGroups: [AppGroup] = []
    private(set) var lastError: String?
    private(set) var lastFailure: ConfigStoreFailure?
    private(set) var configURL: URL
    private(set) var requiresRecovery = false

    /// Called after gestures, app policies or app groups are mutated and
    /// persisted (or after load).
    var onGesturesChanged: (() -> Void)?

    /// Complete library in its persisted wire shape.
    var library: GestureConfigFile {
        GestureConfigFile(
            version: Constants.configVersion,
            gestures: gestures,
            appPolicies: appPolicies,
            appGroups: appGroups
        )
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let replaceItem: (URL, URL) throws -> Void

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        replaceItem = { destination, replacement in
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: replacement
            )
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = support.appendingPathComponent(Constants.supportDirectoryName, isDirectory: true)
        configURL = dir.appendingPathComponent(Constants.configFileName)
        do {
            try Self.migrateLegacySupportDirectoryIfNeeded(
                to: dir,
                supportRoot: support,
                fileManager: fileManager
            )
            load()
        } catch {
            requiresRecovery = fileManager.fileExists(
                atPath: configURL.path
            )
            recordFailure(error)
        }
    }

    /// Copy config from the pre-rename Application Support folder when present.
    private static func migrateLegacySupportDirectoryIfNeeded(
        to newDir: URL,
        supportRoot: URL,
        fileManager: FileManager
    ) throws {
        let legacyDir = supportRoot.appendingPathComponent(Constants.legacySupportDirectoryName, isDirectory: true)
        let legacyConfig = legacyDir.appendingPathComponent(Constants.configFileName)
        let newConfig = newDir.appendingPathComponent(Constants.configFileName)
        guard fileManager.fileExists(atPath: legacyConfig.path),
              !fileManager.fileExists(atPath: newConfig.path)
        else { return }
        try fileManager.createDirectory(
            at: newDir,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: legacyConfig, to: newConfig)
    }

    /// Testing initializer with custom config location.
    init(
        configURL: URL,
        fileManager: FileManager = .default,
        replaceItem: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.replaceItem = replaceItem ?? { destination, replacement in
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: replacement
            )
        }
        self.configURL = configURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        load()
    }

    func load() {
        lastError = nil
        lastFailure = nil
        requiresRecovery = false
        let dir = configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                switch try decodeConfig(from: data) {
                case .current(let file, let requiresCompatibilityRewrite):
                    try validate(file)
                    if requiresCompatibilityRewrite {
                        try persist(file)
                    }
                    publish(file)
                case .legacy(let profiles):
                    let file = Self.file(gestures: profiles)
                    try validate(file)
                    try preserveLegacyBackup(data)
                    try persist(file)
                    publish(file)
                }
            } else {
                let defaults = Self.defaultLibrary()
                try persist(defaults)
                publish(defaults)
            }
        } catch {
            requiresRecovery = fileManager.fileExists(
                atPath: configURL.path
            )
            recordFailure(error)
        }
    }

    @discardableResult
    func save() -> Bool {
        guard !requiresRecovery else { return false }
        do {
            let current = library
            try persist(current)
            publish(current)
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    func add(_ profile: GestureProfile) {
        var candidate = gestures
        candidate.append(profile)
        commit(candidate)
    }

    func update(_ profile: GestureProfile) {
        guard let index = gestures.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        var candidate = gestures
        candidate[index] = profile
        commit(candidate)
    }

    func delete(id: UUID) {
        let candidate = gestures.filter { $0.id != id }
        guard candidate.count != gestures.count else { return }
        commit(candidate)
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let candidate = gestures.filter { !ids.contains($0.id) }
        guard candidate.count != gestures.count else { return }
        commit(candidate)
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = gestures.firstIndex(where: { $0.id == id }) else { return }
        guard gestures[index].isEnabled != enabled else { return }
        var candidate = gestures
        candidate[index].isEnabled = enabled
        commit(candidate)
    }

    func setEnabled(ids: Set<UUID>, enabled: Bool) {
        guard !ids.isEmpty else { return }
        var candidate = gestures
        var changed = false
        for index in candidate.indices where ids.contains(candidate[index].id) {
            if candidate[index].isEnabled != enabled {
                candidate[index].isEnabled = enabled
                changed = true
            }
        }
        if changed { commit(candidate) }
    }

    func replaceAll(_ profiles: [GestureProfile]) {
        commit(profiles)
    }

    /// Restores the default gestures and clears app policies and groups.
    func resetToDefaults() {
        commit(Self.defaultLibrary())
    }

    // MARK: - App policies and groups

    func appPolicy(forBundleIdentifier bundleIdentifier: String) -> AppGesturePolicy? {
        guard let key = AppMatching.normalizedBundleIdentifier(bundleIdentifier)?
            .lowercased()
        else {
            return nil
        }
        return appPolicies.first { $0.bundleIdentifier.lowercased() == key }
    }

    /// An empty set removes the override so the application follows global gestures.
    func setSuppressedGlobalInputs(
        _ suppressed: SuppressedGlobalInputs,
        forBundleIdentifier bundleIdentifier: String
    ) {
        guard let normalized = AppMatching.normalizedBundleIdentifier(bundleIdentifier) else {
            return
        }
        var candidate = library
        candidate.appPolicies.removeAll {
            $0.bundleIdentifier.lowercased() == normalized.lowercased()
        }
        if !suppressed.isEmpty {
            candidate.appPolicies.append(AppGesturePolicy(
                bundleIdentifier: normalized,
                suppressedGlobalInputs: suppressed
            ))
        }
        guard candidate != library else { return }
        commit(candidate)
    }

    func removeAppPolicy(forBundleIdentifier bundleIdentifier: String) {
        setSuppressedGlobalInputs(.none, forBundleIdentifier: bundleIdentifier)
    }

    func appGroup(id: UUID) -> AppGroup? {
        appGroups.first { $0.id == id }
    }

    func addAppGroup(_ group: AppGroup) {
        var candidate = library
        candidate.appGroups.append(group)
        commit(candidate)
    }

    func updateAppGroup(_ group: AppGroup) {
        guard let index = appGroups.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        var candidate = library
        candidate.appGroups[index] = group
        guard candidate != library else { return }
        commit(candidate)
    }

    /// Removes a group. Its gestures are deleted or become global.
    func deleteAppGroup(
        id: UUID,
        gestures disposition: AppGroupGestureDisposition
    ) {
        guard appGroups.contains(where: { $0.id == id }) else { return }
        var candidate = library
        candidate.appGroups.removeAll { $0.id == id }
        switch disposition {
        case .delete:
            candidate.gestures.removeAll { $0.scope == .group(id) }
        case .makeGlobal:
            for index in candidate.gestures.indices
            where candidate.gestures[index].scope == .group(id) {
                candidate.gestures[index].scope = .global
            }
        }
        commit(candidate)
    }

    /// Moves gestures to a new scope in one write (e.g. into an app group).
    func setScope(_ scope: AppScope, forGestureIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var candidate = library
        var changed = false
        for index in candidate.gestures.indices
        where ids.contains(candidate.gestures[index].id)
            && candidate.gestures[index].scope != scope
        {
            candidate.gestures[index].scope = scope
            changed = true
        }
        if changed { commit(candidate) }
    }

    // MARK: - Whole-library backup

    /// Returns the complete gesture library in its persisted wire shape.
    /// Unlike selection export, an empty library is a valid backup.
    func makeBackupGestureFile() throws -> GestureConfigFile {
        guard !requiresRecovery else {
            throw ConfigStoreFailure.recoveryRequired
        }
        do {
            let current = library
            try validate(current)
            return current
        } catch {
            throw recordFailure(error)
        }
    }

    /// Validates a backup without mutating the store or its error state.
    func validateBackupGestureFile(_ file: GestureConfigFile) throws {
        guard file.version == Constants.configVersion else {
            throw ConfigStoreFailure.unsupportedVersion(file.version)
        }
        try validate(file)
    }

    /// Atomically replaces the complete gesture library from a backup.
    /// UUIDs and ordering are preserved exactly; an empty library is valid.
    func replaceFromBackup(_ file: GestureConfigFile) throws {
        guard !requiresRecovery else {
            throw ConfigStoreFailure.recoveryRequired
        }
        try validateBackupGestureFile(file)
        do {
            try persist(file)
            publish(file)
        } catch {
            throw recordFailure(error)
        }
    }

    /// Replaces an unreadable/unsupported config only after preserving its
    /// exact bytes in a uniquely named, non-overwriting recovery copy.
    @discardableResult
    func recoverWithDefaults() throws -> URL? {
        guard requiresRecovery else { return nil }
        let backupURL = try preserveRecoveryCopy()
        let defaults = Self.defaultLibrary()
        do {
            try persist(defaults)
            requiresRecovery = false
            publish(defaults)
            return backupURL
        } catch {
            recordFailure(error)
            throw error
        }
    }

    // MARK: - Import / Export

    /// Encode selected profiles as a shareable `GestureConfigFile` package (order matches store).
    func exportPackage(ids: Set<UUID>) throws -> Data {
        let selected = gestures.filter { ids.contains($0.id) }
        guard !selected.isEmpty else {
            throw GestureImportExportError.emptySelection
        }
        // Group-scoped gestures carry their group so the package stays valid.
        let referencedGroupIDs = Set(selected.compactMap(\.scope.groupID))
        let file = GestureConfigFile(
            version: Constants.configVersion,
            gestures: selected,
            appGroups: appGroups.filter { referencedGroupIDs.contains($0.id) }
        )
        return try encoder.encode(file)
    }

    /// Decode a package and classify each profile as unique or duplicate vs current store content.
    func analyzeImportPackage(from data: Data) throws -> GestureImportAnalysis {
        let package: GestureConfigFile
        switch try decodeConfig(from: data) {
        case .current(let file, _):
            package = file
        case .legacy(let profiles):
            package = Self.file(gestures: profiles)
        }
        try validate(package)
        guard !package.gestures.isEmpty else {
            throw GestureImportExportError.emptyPackage
        }
        let (importedProfiles, groupsToAdd) = resolveImportedGroups(package)
        var unique: [GestureProfile] = []
        var duplicates: [GestureProfile] = []
        var ordered: [GestureProfile] = []
        unique.reserveCapacity(importedProfiles.count)
        ordered.reserveCapacity(importedProfiles.count)
        for profile in importedProfiles {
            ordered.append(profile)
            if gestures.contains(where: { $0.isContentEqual(to: profile) }) {
                duplicates.append(profile)
            } else {
                unique.append(profile)
            }
        }
        return GestureImportAnalysis(
            unique: unique,
            duplicates: duplicates,
            ordered: ordered,
            groups: groupsToAdd
        )
    }

    /// Maps package groups onto local ones (same id, else same content) and
    /// returns the groups that still need to be added.
    private func resolveImportedGroups(
        _ package: GestureConfigFile
    ) -> ([GestureProfile], [AppGroup]) {
        let referenced = Set(package.gestures.compactMap(\.scope.groupID))
        var remap: [UUID: UUID] = [:]
        var groupsToAdd: [AppGroup] = []
        for group in package.appGroups where referenced.contains(group.id) {
            if appGroups.contains(where: { $0.id == group.id }) {
                remap[group.id] = group.id
            } else if let local = appGroups.first(where: { $0.isContentEqual(to: group) }) {
                remap[group.id] = local.id
            } else {
                remap[group.id] = group.id
                groupsToAdd.append(group)
            }
        }
        let profiles = package.gestures.map { profile in
            guard let groupID = profile.scope.groupID,
                  let mapped = remap[groupID]
            else {
                return profile
            }
            var remapped = profile
            remapped.scope = .group(mapped)
            return remapped
        }
        return (profiles, groupsToAdd)
    }

    /// Assign fresh UUIDs, append profiles, and persist once.
    /// - Returns: IDs of the newly imported profiles (for UI selection).
    @discardableResult
    func importProfiles(
        _ profiles: [GestureProfile],
        groups: [AppGroup] = []
    ) throws -> [UUID] {
        guard !profiles.isEmpty else { return [] }
        guard !requiresRecovery else {
            throw GestureImportExportError.persistFailed(
                lastFailure?.localizedDescription
                    ?? L10n.string("config.failure.recoveryRequired")
            )
        }
        var newIDs: [UUID] = []
        var candidate = library
        newIDs.reserveCapacity(profiles.count)
        for profile in profiles {
            var imported = profile
            let newID = UUID()
            imported.id = newID
            candidate.gestures.append(imported)
            newIDs.append(newID)
        }
        let referenced = Set(profiles.compactMap(\.scope.groupID))
        for group in groups
        where referenced.contains(group.id)
            && !candidate.appGroups.contains(where: { $0.id == group.id })
        {
            candidate.appGroups.append(group)
        }
        do {
            try persist(candidate)
            publish(candidate)
        } catch {
            recordFailure(error)
            throw GestureImportExportError.persistFailed(error.localizedDescription)
        }
        return newIDs
    }

    /// Decode a package and import according to duplicate policy.
    /// Force-imported duplicates are disabled by default.
    /// - Returns: IDs of the newly imported profiles (for UI selection).
    @discardableResult
    func importPackage(from data: Data, duplicatePolicy: GestureImportDuplicatePolicy = .forceAll) throws -> [UUID] {
        let analysis = try analyzeImportPackage(from: data)
        return try importProfiles(
            analysis.profilesToImport(policy: duplicatePolicy),
            groups: analysis.groups
        )
    }

    /// Enabled gestures for the mouse button used for this stroke.
    /// App scope is evaluated later against each profile's frozen target.
    func enabledGestures(button: MouseTriggerButton) -> [GestureProfile] {
        gestures.filter { profile in
            guard profile.isEnabled,
                  case .drawn(let drawn) = profile.input,
                  case .mouse(let trigger) = drawn.activation
            else {
                return false
            }
            return trigger.button == button
        }
    }

    /// Buttons used by any currently enabled gesture (for event-tap watch set).
    func enabledTriggerButtons() -> Set<MouseTriggerButton> {
        Set(gestures.compactMap { profile in
            guard profile.isEnabled,
                  case .drawn(let drawn) = profile.input,
                  case .mouse(let trigger) = drawn.activation
            else {
                return nil
            }
            return trigger.button
        })
    }

    private func persist(_ library: GestureConfigFile) throws {
        var file = library
        file.version = Constants.configVersion
        try validate(file)
        let dir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(file)
        let temp = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { removeTemporaryItemIfPresent(at: temp) }
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: configURL.path) {
            try replaceItem(configURL, temp)
        } else {
            try fileManager.moveItem(at: temp, to: configURL)
        }
    }

    private func validate(_ file: GestureConfigFile) throws {
        try validate(file.gestures)
        var groupIDs = Set<UUID>()
        for group in file.appGroups {
            guard groupIDs.insert(group.id).inserted else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .duplicateAppGroupID(group.id)
                )
            }
        }
        var policyKeys = Set<String>()
        for policy in file.appPolicies {
            guard let key = AppMatching.normalizedBundleIdentifier(
                policy.bundleIdentifier
            )?.lowercased(),
                policyKeys.insert(key).inserted
            else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .invalidAppPolicy(policy.bundleIdentifier)
                )
            }
        }
        for profile in file.gestures {
            if let groupID = profile.scope.groupID, !groupIDs.contains(groupID) {
                throw ConfigStoreFailure.invalidConfiguration(
                    .missingAppGroup(groupID)
                )
            }
        }
    }

    private func validate(_ profiles: [GestureProfile]) throws {
        var ids = Set<UUID>()
        for profile in profiles {
            guard ids.insert(profile.id).inserted else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .duplicateProfileID(profile.id)
                )
            }
            guard case .drawn(let drawn) = profile.input else { continue }
            guard drawn.allPaths.count <= DrawnGesture.maximumSampleCount else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .tooManyDrawnSamples(profile.id)
                )
            }
            guard drawn.allPaths.allSatisfy({ $0.count >= 2 }) else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .drawnPathTooShort(profile.id)
                )
            }
            guard drawn.allPaths.joined().allSatisfy({
                $0.x.isFinite && $0.y.isFinite
            }) else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .nonFiniteDrawnPoint(profile.id)
                )
            }
            guard drawn.allPaths.allSatisfy({ path in
                zip(path, path.dropFirst()).contains { lhs, rhs in
                    lhs.x != rhs.x || lhs.y != rhs.y
                }
            }) else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .zeroLengthDrawnPath(profile.id)
                )
            }
        }
    }

    private func decodeConfig(from data: Data) throws -> DecodedConfig {
        let header: GestureConfigHeader
        do {
            header = try decoder.decode(GestureConfigHeader.self, from: data)
        } catch {
            throw ConfigStoreFailure.decodeFailed(error.localizedDescription)
        }

        switch header.version {
        case Constants.configVersion:
            do {
                let file = try decoder.decode(GestureConfigFile.self, from: data)
                let compatibility = try decoder.decode(
                    GestureConfigCompatibilityFile.self,
                    from: data
                )
                return .current(
                    file,
                    requiresCompatibilityRewrite: compatibility
                        .storesNativeApplicationSwitch
                )
            } catch {
                throw ConfigStoreFailure.decodeFailed(error.localizedDescription)
            }
        case 1:
            do {
                let legacy = try decoder.decode(LegacyGestureConfigFile.self, from: data)
                return .legacy(legacy.gestures.map(\.profile))
            } catch {
                throw ConfigStoreFailure.decodeFailed(error.localizedDescription)
            }
        default:
            throw ConfigStoreFailure.unsupportedVersion(header.version)
        }
    }

    private func preserveLegacyBackup(_ data: Data) throws {
        let directory = configURL.deletingLastPathComponent()
        let backupURL = directory
            .appendingPathComponent(Constants.legacyConfigBackupFileName)
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString).v1-backup.tmp")
        defer { removeTemporaryItemIfPresent(at: temporaryURL) }
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try fileManager.moveItem(at: temporaryURL, to: backupURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path) {
                return
            }
            throw ConfigStoreFailure.backupFailed(error.localizedDescription)
        }
    }

    private func preserveRecoveryCopy() throws -> URL {
        let directory = configURL.deletingLastPathComponent()
        let backupURL = directory.appendingPathComponent(
            "\(Constants.configFileName).recovery.\(UUID().uuidString).bak"
        )
        do {
            try fileManager.copyItem(at: configURL, to: backupURL)
            return backupURL
        } catch {
            throw ConfigStoreFailure.recoveryBackupFailed(
                error.localizedDescription
            )
        }
    }

    @discardableResult
    private func recordFailure(_ error: Error) -> ConfigStoreFailure {
        let failure = (error as? ConfigStoreFailure)
            ?? .persistenceFailed(error.localizedDescription)
        lastFailure = failure
        lastError = failure.localizedDescription
        return failure
    }

    private func removeTemporaryItemIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Self.logger.error(
                "Failed to remove temporary config item \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func commit(_ candidate: [GestureProfile]) {
        var file = library
        file.gestures = candidate
        commit(file)
    }

    private func commit(_ candidate: GestureConfigFile) {
        guard !requiresRecovery else { return }
        do {
            try persist(candidate)
            publish(candidate)
        } catch {
            recordFailure(error)
        }
    }

    private func publish(_ file: GestureConfigFile) {
        gestures = file.gestures
        appPolicies = file.appPolicies
        appGroups = file.appGroups
        lastFailure = nil
        lastError = nil
        onGesturesChanged?()
    }

    private static func file(gestures: [GestureProfile]) -> GestureConfigFile {
        GestureConfigFile(version: Constants.configVersion, gestures: gestures)
    }

    private static func defaultLibrary() -> GestureConfigFile {
        file(gestures: DefaultGestures.make())
    }
}

enum AppGroupGestureDisposition: Sendable {
    case delete
    case makeGlobal
}

private enum DecodedConfig {
    case current(
        GestureConfigFile,
        requiresCompatibilityRewrite: Bool
    )
    case legacy([GestureProfile])
}

private struct GestureConfigHeader: Decodable {
    let version: Int
}

private struct GestureConfigCompatibilityFile: Decodable {
    let gestures: [GestureConfigCompatibilityProfile]

    var storesNativeApplicationSwitch: Bool {
        gestures.contains { $0.action?.storesNativeApplicationSwitch == true }
    }
}

private struct GestureConfigCompatibilityProfile: Decodable {
    let action: GestureConfigCompatibilityAction?
}

private struct GestureConfigCompatibilityAction: Decodable {
    let storesNativeApplicationSwitch: Bool

    private enum CodingKeys: String, CodingKey {
        case applicationSwitch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storesNativeApplicationSwitch = container.contains(.applicationSwitch)
    }
}

private struct LegacyGestureConfigFile: Decodable {
    let version: Int
    let gestures: [LegacyGestureProfile]
}

private struct LegacyGestureProfile: Decodable {
    let id: UUID
    let name: String
    let isEnabled: Bool
    let trigger: GestureTrigger
    let pattern: GesturePattern
    let action: GestureAction
    let scope: AppScope
    let targetPolicy: GestureTargetPolicy
    let notes: String

    var profile: GestureProfile {
        GestureProfile(
            id: id,
            name: name,
            isEnabled: isEnabled,
            trigger: trigger,
            pattern: pattern,
            action: action,
            scope: scope,
            targetPolicy: targetPolicy,
            notes: notes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case trigger
        case pattern
        case action
        case scope
        case targetPolicy
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        trigger = try container.decodeIfPresent(GestureTrigger.self, forKey: .trigger) ?? .default
        pattern = try container.decode(GesturePattern.self, forKey: .pattern)
        action = try container.decodeIfPresent(GestureAction.self, forKey: .action) ?? .none
        scope = try container.decodeIfPresent(AppScope.self, forKey: .scope) ?? .global
        targetPolicy = try container.decodeIfPresent(GestureTargetPolicy.self, forKey: .targetPolicy)
            ?? .frontmostWindow
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

enum ConfigStoreFailure: Error, Equatable, LocalizedError, Sendable {
    case recoveryRequired
    case unsupportedVersion(Int)
    case decodeFailed(String)
    case invalidConfiguration(ConfigValidationFailure)
    case backupFailed(String)
    case recoveryBackupFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .recoveryRequired:
            return L10n.string("config.failure.recoveryRequired")
        case .unsupportedVersion(let version):
            return String(
                format: L10n.string("config.failure.unsupportedVersion"),
                locale: L10n.locale,
                version
            )
        case .decodeFailed(let message):
            return String(
                format: L10n.string("config.failure.decode"),
                locale: L10n.locale,
                message
            )
        case .invalidConfiguration(let reason):
            return reason.localizedDescription
        case .backupFailed(let message):
            return String(
                format: L10n.string("config.failure.backup"),
                locale: L10n.locale,
                message
            )
        case .recoveryBackupFailed(let message):
            return String(
                format: L10n.string("config.failure.recoveryBackup"),
                locale: L10n.locale,
                message
            )
        case .persistenceFailed(let message):
            return String(
                format: L10n.string("config.failure.persistence"),
                locale: L10n.locale,
                message
            )
        }
    }
}

enum ConfigValidationFailure: Equatable, Sendable {
    case duplicateProfileID(UUID)
    case tooManyDrawnSamples(UUID)
    case drawnPathTooShort(UUID)
    case nonFiniteDrawnPoint(UUID)
    case zeroLengthDrawnPath(UUID)
    case duplicateAppGroupID(UUID)
    case missingAppGroup(UUID)
    case invalidAppPolicy(String)

    var localizedDescription: String {
        let key: String
        let argument: String
        switch self {
        case .duplicateProfileID(let id):
            key = "config.failure.duplicateID"
            argument = id.uuidString
        case .tooManyDrawnSamples(let id):
            key = "config.failure.tooManyDrawnSamples"
            argument = id.uuidString
        case .drawnPathTooShort(let id):
            key = "config.failure.drawnPathTooShort"
            argument = id.uuidString
        case .nonFiniteDrawnPoint(let id):
            key = "config.failure.nonFinitePoint"
            argument = id.uuidString
        case .zeroLengthDrawnPath(let id):
            key = "config.failure.zeroLengthDrawnPath"
            argument = id.uuidString
        case .duplicateAppGroupID(let id):
            key = "config.failure.duplicateAppGroupID"
            argument = id.uuidString
        case .missingAppGroup(let id):
            key = "config.failure.missingAppGroup"
            argument = id.uuidString
        case .invalidAppPolicy(let bundleIdentifier):
            key = "config.failure.invalidAppPolicy"
            argument = bundleIdentifier
        }
        return String(
            format: L10n.string(key),
            locale: L10n.locale,
            argument
        )
    }
}

// MARK: - Import / Export types

enum GestureImportDuplicatePolicy: Sendable {
    /// Import every profile, including ones that already exist by content.
    case forceAll
    /// Import only profiles that do not match existing content.
    case skipDuplicates
}

struct GestureImportAnalysis: Equatable, Sendable {
    /// Profiles with no content match in the current store (package order among uniques).
    let unique: [GestureProfile]
    /// Profiles that match existing store content (package order among duplicates).
    let duplicates: [GestureProfile]
    /// Full package in original order (migrated).
    let ordered: [GestureProfile]
    /// Package app groups referenced by the profiles and missing locally.
    var groups: [AppGroup] = []

    var totalCount: Int { ordered.count }
    var hasDuplicates: Bool { !duplicates.isEmpty }

    /// Profiles to import for the chosen policy.
    /// Force-imported duplicates keep content but set `isEnabled = false`.
    func profilesToImport(policy: GestureImportDuplicatePolicy) -> [GestureProfile] {
        switch policy {
        case .skipDuplicates:
            return unique
        case .forceAll:
            return ordered.map { profile in
                guard duplicates.contains(where: { $0.isContentEqual(to: profile) }) else {
                    return profile
                }
                var disabled = profile
                disabled.isEnabled = false
                return disabled
            }
        }
    }
}

enum GestureImportExportError: Error, Equatable, LocalizedError {
    case emptySelection
    case emptyPackage
    case persistFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return L10n.string("config.failure.emptyExport")
        case .emptyPackage:
            return L10n.string("config.failure.emptyImport")
        case .persistFailed(let message):
            return message
        }
    }
}
