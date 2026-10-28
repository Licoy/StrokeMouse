import CryptoKit
import XCTest
@testable import StrokeMouse

@MainActor
final class WindowMaximizeConfigCompatibilityTests: XCTestCase {
    func testPrimaryAndSecondaryMaximizeSurviveExportImportAndReload() throws {
        try withStore { source, url in
            let profiles = maximizeProfiles()
            source.replaceAll(profiles)
            XCTAssertNil(source.lastFailure)
            let package = try source.exportPackage(ids: Set(profiles.map(\.id)))
            let exported = try JSONDecoder().decode(GestureConfigFile.self, from: package)
            XCTAssertEqual(exported.version, 5)
            XCTAssertEqual(exported.gestures, profiles)
            XCTAssertEqual(try JSONDecoder().decode(
                GestureConfigFile.self, from: Data(contentsOf: url)
            ).version, 5)

            let destinationURL = url.deletingLastPathComponent().appendingPathComponent("import.json")
            let destination = ConfigStore(configURL: destinationURL)
            destination.replaceAll([])
            XCTAssertNil(destination.lastFailure)
            let importedIDs = try destination.importPackage(from: package)
            XCTAssertEqual(importedIDs.count, profiles.count)
            XCTAssertEqual(Set(importedIDs).count, profiles.count)
            XCTAssertTrue(Set(importedIDs).isDisjoint(with: Set(profiles.map(\.id))))
            let expected = zip(profiles, importedIDs).map { profile, id in
                var imported = profile
                imported.id = id
                return imported
            }
            XCTAssertEqual(destination.gestures, expected)
            XCTAssertEqual(ConfigStore(configURL: destinationURL).gestures, expected)
            XCTAssertFalse(ConfigStore(configURL: destinationURL).requiresRecovery)
        }
    }

    func testLibrariesWithoutMaximizeKeepExistingExportVersions() throws {
        try withStore { store, _ in
            let cases: [(GestureProfile, Int)] = [
                (profile(action: .window(.zoom)), 2),
                (profile(action: .window(.fullscreen)), 2),
                (profile(action: .shortcut(chord: .init(modifiers: [.function], keyCode: nil))), 3),
                (profile(action: .system(.init(command: .missionControl))), 4),
                (GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)),
                                targetPolicy: .windowUnderPointer), 4)
            ]
            for (profile, version) in cases {
                store.replaceAll([profile])
                XCTAssertNil(store.lastFailure)
                let data = try store.exportPackage(ids: [profile.id])
                let file = try JSONDecoder().decode(GestureConfigFile.self, from: data)
                XCTAssertEqual(file.version, version)
                XCTAssertEqual(file.gestures, [profile])
            }
            XCTAssertEqual(WindowCommand.zoom.rawValue, "zoom")
            XCTAssertEqual(WindowCommand.fullscreen.rawValue, "fullscreen")
        }
    }

    func testMislabeledAndFuturePackagesCannotChangeLocalStore() throws {
        try withStore { store, url in
            let before = store.gestures
            let bytes = try Data(contentsOf: url)
            for profile in maximizeProfiles() {
                for version in [2, 3, 4, 99] {
                    let file = GestureConfigFile(version: version, gestures: [profile])
                    XCTAssertThrowsError(try store.importPackage(from: JSONEncoder().encode(file))) {
                        XCTAssertEqual($0 as? ConfigStoreFailure, .unsupportedVersion(version))
                    }
                    XCTAssertThrowsError(try store.replaceFromBackup(file)) {
                        XCTAssertEqual($0 as? ConfigStoreFailure, .unsupportedVersion(version))
                    }
                    XCTAssertEqual(store.gestures, before)
                    XCTAssertEqual(try Data(contentsOf: url), bytes)
                }
            }
        }
    }

    func testBackupCodecAndRestoreSupportV5OverwriteAndMerge() throws {
        try withStore { store, url in
            let profiles = maximizeProfiles()
            store.replaceAll(profiles)
            XCTAssertNil(store.lastFailure)
            let payload = BackupPayloadV1(
                gestures: try store.makeBackupGestureFile(), settings: nil,
                restoredFromSnapshotID: nil
            )
            let plaintext = try BackupCodec.encodePlaintext(payload: payload, metadata: metadata())
            let encrypted = try BackupCodec.encodeEncrypted(
                payload: payload, metadata: metadata(), password: "maximize backup password"
            )
            let decoded = try BackupCodec.decode(plaintext.data)
            XCTAssertEqual(decoded.payload, payload)
            XCTAssertEqual(try BackupCodec.decode(
                encrypted.data, derivedKey: XCTUnwrap(encrypted.derivedKey)
            ).payload, payload)
            let local = profile(action: .window(.center))
            let cases: [(SyncRestoreMode, [GestureProfile])] = [
                (.overwrite, profiles),
                (.merge(decisions: .init(), defaultDuplicatePolicy: .skip), [local] + profiles)
            ]
            for (mode, expected) in cases {
                store.replaceAll([local])
                XCTAssertNil(store.lastFailure)
                try restore(decoded, mode: mode, store: store, rollback: plaintext.data)
                XCTAssertEqual(store.gestures, expected)
                XCTAssertEqual(ConfigStore(configURL: url).gestures, expected)
                XCTAssertEqual(try store.makeBackupGestureFile().version, 5)
            }
        }
    }

    func testBackupCodecAndMergeRejectMislabeledAndFutureVersions() throws {
        try withStore { store, url in
            store.replaceAll(maximizeProfiles())
            XCTAssertNil(store.lastFailure)
            let payload = BackupPayloadV1(
                gestures: try store.makeBackupGestureFile(), settings: nil,
                restoredFromSnapshotID: nil
            )
            let valid = try BackupCodec.encodePlaintext(payload: payload, metadata: metadata())
            let before = store.gestures
            let bytes = try Data(contentsOf: url)
            for version in [2, 3, 4, 99] {
                var invalid = payload
                invalid.gestures.version = version
                XCTAssertThrowsError(try BackupCodec.encodePlaintext(payload: invalid, metadata: metadata())) {
                    XCTAssertEqual($0 as? BackupCodecError, .unsupportedGestureConfigVersion(version))
                }
                let document = try documentWithPayload(invalid, envelope: valid.envelope)
                XCTAssertThrowsError(try BackupCodec.decode(document)) {
                    XCTAssertEqual($0 as? BackupCodecError, .unsupportedGestureConfigVersion(version))
                }
                XCTAssertThrowsError(try BackupMergePlanner.plan(
                    local: GestureConfigFile.empty, backup: invalid.gestures,
                    localSettings: [String: String](), backupSettings: [:]
                )) {
                    XCTAssertEqual($0 as? BackupMergePlannerError,
                                   .unsupportedConfigVersion(side: .backup, version: version))
                }
                let invalidBackup = BackupDecodedBackup(envelope: valid.envelope, payload: invalid)
                XCTAssertThrowsError(try restore(
                    invalidBackup, mode: .overwrite, store: store, rollback: valid.data
                )) {
                    XCTAssertEqual($0 as? ConfigStoreFailure, .unsupportedVersion(version))
                }
                XCTAssertEqual(store.gestures, before)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testLoadingUnknownVersionPreservesMemoryAndDisk() throws {
        try withStore { store, url in
            let before = store.gestures
            let future = try JSONEncoder().encode(GestureConfigFile(version: 99, gestures: maximizeProfiles()))
            try future.write(to: url)
            store.load()
            XCTAssertTrue(store.requiresRecovery)
            XCTAssertEqual(store.lastFailure, .unsupportedVersion(99))
            XCTAssertEqual(store.gestures, before)
            XCTAssertEqual(try Data(contentsOf: url), future)
        }
    }

    private func restore(
        _ decoded: BackupDecodedBackup, mode: SyncRestoreMode,
        store: ConfigStore, rollback: Data
    ) throws {
        let suite = "WindowMaximizeRestore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ConfigurationRestoreEngine(configStore: store, defaults: defaults, applyConfiguration: {})
        let id = RemoteBackupID(providerID: "test", containerID: "test", revisionID: "test")
        let prepared = try engine.prepare(backupID: id, decoded: decoded)
        _ = try engine.restore(prepared, request: RestoreRequest(
            backupID: id, mode: mode, confirmsScriptRisk: false,
            confirmsExperimentalTrackpadRisk: false
        ), rollbackDocument: rollback)
    }

    private func documentWithPayload(
        _ payload: BackupPayloadV1, envelope: BackupEnvelopeV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var result = envelope
        result.payloadRepresentation = try encoder.encode(payload)
        result.payloadDigest = Data(SHA256.hash(data: result.payloadRepresentation))
        return try encoder.encode(result)
    }

    private func metadata() -> BackupMetadataV1 {
        BackupMetadataV1(snapshotID: UUID(), createdAt: Date(timeIntervalSince1970: 1),
                         kind: .manual, deviceID: UUID(), deviceName: "Test Mac",
                         appVersion: "1", appBuild: "1", scope: .gesturesOnly)
    }

    private func maximizeProfiles() -> [GestureProfile] {
        var secondary = GestureProfile(name: "Secondary", pattern: .freePath(PathTemplates.down), action: .window(.zoom))
        secondary.secondaryAction = .window(.maximize)
        return [profile(action: .window(.maximize)), secondary]
    }

    private func profile(action: GestureAction) -> GestureProfile {
        GestureProfile(name: "Primary", pattern: .freePath(PathTemplates.up), action: action)
    }

    private func withStore(_ body: (ConfigStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WindowMaximizeConfig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gestures.json")
        try body(ConfigStore(configURL: url), url)
    }
}
