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
    private(set) var lastError: String?
    private(set) var lastFailure: ConfigStoreFailure?
    private(set) var configURL: URL
    private(set) var requiresRecovery = false

    /// Called after gestures are mutated and persisted (or after load).
    var onGesturesChanged: (() -> Void)?

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
                case .current(let profiles):
                    try validate(profiles)
                    publish(profiles)
                case .legacy(let profiles):
                    try validate(profiles)
                    try preserveLegacyBackup(data)
                    try persist(profiles)
                    publish(profiles)
                }
            } else {
                let defaults = DefaultGestures.make()
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
            try persist(gestures)
            publish(gestures)
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

    func resetToDefaults() {
        commit(DefaultGestures.make())
    }

    /// Replaces an unreadable/unsupported config only after preserving its
    /// exact bytes in a uniquely named, non-overwriting recovery copy.
    @discardableResult
    func recoverWithDefaults() throws -> URL? {
        guard requiresRecovery else { return nil }
        let backupURL = try preserveRecoveryCopy()
        let defaults = DefaultGestures.make()
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
        let file = GestureConfigFile(version: Constants.configVersion, gestures: selected)
        return try encoder.encode(file)
    }

    /// Decode a package and classify each profile as unique or duplicate vs current store content.
    func analyzeImportPackage(from data: Data) throws -> GestureImportAnalysis {
        let importedProfiles: [GestureProfile]
        switch try decodeConfig(from: data) {
        case .current(let profiles), .legacy(let profiles):
            importedProfiles = profiles
        }
        try validate(importedProfiles)
        guard !importedProfiles.isEmpty else {
            throw GestureImportExportError.emptyPackage
        }
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
        return GestureImportAnalysis(unique: unique, duplicates: duplicates, ordered: ordered)
    }

    /// Assign fresh UUIDs, append profiles, and persist once.
    /// - Returns: IDs of the newly imported profiles (for UI selection).
    @discardableResult
    func importProfiles(_ profiles: [GestureProfile]) throws -> [UUID] {
        guard !profiles.isEmpty else { return [] }
        guard !requiresRecovery else {
            throw GestureImportExportError.persistFailed(
                lastFailure?.localizedDescription
                    ?? L10n.string("config.failure.recoveryRequired")
            )
        }
        var newIDs: [UUID] = []
        var candidate = gestures
        newIDs.reserveCapacity(profiles.count)
        for profile in profiles {
            var imported = profile
            let newID = UUID()
            imported.id = newID
            candidate.append(imported)
            newIDs.append(newID)
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
        return try importProfiles(analysis.profilesToImport(policy: duplicatePolicy))
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

    private func persist(_ profiles: [GestureProfile]) throws {
        try validate(profiles)
        let dir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = GestureConfigFile(
            version: Constants.configVersion,
            gestures: profiles
        )
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

    private func validate(_ profiles: [GestureProfile]) throws {
        var ids = Set<UUID>()
        for profile in profiles {
            guard ids.insert(profile.id).inserted else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .duplicateProfileID(profile.id)
                )
            }
            guard case .drawn(let drawn) = profile.input else { continue }
            guard drawn.points.count >= 2 else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .drawnPathTooShort(profile.id)
                )
            }
            guard drawn.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                throw ConfigStoreFailure.invalidConfiguration(
                    .nonFiniteDrawnPoint(profile.id)
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
                return .current(try decoder.decode(GestureConfigFile.self, from: data).gestures)
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

    private func recordFailure(_ error: Error) {
        let failure = (error as? ConfigStoreFailure)
            ?? .persistenceFailed(error.localizedDescription)
        lastFailure = failure
        lastError = failure.localizedDescription
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
        guard !requiresRecovery else { return }
        do {
            try persist(candidate)
            publish(candidate)
        } catch {
            recordFailure(error)
        }
    }

    private func publish(_ profiles: [GestureProfile]) {
        gestures = profiles
        lastFailure = nil
        lastError = nil
        onGesturesChanged?()
    }
}

private enum DecodedConfig {
    case current([GestureProfile])
    case legacy([GestureProfile])
}

private struct GestureConfigHeader: Decodable {
    let version: Int
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
    case unsupportedVersion(Int)
    case decodeFailed(String)
    case invalidConfiguration(ConfigValidationFailure)
    case backupFailed(String)
    case recoveryBackupFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
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
    case drawnPathTooShort(UUID)
    case nonFiniteDrawnPoint(UUID)

    var localizedDescription: String {
        let key: String
        switch self {
        case .duplicateProfileID:
            key = "config.failure.duplicateID"
        case .drawnPathTooShort:
            key = "config.failure.drawnPathTooShort"
        case .nonFiniteDrawnPoint:
            key = "config.failure.nonFinitePoint"
        }
        let id: UUID
        switch self {
        case .duplicateProfileID(let value),
             .drawnPathTooShort(let value),
             .nonFiniteDrawnPoint(let value):
            id = value
        }
        return String(
            format: L10n.string(key),
            locale: L10n.locale,
            id.uuidString
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
