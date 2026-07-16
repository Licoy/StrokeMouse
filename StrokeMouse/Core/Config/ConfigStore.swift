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
