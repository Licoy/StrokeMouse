import Foundation
import Observation

@MainActor
@Observable
final class ConfigStore {
    private(set) var gestures: [GestureProfile] = []
    private(set) var lastError: String?
    private(set) var configURL: URL

    /// Called after gestures are mutated and persisted (or after load).
    var onGesturesChanged: (() -> Void)?

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = support.appendingPathComponent(Constants.supportDirectoryName, isDirectory: true)
        configURL = dir.appendingPathComponent(Constants.configFileName)
        Self.migrateLegacySupportDirectoryIfNeeded(to: dir, supportRoot: support, fileManager: fileManager)
        load()
    }

    /// Copy config from the pre-rename Application Support folder when present.
    private static func migrateLegacySupportDirectoryIfNeeded(
        to newDir: URL,
        supportRoot: URL,
        fileManager: FileManager
    ) {
        let legacyDir = supportRoot.appendingPathComponent(Constants.legacySupportDirectoryName, isDirectory: true)
        let legacyConfig = legacyDir.appendingPathComponent(Constants.configFileName)
        let newConfig = newDir.appendingPathComponent(Constants.configFileName)
        guard fileManager.fileExists(atPath: legacyConfig.path),
              !fileManager.fileExists(atPath: newConfig.path)
        else { return }
        do {
            try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyConfig, to: newConfig)
        } catch {
            // Non-fatal: first launch will seed defaults if migration fails.
        }
    }

    /// Testing initializer with custom config location.
    init(configURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.configURL = configURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        load()
    }

    func load() {
        lastError = nil
        let dir = configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                let file = try decoder.decode(GestureConfigFile.self, from: data)
                // Migrate legacy direction patterns to free-path templates.
                gestures = file.gestures.map { profile in
                    var p = profile
                    if case .directions(let dirs) = p.pattern {
                        p.pattern = .freePath(PathTemplates.fromDirections(dirs).map(CodablePoint.init))
                    }
                    return p
                }
                if gestures != file.gestures {
                    try persist()
                }
                onGesturesChanged?()
            } else {
                gestures = DefaultGestures.make()
                try persist()
                onGesturesChanged?()
            }
        } catch {
            lastError = error.localizedDescription
            gestures = DefaultGestures.make()
            onGesturesChanged?()
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            try persist()
            lastError = nil
            onGesturesChanged?()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func add(_ profile: GestureProfile) {
        gestures.append(profile)
        save()
    }

    func update(_ profile: GestureProfile) {
        guard let index = gestures.firstIndex(where: { $0.id == profile.id }) else { return }
        gestures[index] = profile
        save()
    }

    func delete(id: UUID) {
        gestures.removeAll { $0.id == id }
        save()
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        gestures.removeAll { ids.contains($0.id) }
        save()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = gestures.firstIndex(where: { $0.id == id }) else { return }
        gestures[index].isEnabled = enabled
        save()
    }

    func setEnabled(ids: Set<UUID>, enabled: Bool) {
        guard !ids.isEmpty else { return }
        var changed = false
        for index in gestures.indices where ids.contains(gestures[index].id) {
            if gestures[index].isEnabled != enabled {
                gestures[index].isEnabled = enabled
                changed = true
            }
        }
        if changed { save() }
    }

    func replaceAll(_ profiles: [GestureProfile]) {
        gestures = profiles
        save()
    }

    func resetToDefaults() {
        gestures = DefaultGestures.make()
        save()
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
        let file = try decoder.decode(GestureConfigFile.self, from: data)
        guard !file.gestures.isEmpty else {
            throw GestureImportExportError.emptyPackage
        }
        var unique: [GestureProfile] = []
        var duplicates: [GestureProfile] = []
        var ordered: [GestureProfile] = []
        unique.reserveCapacity(file.gestures.count)
        ordered.reserveCapacity(file.gestures.count)
        for profile in file.gestures {
            let migrated = Self.migratedProfile(profile)
            ordered.append(migrated)
            if gestures.contains(where: { $0.isContentEqual(to: migrated) }) {
                duplicates.append(migrated)
            } else {
                unique.append(migrated)
            }
        }
        return GestureImportAnalysis(unique: unique, duplicates: duplicates, ordered: ordered)
    }

    /// Assign fresh UUIDs, append profiles, and persist once.
    /// - Returns: IDs of the newly imported profiles (for UI selection).
    @discardableResult
    func importProfiles(_ profiles: [GestureProfile]) throws -> [UUID] {
        guard !profiles.isEmpty else { return [] }
        var newIDs: [UUID] = []
        newIDs.reserveCapacity(profiles.count)
        for profile in profiles {
            var imported = Self.migratedProfile(profile)
            let newID = UUID()
            imported.id = newID
            gestures.append(imported)
            newIDs.append(newID)
        }
        guard save() else {
            let imported = Set(newIDs)
            gestures.removeAll { imported.contains($0.id) }
            throw GestureImportExportError.persistFailed(lastError ?? "Unknown error")
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

    /// Migrate legacy direction patterns to free-path templates (same as `load()`).
    private static func migratedProfile(_ profile: GestureProfile) -> GestureProfile {
        var p = profile
        if case .directions(let dirs) = p.pattern {
            p.pattern = .freePath(PathTemplates.fromDirections(dirs).map(CodablePoint.init))
        }
        return p
    }

    /// Enabled gestures for the frontmost app and the mouse button used for this stroke.
    func enabledGestures(frontmostBundleId: String?, button: MouseTriggerButton) -> [GestureProfile] {
        gestures.filter { profile in
            guard profile.isEnabled else { return false }
            guard profile.trigger.button == button else { return false }
            switch profile.scope {
            case .global:
                return true
            case .apps(let ids):
                guard let frontmostBundleId else { return false }
                return ids.contains(frontmostBundleId)
            }
        }
    }

    /// Buttons used by any currently enabled gesture (for event-tap watch set).
    func enabledTriggerButtons() -> Set<MouseTriggerButton> {
        Set(gestures.compactMap { $0.isEnabled ? $0.trigger.button : nil })
    }

    private func persist() throws {
        let dir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = GestureConfigFile(version: Constants.configVersion, gestures: gestures)
        let data = try encoder.encode(file)
        let temp = configURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: configURL.path) {
            _ = try fileManager.replaceItemAt(configURL, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: configURL)
        }
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
            return "No gestures selected for export."
        case .emptyPackage:
            return "No gestures found in this file."
        case .persistFailed(let message):
            return message
        }
    }
}
