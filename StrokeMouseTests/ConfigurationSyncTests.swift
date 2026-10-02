import AppKit
import XCTest
@testable import StrokeMouse

@MainActor
final class ConfigurationSyncTests: XCTestCase {
    func testDefaultProviderSelectionIsWebDAV() {
        XCTAssertEqual(SyncProviderKind.defaultSelection, .webDAV)
    }

    func testSavingConnectionPreflightsRecoveryBeforePersistingCredentials() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try Data("not-json".utf8).write(to: harness.store.configURL, options: .atomic)
        harness.store.load()
        XCTAssertTrue(harness.store.requiresRecovery)

        let draft = SyncConnectionDraft(
            provider: .githubGist,
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true
        )
        assertFailure(await harness.sync.handle(.saveConnection(
            draft,
            SyncSecretChanges(providerSecret: "must-not-persist")
        )))

        let stored = try ConfigurationSyncPersistence(defaults: harness.defaults)
            .loadConfiguration()
        XCTAssertNil(stored)
        let secret = try await harness.vault.credential(
            for: "provider.githubGist"
        )
        XCTAssertNil(secret)
        XCTAssertNil(harness.sync.state.connection)
    }

    func testSaveConnectionCompensatesKeychainWhenPersistenceFails() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        harness.persistence.failNextSaveAfterMutation()

        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "replacementgist",
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        let result = await harness.sync.handle(.saveConnection(
            replacement,
            SyncSecretChanges(providerSecret: "replacement-secret")
        ))
        assertFailure(result)

        let secret = try await harness.vault.credential(
            for: "provider.githubGist"
        )
        XCTAssertEqual(secret, Data("test-token".utf8))
        let stored = try harness.persistence.loadConfiguration()
        XCTAssertEqual(stored?.connection, .githubGist(gistID: nil))
        XCTAssertEqual(harness.sync.state.connection?.gistID, nil)
        assertDoesNotExpose("replacement-secret", in: result)
    }

    func testSaveConnectionCompensatesAKeychainMutationThatThrows() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        await harness.vault.failNext(
            .set,
            account: "provider.githubGist",
            afterMutation: true
        )

        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "replacementgist",
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        let result = await harness.sync.handle(.saveConnection(
            replacement,
            SyncSecretChanges(providerSecret: "replacement-secret")
        ))
        assertFailure(result)

        let secret = try await harness.vault.credential(
            for: "provider.githubGist"
        )
        XCTAssertEqual(secret, Data("test-token".utf8))
        XCTAssertEqual(
            try harness.persistence.loadConfiguration()?.connection,
            .githubGist(gistID: nil)
        )
        assertDoesNotExpose("replacement-secret", in: result)
    }

    func testDisconnectCompensatesCredentialsWhenPersistenceRemovalFails() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        harness.persistence.failNextRemovalAfterMutation()

        let result = await harness.sync.handle(.disconnect)
        assertFailure(result)

        let secret = try await harness.vault.credential(
            for: "provider.githubGist"
        )
        XCTAssertEqual(secret, Data("test-token".utf8))
        XCTAssertNotNil(try harness.persistence.loadConfiguration())
        XCTAssertNotNil(harness.sync.state.connection)
    }

    func testDisconnectCompensatesAKeychainDeletionThatThrows() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        await harness.vault.failNext(
            .delete,
            account: "provider.githubGist",
            afterMutation: true
        )

        assertFailure(await harness.sync.handle(.disconnect))

        let secret = try await harness.vault.credential(
            for: "provider.githubGist"
        )
        XCTAssertEqual(secret, Data("test-token".utf8))
        XCTAssertNotNil(try harness.persistence.loadConfiguration())
        XCTAssertNotNil(harness.sync.state.connection)
    }

    func testSavingConnectionDoesNotWriteAndManualBackupAlwaysCreatesVersion() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        try await connect(harness.sync, automatic: false)
        let countAfterSave = await harness.remote.storeCount()
        XCTAssertEqual(countAfterSave, 0)

        assertSuccess(await harness.sync.handle(.backupNow))
        assertSuccess(await harness.sync.handle(.backupNow))
        let manualCount = await harness.remote.storeCount()
        XCTAssertEqual(manualCount, 2)
        XCTAssertFalse(harness.sync.state.hasPendingBackup)
    }

    func testFirstGistBackupPersistsReturnedContainerWithoutVaultReread() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        await harness.vault.failNext(
            .read,
            account: "provider.githubGist"
        )

        assertSuccess(await harness.sync.handle(.backupNow))

        let stored = try harness.persistence.loadConfiguration()
        XCTAssertEqual(
            stored?.connection,
            .githubGist(gistID: "test-gist")
        )
        XCTAssertEqual(harness.sync.state.connection?.gistID, "test-gist")
        let count = await harness.remote.storeCount()
        XCTAssertEqual(count, 1)
    }

    func testConfigurationChangeIsDebouncedAndUnchangedContentIsNotUploaded() async throws {
        let harness = try makeHarness(debounceInterval: 0.05)
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: true)

        let replacement = makeGesture(name: "Changed")
        try harness.store.replaceFromBackup(
            GestureConfigFile(version: Constants.configVersion, gestures: [replacement])
        )
        harness.sync.noteLocalConfigurationChanged()
        harness.sync.noteLocalConfigurationChanged()
        try await Task.sleep(for: .milliseconds(180))
        let debouncedCount = await harness.remote.storeCount()
        XCTAssertEqual(debouncedCount, 1)

        harness.sync.noteLocalConfigurationChanged()
        try await Task.sleep(for: .milliseconds(120))
        let unchangedCount = await harness.remote.storeCount()
        XCTAssertEqual(unchangedCount, 1)
    }

    func testFailedBackupKeepsPendingStateUntilExplicitRetry() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        await harness.remote.setStoreFailure(true)

        assertFailure(await harness.sync.handle(.backupNow))
        XCTAssertTrue(harness.sync.state.hasPendingBackup)
        XCTAssertNotNil(harness.sync.state.lastFailure)

        await harness.remote.setStoreFailure(false)
        assertSuccess(await harness.sync.handle(.backupNow))
        XCTAssertFalse(harness.sync.state.hasPendingBackup)
        let recoveredCount = await harness.remote.storeCount()
        XCTAssertEqual(recoveredCount, 1)
    }

    func testHourlyAuditMarksMissedChangePendingBeforeRemoteUpload() async throws {
        let clock = TestClock()
        let harness = try makeHarness(now: { clock.now() })
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: true)
        assertSuccess(await harness.sync.handle(.backupNow))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(harness.sync.state.hasPendingBackup)
        try harness.persistence.useInMemoryMutations()

        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [makeGesture(name: "Missed Change")]
        ))
        clock.advance(by: 3_601)
        await harness.remote.setStoreDelay(.milliseconds(80))
        await harness.remote.setStoreFailure(true)
        postWakeNotification()

        for _ in 0..<100 {
            if harness.sync.state.activity == .backingUp { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(harness.sync.state.activity, .backingUp)
        XCTAssertTrue(harness.sync.state.hasPendingBackup)
        for _ in 0..<100 {
            if harness.sync.state.activity == .idle { break }
            try await Task.sleep(for: .milliseconds(3))
        }
        XCTAssertTrue(harness.sync.state.hasPendingBackup)
    }

    func testActivationRechecksHourlyStateAfterCredentialAwait() async throws {
        let clock = TestClock()
        let harness = try makeHarness(
            activates: false,
            now: { clock.now() }
        )
        defer { harness.cleanup() }
        try await harness.vault.setCredential(
            Data("test-token".utf8),
            for: "provider.githubGist"
        )
        try harness.persistence.saveConfiguration(StoredSyncConfiguration(
            connection: .githubGist(gistID: "test-gist"),
            deviceID: UUID(),
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            currentEncryptionKeyID: nil,
            knownEncryptionKeyIDs: [],
            automaticBackupEnabled: true,
            lastSuccessfulContentHash: nil,
            lastSuccess: nil,
            lastHourlyCheck: nil
        ))
        await harness.vault.delayNextRead(
            account: "provider.githubGist"
        )
        await harness.remote.setStoreDelay(.milliseconds(80))
        await harness.remote.setStoreFailure(true)

        harness.sync.activate()
        for _ in 0..<100 {
            if await harness.vault.delayedReadStarted() { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        postWakeNotification()
        for _ in 0..<100 {
            if await harness.remote.storeAttemptCount() >= 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        await harness.vault.resumeDelayedRead()
        try await Task.sleep(for: .milliseconds(180))

        let attempts = await harness.remote.storeAttemptCount()
        XCTAssertEqual(attempts, 1)
    }

    func testActivationDoesNotInstallAdapterForReplacedConnection() async throws {
        let oldRemote = RecordingBackupAdapter()
        let newRemote = RecordingBackupAdapter()
        let harness = try makeHarness(
            activates: false,
            remote: newRemote,
            adapterFactory: { descriptor, _ in
                if descriptor == .githubGist(gistID: "oldgist") {
                    return oldRemote
                }
                return newRemote
            }
        )
        defer { harness.cleanup() }
        try await harness.vault.setCredential(
            Data("old-token".utf8),
            for: "provider.githubGist"
        )
        try harness.persistence.saveConfiguration(StoredSyncConfiguration(
            connection: .githubGist(gistID: "oldgist"),
            deviceID: UUID(),
            deviceName: "Old Mac",
            scope: .gesturesOnly,
            encryption: .none,
            currentEncryptionKeyID: nil,
            knownEncryptionKeyIDs: [],
            automaticBackupEnabled: false,
            lastSuccessfulContentHash: nil,
            lastSuccess: nil,
            lastHourlyCheck: nil
        ))
        await harness.vault.delayNextRead(account: "provider.githubGist")

        harness.sync.activate()
        for _ in 0..<100 {
            if await harness.vault.delayedReadStarted() { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "newgist",
            deviceName: "New Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        assertSuccess(await harness.sync.handle(.saveConnection(
            replacement,
            SyncSecretChanges(providerSecret: "new-token")
        )))
        await harness.vault.resumeDelayedRead()
        try await Task.sleep(for: .milliseconds(20))

        assertSuccess(await harness.sync.handle(.backupNow))

        let oldCount = await oldRemote.storeCount()
        let newCount = await newRemote.storeCount()
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 1)
        XCTAssertEqual(harness.sync.state.connection?.gistID, "newgist")
    }

    func testActivationDoesNotOverwriteSameConnectionReplacementAdapter() async throws {
        let oldRemote = RecordingBackupAdapter()
        let newRemote = RecordingBackupAdapter()
        let harness = try makeHarness(
            activates: false,
            remote: newRemote,
            adapterFactory: { _, secret in
                secret == "old-token" ? oldRemote : newRemote
            }
        )
        defer { harness.cleanup() }
        try await harness.vault.setCredential(
            Data("old-token".utf8),
            for: "provider.githubGist"
        )
        try harness.persistence.saveConfiguration(StoredSyncConfiguration(
            connection: .githubGist(gistID: "samegist"),
            deviceID: UUID(),
            deviceName: "Old Mac",
            scope: .gesturesOnly,
            encryption: .none,
            currentEncryptionKeyID: nil,
            knownEncryptionKeyIDs: [],
            automaticBackupEnabled: false,
            lastSuccessfulContentHash: nil,
            lastSuccess: nil,
            lastHourlyCheck: nil
        ))
        await harness.vault.delayNextRead(account: "provider.githubGist")

        harness.sync.activate()
        for _ in 0..<100 {
            if await harness.vault.delayedReadStarted() { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "samegist",
            deviceName: "New Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        assertSuccess(await harness.sync.handle(.saveConnection(
            replacement,
            SyncSecretChanges(providerSecret: "new-token")
        )))
        await harness.vault.resumeDelayedRead()
        try await Task.sleep(for: .milliseconds(20))

        assertSuccess(await harness.sync.handle(.backupNow))
        let oldCount = await oldRemote.storeCount()
        let newCount = await newRemote.storeCount()
        XCTAssertEqual(oldCount, 0)
        XCTAssertEqual(newCount, 1)
    }

    func testCompensationFailureStopsQueuedAndFutureRemoteWork() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: true)
        await harness.vault.delayNextRead(account: "provider.githubGist")

        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            deviceName: "Replacement Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: true,
            confirmsPlaintextRisk: true
        )
        let save = Task { @MainActor in
            await harness.sync.handle(.saveConnection(
                replacement,
                SyncSecretChanges(providerSecret: "replacement-secret")
            ))
        }
        for _ in 0..<100 {
            if await harness.vault.delayedReadStarted() { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        assertQueued(await harness.sync.handle(.backupNow))
        await harness.vault.failNext(
            .set,
            account: "provider.githubGist",
            afterMutation: true
        )
        await harness.vault.failNext(
            .set,
            account: "provider.githubGist",
            afterMutation: true
        )
        await harness.vault.resumeDelayedRead()

        let result = await save.value
        assertFailure(result)
        assertDoesNotExpose("replacement-secret", in: result)
        XCTAssertEqual(
            harness.sync.state.lastFailure?.message,
            L10n.string("sync.error.localTransactionCompensation")
        )
        XCTAssertEqual(
            harness.sync.state.connection?.hasStoredProviderSecret,
            false
        )
        XCTAssertNil(harness.sync.state.nextHourlyCheck)
        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [makeGesture(name: "Blocked Change")]
        ))
        harness.sync.noteLocalConfigurationChanged()
        postWakeNotification()
        assertFailure(await harness.sync.handle(.backupNow))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(harness.sync.state.nextHourlyCheck)
        let attempts = await harness.remote.storeAttemptCount()
        XCTAssertEqual(attempts, 0)
    }

    func testOverlappingBackupRequestsCoalesceIntoOneQueuedBackup() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        await harness.remote.setStoreDelay(.milliseconds(80))

        let first = Task { @MainActor in
            await harness.sync.handle(.backupNow)
        }
        while harness.sync.state.activity != .backingUp {
            await Task.yield()
        }
        assertFailure(await harness.sync.handle(.loadHistory(
            BackupHistoryQuery(limit: 20)
        )))
        XCTAssertEqual(harness.sync.state.activity, .backingUp)
        let second = await harness.sync.handle(.backupNow)
        let third = await harness.sync.handle(.backupNow)
        assertQueued(second)
        assertQueued(third)
        assertSuccess(await first.value)

        for _ in 0..<100 {
            if await harness.remote.storeCount() >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let count = await harness.remote.storeCount()
        XCTAssertEqual(count, 2)
        let maximumConcurrent = await harness.remote.maximumConcurrentStores()
        XCTAssertEqual(maximumConcurrent, 1)
    }

    func testRestoreProvenanceDoesNotCauseDuplicateAutomaticBackup() async throws {
        let harness = try makeHarness(debounceInterval: 0.03)
        defer { harness.cleanup() }
        let backedUp = makeGesture(name: "Backed Up")
        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [backedUp]
        ))
        try await connect(harness.sync, automatic: true)
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let sourceID = try XCTUnwrap(latestID)
        let sourceData = try await harness.remote.fetchBackup(sourceID)
        let sourceSnapshotID = try BackupCodec.decodeEnvelope(
            from: sourceData
        ).snapshotID

        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [makeGesture(name: "Local")]
        ))
        assertSuccess(await harness.sync.handle(.preview(sourceID, nil)))
        assertSuccess(await harness.sync.handle(.restore(RestoreRequest(
            backupID: sourceID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: true
        ))))

        for _ in 0..<100 {
            if await harness.remote.storeCount() >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(120))
        let finalCount = await harness.remote.storeCount()
        XCTAssertEqual(finalCount, 2)
        let storedLatestData = await harness.remote.latestData()
        let latestData = try XCTUnwrap(storedLatestData)
        let decoded = try BackupCodec.decode(latestData)
        XCTAssertEqual(
            decoded.payload.restoredFromSnapshotID,
            sourceSnapshotID
        )
        XCTAssertFalse(harness.sync.state.hasPendingBackup)
    }

    func testActivationPerformsOnlyOneOverdueHourlyAudit() async throws {
        let harness = try makeHarness(activates: false)
        defer { harness.cleanup() }
        try await harness.vault.setCredential(
            Data("test-token".utf8),
            for: "provider.githubGist"
        )
        let stored = StoredSyncConfiguration(
            connection: .githubGist(gistID: "test-gist"),
            deviceID: UUID(),
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            currentEncryptionKeyID: nil,
            knownEncryptionKeyIDs: [],
            automaticBackupEnabled: true,
            lastSuccessfulContentHash: nil,
            lastSuccess: nil,
            lastHourlyCheck: Date(timeIntervalSinceNow: -7_200)
        )
        try ConfigurationSyncPersistence(defaults: harness.defaults)
            .saveConfiguration(stored)
        await harness.remote.setStoreFailure(true)

        harness.sync.activate()
        for _ in 0..<100 {
            if await harness.remote.storeAttemptCount() >= 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(80))
        let attempts = await harness.remote.storeAttemptCount()
        XCTAssertEqual(attempts, 1)
    }

    func testHTTPConfirmationIsBoundToTheExactEndpoint() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        var draft = SyncConnectionDraft(
            provider: .webDAV,
            webDAVURL: "http://dav.example/alice/",
            webDAVUsername: "alice",
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsInsecureHTTP: true,
            confirmedInsecureHTTPURL: "http://dav.example/bob/"
        )
        assertFailure(await harness.sync.handle(.saveConnection(
            draft,
            SyncSecretChanges(providerSecret: "dav-password")
        )))
        XCTAssertNil(harness.sync.state.connection)

        draft.confirmedInsecureHTTPURL = draft.webDAVURL
        assertSuccess(await harness.sync.handle(.saveConnection(
            draft,
            SyncSecretChanges(providerSecret: "dav-password")
        )))
    }

    func testAllConfigurationRestoreRequiresExperimentalTrackpadConfirmation() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.defaults.set(
            true,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        harness.defaults.set(
            GestureAmbiguityResolution.chooseBest.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        try await connect(
            harness.sync,
            automatic: false,
            scope: .allConfiguration
        )
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)

        harness.defaults.set(
            false,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        harness.defaults.set(
            GestureAmbiguityResolution.reject.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))
        XCTAssertTrue(
            harness.sync.history.preview?
                .containsExperimentalTrackpadGestures == true
        )
        let unconfirmed = RestoreRequest(
            backupID: backupID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: false
        )
        assertFailure(await harness.sync.handle(.restore(unconfirmed)))
        XCTAssertFalse(harness.defaults.bool(
            forKey: PreferenceKey.directTrackpadEnabled
        ))
        XCTAssertFalse(harness.defaults.bool(
            forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
        ))

        var confirmed = unconfirmed
        confirmed.confirmsExperimentalTrackpadRisk = true
        assertSuccess(await harness.sync.handle(.restore(confirmed)))
        XCTAssertTrue(harness.defaults.bool(
            forKey: PreferenceKey.directTrackpadEnabled
        ))
        XCTAssertTrue(harness.defaults.bool(
            forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
        ))
        XCTAssertEqual(
            harness.defaults.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.chooseBest.rawValue
        )
    }

    func testPreviewListsPrivilegedGestureNamesWithoutScriptBodies() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let shellBody = "printf 'preview-secret-shell-body'"
        let appleScriptBody = "return \"preview-secret-applescript-body\""
        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [
                makeGesture(name: "Safe Gesture"),
                makeGesture(
                    name: "Shell Gesture",
                    action: .shell(shellBody)
                ),
                makeGesture(
                    name: "AppleScript Gesture",
                    action: .appleScript(appleScriptBody)
                ),
            ]
        ))
        try await connect(harness.sync, automatic: false)
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)

        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))
        let preview = try XCTUnwrap(harness.sync.history.preview)
        XCTAssertEqual(
            preview.privilegedGestureNames,
            ["Shell Gesture", "AppleScript Gesture"]
        )
        XCTAssertTrue(preview.containsScripts)
        let publicDescription = String(describing: preview)
        XCTAssertFalse(publicDescription.contains(shellBody))
        XCTAssertFalse(publicDescription.contains(appleScriptBody))
    }

    func testEncryptedSnapshotOnAnotherMacRequiresThenAcceptsPassword() async throws {
        let source = try makeHarness()
        defer { source.cleanup() }
        let encryptedDraft = SyncConnectionDraft(
            provider: .githubGist,
            deviceName: "Source Mac",
            scope: .gesturesOnly,
            encryption: .aes256GCM,
            automaticBackupEnabled: false
        )
        assertSuccess(await source.sync.handle(.saveConnection(
            encryptedDraft,
            SyncSecretChanges(
                providerSecret: "test-token",
                encryptionPassword: "correct horse battery"
            )
        )))
        assertSuccess(await source.sync.handle(.backupNow))
        let latestID = await source.remote.latestID()
        let backupID = try XCTUnwrap(latestID)
        let backupData = try await source.remote.fetchBackup(backupID)
        let keyID = try XCTUnwrap(
            BackupCodec.decodeEnvelope(from: backupData).encryption.keyID
        )

        let destination = try makeHarness(remote: source.remote)
        defer { destination.cleanup() }
        let destinationDraft = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "testgist",
            deviceName: "Destination Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        assertSuccess(await destination.sync.handle(.saveConnection(
            destinationDraft,
            SyncSecretChanges(providerSecret: "test-token")
        )))
        let firstPreview = await destination.sync.handle(.preview(
            backupID,
            nil
        ))
        guard case .requiresDecryption(let requestedID) = firstPreview else {
            return XCTFail("Expected password prompt, got \(firstPreview)")
        }
        XCTAssertEqual(requestedID, backupID)
        assertSuccess(await destination.sync.handle(.preview(
            backupID,
            DecryptionAttempt(
                password: "correct horse battery",
                savesOnThisMac: true
            )
        )))
        let savedKey = try await destination.vault.credential(
            for: "encryption.\(keyID.uuidString.lowercased())"
        )
        XCTAssertNotNil(savedKey)
    }

    func testCorruptStoredDerivedKeyFailsWithoutRequestingPassword() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let key = BackupDerivedKey(
            keyID: UUID(),
            salt: Data(repeating: 7, count: BackupCodec.saltByteCount),
            iterations: BackupCodec.pbkdf2Iterations,
            keyData: Data(repeating: 9, count: BackupDerivedKey.byteCount)
        )
        let backupID = try await storeEncryptedBackup(
            on: harness.remote,
            key: key
        )
        try await connect(harness.sync, automatic: false)
        let corruptKey = BackupDerivedKey(
            keyID: key.keyID,
            salt: key.salt,
            iterations: key.iterations,
            keyData: Data([1])
        )
        try await harness.vault.setCredential(
            try ConfigurationSyncPersistence.encodeDerivedKey(corruptKey),
            for: "encryption.\(key.keyID.uuidString.lowercased())"
        )

        let result = await harness.sync.handle(.preview(backupID, nil))

        assertFailure(result)
        XCTAssertNil(harness.sync.state.pendingDecryptionID)
        XCTAssertNil(harness.sync.history.preview)
    }

    func testKeychainSaveFailureClearsPendingDecryptionState() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let password = "correct horse battery"
        let key = try BackupCodec.deriveKey(password: password)
        let backupID = try await storeEncryptedBackup(
            on: harness.remote,
            key: key
        )
        try await connect(harness.sync, automatic: false)
        let initial = await harness.sync.handle(.preview(backupID, nil))
        guard case .requiresDecryption = initial else {
            return XCTFail("Expected password request, got \(initial)")
        }
        let keyAccount = "encryption.\(key.keyID.uuidString.lowercased())"
        await harness.vault.failNext(.set, account: keyAccount)

        let result = await harness.sync.handle(.preview(
            backupID,
            DecryptionAttempt(password: password, savesOnThisMac: true)
        ))

        assertFailure(result)
        XCTAssertNil(harness.sync.state.pendingDecryptionID)
        let savedKey = try await harness.vault.credential(for: keyAccount)
        XCTAssertNil(savedKey)
        XCTAssertNil(harness.sync.history.preview)
    }

    func testChangingRemoteContainerClearsOldHistoryAndPreview() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        assertSuccess(await harness.sync.handle(.backupNow))
        assertSuccess(await harness.sync.handle(.loadHistory(
            BackupHistoryQuery(limit: 20)
        )))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)
        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))
        XCTAssertFalse(harness.sync.history.items.isEmpty)
        XCTAssertNotNil(harness.sync.history.preview)

        let replacement = SyncConnectionDraft(
            provider: .githubGist,
            gistIDOrURL: "anothergist",
            deviceName: "Test Mac",
            scope: .gesturesOnly,
            encryption: .none,
            automaticBackupEnabled: false,
            confirmsPlaintextRisk: true,
            confirmsExistingGistVisibilityRisk: true
        )
        assertSuccess(await harness.sync.handle(.saveConnection(
            replacement,
            SyncSecretChanges()
        )))
        XCTAssertTrue(harness.sync.history.items.isEmpty)
        XCTAssertNil(harness.sync.history.preview)
        assertFailure(await harness.sync.handle(.restore(RestoreRequest(
            backupID: backupID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: true
        ))))
    }

    func testRestoreFailureStillExposesRollbackAndCompensatesLocalState() async throws {
        var applyAttempts = 0
        let harness = try makeHarness(applyConfiguration: {
            applyAttempts += 1
            if applyAttempts == 1 { throw ExpectedApplyFailure() }
        })
        defer { harness.cleanup() }
        let backedUp = makeGesture(name: "Backed Up")
        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [backedUp]
        ))
        harness.defaults.set(
            true,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        harness.defaults.set(
            GestureAmbiguityResolution.reject.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        try await connect(
            harness.sync,
            automatic: false,
            scope: .allConfiguration
        )
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)

        let local = makeGesture(name: "Local")
        try harness.store.replaceFromBackup(GestureConfigFile(
            version: Constants.configVersion,
            gestures: [local]
        ))
        harness.defaults.set(
            false,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        harness.defaults.set(
            GestureAmbiguityResolution.chooseBest.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))
        assertFailure(await harness.sync.handle(.restore(RestoreRequest(
            backupID: backupID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: true
        ))))

        XCTAssertEqual(applyAttempts, 2)
        XCTAssertEqual(harness.store.gestures, [local])
        XCTAssertFalse(harness.defaults.bool(
            forKey: PreferenceKey.directTrackpadEnabled
        ))
        XCTAssertFalse(harness.defaults.bool(
            forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
        ))
        XCTAssertEqual(
            harness.defaults.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.chooseBest.rawValue
        )
        let rollbackURL = try XCTUnwrap(harness.sync.state.lastRollbackURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackURL.path))
        let rollback = try BackupCodec.decode(Data(contentsOf: rollbackURL))
        XCTAssertEqual(
            rollback.payload.settings?.ambiguityResolution,
            GestureAmbiguityResolution.chooseBest.rawValue
        )
    }

    func testOversizedHistoryItemIsNotDownloaded() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try await connect(harness.sync, automatic: false)
        assertSuccess(await harness.sync.handle(.backupNow))
        await harness.remote.setReportedByteCount(
            BackupRemoteLimits.maximumPayloadByteCount + 1
        )

        assertSuccess(await harness.sync.handle(.loadHistory(
            BackupHistoryQuery(limit: 20)
        )))
        let fetchAttempts = await harness.remote.fetchAttemptCount()
        XCTAssertEqual(fetchAttempts, 0)
        XCTAssertNotNil(harness.sync.history.items.first?.inspectionError)
    }

    func testPreviewDoesNotMutateAndOverwriteCreatesRollbackThenReplacesExactly() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let backedUp = makeGesture(name: "Backed Up")
        try harness.store.replaceFromBackup(
            GestureConfigFile(version: Constants.configVersion, gestures: [backedUp])
        )
        try await connect(harness.sync, automatic: false)
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)

        let local = makeGesture(name: "Local Only")
        try harness.store.replaceFromBackup(
            GestureConfigFile(version: Constants.configVersion, gestures: [local])
        )
        let storedData = try await harness.remote.fetchBackup(backupID)
        let decoded = try BackupCodec.decode(storedData)
        try harness.store.validateBackupGestureFile(decoded.payload.gestures)
        let localSettings = PortableSettingsV1.capture(from: harness.defaults)
        try localSettings.validate()
        _ = try BackupMergePlanner.plan(
            local: try harness.store.makeBackupGestureFile(),
            backup: decoded.payload.gestures,
            localSettings: localSettings.mergeValues,
            backupSettings: [:]
        )
        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))
        XCTAssertEqual(harness.store.gestures, [local])

        let request = RestoreRequest(
            backupID: backupID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: true
        )
        assertSuccess(await harness.sync.handle(.restore(request)))
        XCTAssertEqual(harness.store.gestures, [backedUp])
        let rollbackURL = try XCTUnwrap(harness.sync.state.lastRollbackURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackURL.path))
        XCTAssertTrue(harness.sync.state.hasPendingBackup)
    }

    func testRestoreRejectsLocalChangesMadeAfterPreview() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        try harness.store.replaceFromBackup(
            GestureConfigFile(
                version: Constants.configVersion,
                gestures: [makeGesture(name: "Backed Up")]
            )
        )
        try await connect(harness.sync, automatic: false)
        assertSuccess(await harness.sync.handle(.backupNow))
        let latestID = await harness.remote.latestID()
        let backupID = try XCTUnwrap(latestID)

        try harness.store.replaceFromBackup(
            GestureConfigFile(
                version: Constants.configVersion,
                gestures: [makeGesture(name: "Before Preview")]
            )
        )
        assertSuccess(await harness.sync.handle(.preview(backupID, nil)))

        let afterPreview = makeGesture(name: "After Preview")
        try harness.store.replaceFromBackup(
            GestureConfigFile(
                version: Constants.configVersion,
                gestures: [afterPreview]
            )
        )
        harness.defaults.set(
            45.0,
            forKey: PreferenceKey.minStrokeDistance
        )
        let request = RestoreRequest(
            backupID: backupID,
            mode: .overwrite,
            confirmsScriptRisk: true,
            confirmsExperimentalTrackpadRisk: true
        )

        assertFailure(await harness.sync.handle(.restore(request)))
        XCTAssertEqual(harness.store.gestures, [afterPreview])
        XCTAssertNil(harness.sync.state.lastRollbackURL)
    }

    private func connect(
        _ sync: ConfigurationSync,
        automatic: Bool,
        scope: SyncScope = .gesturesOnly
    ) async throws {
        let draft = SyncConnectionDraft(
            provider: .githubGist,
            deviceName: "Test Mac",
            scope: scope,
            encryption: .none,
            automaticBackupEnabled: automatic,
            confirmsPlaintextRisk: true
        )
        assertSuccess(await sync.handle(.saveConnection(
            draft,
            SyncSecretChanges(providerSecret: "test-token")
        )))
    }

    private func makeHarness(
        debounceInterval: TimeInterval = 60,
        hourlyInterval: TimeInterval = 3_600,
        activates: Bool = true,
        remote providedRemote: RecordingBackupAdapter? = nil,
        adapterFactory providedFactory: SyncAdapterFactory? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        applyConfiguration: @escaping () throws -> Void = {}
    ) throws -> SyncHarness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConfigurationSyncTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let store = ConfigStore(
            configURL: root.appendingPathComponent(Constants.configFileName)
        )
        let suiteName = "ConfigurationSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let remote = providedRemote ?? RecordingBackupAdapter()
        let vault = TestCredentialVault()
        let persistence = TestConfigurationSyncPersistence(
            base: ConfigurationSyncPersistence(defaults: defaults)
        )
        let sync = ConfigurationSync(
            configStore: store,
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            adapterFactory: providedFactory ?? { _, _ in remote },
            debounceInterval: debounceInterval,
            hourlyInterval: hourlyInterval,
            now: now,
            applyConfiguration: applyConfiguration
        )
        if activates { sync.activate() }
        return SyncHarness(
            sync: sync,
            store: store,
            remote: remote,
            vault: vault,
            persistence: persistence,
            defaults: defaults,
            suiteName: suiteName,
            root: root
        )
    }

    private func makeGesture(
        name: String,
        action: GestureAction = .none
    ) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: [
                    CodablePoint(x: 0, y: 0),
                    CodablePoint(x: 1, y: 0),
                ]
            )),
            action: action
        )
    }

    private func postWakeNotification() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func storeEncryptedBackup(
        on remote: RecordingBackupAdapter,
        key: BackupDerivedKey
    ) async throws -> RemoteBackupID {
        let encoded = try BackupCodec.encodeEncrypted(
            payload: BackupPayloadV1(
                gestures: GestureConfigFile(
                    version: Constants.configVersion,
                    gestures: [makeGesture(name: "Encrypted")]
                ),
                settings: nil,
                restoredFromSnapshotID: nil
            ),
            metadata: BackupMetadataV1(
                snapshotID: UUID(),
                createdAt: Date(),
                kind: .manual,
                deviceID: UUID(),
                deviceName: "Source Mac",
                appVersion: "1",
                appBuild: "1",
                scope: .gesturesOnly
            ),
            derivedKey: key
        )
        return try await remote.storeBackup(encoded.data, createdAt: Date())
    }

    private func assertSuccess(
        _ result: SyncResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("Expected success, got \(result)", file: file, line: line)
        }
    }

    private func assertFailure(
        _ result: SyncResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure = result else {
            return XCTFail("Expected failure, got \(result)", file: file, line: line)
        }
    }

    private func assertQueued(
        _ result: SyncResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .queued = result else {
            return XCTFail("Expected queued, got \(result)", file: file, line: line)
        }
    }

    private func assertDoesNotExpose(
        _ secret: String,
        in result: SyncResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let message) = result else { return }
        XCTAssertFalse(message.contains(secret), file: file, line: line)
    }
}

private struct SyncHarness {
    let sync: ConfigurationSync
    let store: ConfigStore
    let remote: RecordingBackupAdapter
    let vault: TestCredentialVault
    let persistence: TestConfigurationSyncPersistence
    let defaults: UserDefaults
    let suiteName: String
    let root: URL

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            XCTFail("Failed to remove test directory: \(error)")
        }
    }
}

private final class TestConfigurationSyncPersistence: ConfigurationSyncPersisting {
    private enum Failure: Equatable {
        case saveAfterMutation
        case removalAfterMutation
    }

    private let base: ConfigurationSyncPersistence
    private var failure: Failure?
    private var usesInMemoryMutations = false
    private var inMemoryConfiguration: StoredSyncConfiguration?

    init(base: ConfigurationSyncPersistence) {
        self.base = base
    }

    func loadConfiguration() throws -> StoredSyncConfiguration? {
        if usesInMemoryMutations { return inMemoryConfiguration }
        return try base.loadConfiguration()
    }

    func saveConfiguration(_ configuration: StoredSyncConfiguration) throws {
        if usesInMemoryMutations {
            inMemoryConfiguration = configuration
        } else {
            try base.saveConfiguration(configuration)
        }
        if failure == .saveAfterMutation {
            failure = nil
            throw ExpectedPersistenceFailure()
        }
    }

    func removeConfiguration() throws {
        if usesInMemoryMutations {
            inMemoryConfiguration = nil
        } else {
            try base.removeConfiguration()
        }
        if failure == .removalAfterMutation {
            failure = nil
            throw ExpectedPersistenceFailure()
        }
    }

    func stableDeviceID() -> UUID {
        base.stableDeviceID()
    }

    func failNextSaveAfterMutation() {
        failure = .saveAfterMutation
    }

    func failNextRemovalAfterMutation() {
        failure = .removalAfterMutation
    }

    func useInMemoryMutations() throws {
        inMemoryConfiguration = try base.loadConfiguration()
        usesInMemoryMutations = true
    }
}

private actor TestCredentialVault: CredentialVault {
    enum Operation: Equatable {
        case read
        case set
        case delete
    }

    private struct Failure {
        let operation: Operation
        let account: String?
        let afterMutation: Bool
    }

    private var credentials: [String: Data] = [:]
    private var failures: [Failure] = []

    private var delayedReadAccount: String?
    private var didStartDelayedRead = false
    private var delayedReadContinuation: CheckedContinuation<Void, Never>?

    func credential(for account: String) async throws -> Data? {
        if consumeFailure(operation: .read, account: account) != nil {
            throw ExpectedCredentialFailure()
        }
        let value = credentials[account]
        if delayedReadAccount == account {
            delayedReadAccount = nil
            didStartDelayedRead = true
            await withCheckedContinuation { continuation in
                delayedReadContinuation = continuation
            }
        }
        return value
    }

    func setCredential(_ credential: Data, for account: String) throws {
        let expectedFailure = consumeFailure(operation: .set, account: account)
        if expectedFailure?.afterMutation == false {
            throw ExpectedCredentialFailure()
        }
        credentials[account] = credential
        if expectedFailure != nil {
            throw ExpectedCredentialFailure()
        }
    }

    func deleteCredential(for account: String) throws {
        let expectedFailure = consumeFailure(
            operation: .delete,
            account: account
        )
        if expectedFailure?.afterMutation == false {
            throw ExpectedCredentialFailure()
        }
        credentials.removeValue(forKey: account)
        if expectedFailure != nil {
            throw ExpectedCredentialFailure()
        }
    }

    func failNext(
        _ operation: Operation,
        account: String? = nil,
        afterMutation: Bool = false
    ) {
        failures.append(Failure(
            operation: operation,
            account: account,
            afterMutation: afterMutation
        ))
    }

    func delayNextRead(account: String) {
        delayedReadAccount = account
        didStartDelayedRead = false
    }

    func delayedReadStarted() -> Bool {
        didStartDelayedRead
    }

    func resumeDelayedRead() {
        let continuation = delayedReadContinuation
        delayedReadContinuation = nil
        continuation?.resume()
    }

    private func consumeFailure(
        operation: Operation,
        account: String
    ) -> Failure? {
        guard let index = failures.firstIndex(where: {
            $0.operation == operation
                && ($0.account == nil || $0.account == account)
        }) else { return nil }
        return failures.remove(at: index)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            date = date.addingTimeInterval(interval)
        }
    }
}

private actor RecordingBackupAdapter: BackupRemoteAdapter {
    nonisolated let providerID = BackupRemoteProviderID.githubGist

    private var documents: [(id: RemoteBackupID, date: Date, data: Data)] = []
    private var failsStore = false
    private var storeDelay: Duration?
    private var storeAttempts = 0
    private var activeStores = 0
    private var maximumActiveStores = 0
    private var reportedByteCount: Int?
    private var fetchAttempts = 0

    func validateConnection() async throws {}

    func storeBackup(
        _ data: Data,
        createdAt: Date
    ) async throws -> RemoteBackupID {
        storeAttempts += 1
        activeStores += 1
        maximumActiveStores = max(maximumActiveStores, activeStores)
        defer { activeStores -= 1 }
        if let storeDelay {
            try await Task.sleep(for: storeDelay)
        }
        if failsStore {
            throw BackupRemoteError.transport("expected test failure")
        }
        let envelope = try BackupCodec.decodeEnvelope(from: data)
        let id = RemoteBackupID(
            providerID: providerID,
            containerID: "test-gist",
            revisionID: envelope.snapshotID.uuidString
        )
        documents.append((id, createdAt, data))
        return id
    }

    func listHistory(
        _ query: BackupHistoryQuery
    ) async throws -> BackupHistoryPage {
        let start = query.cursor.flatMap(Int.init) ?? 0
        let ordered = documents.reversed()
        let page = Array(ordered.dropFirst(start).prefix(query.limit))
        let end = start + page.count
        return BackupHistoryPage(
            backups: page.map {
                BackupSummary(
                    id: $0.id,
                    createdAt: $0.date,
                    byteCount: reportedByteCount ?? $0.data.count
                )
            },
            nextCursor: end < documents.count ? String(end) : nil
        )
    }

    func fetchBackup(_ id: RemoteBackupID) async throws -> Data {
        fetchAttempts += 1
        guard let document = documents.first(where: { $0.id == id }) else {
            throw BackupRemoteError.notFound
        }
        return document.data
    }

    func setStoreFailure(_ value: Bool) {
        failsStore = value
    }

    func setStoreDelay(_ delay: Duration?) {
        storeDelay = delay
    }

    func storeCount() -> Int { documents.count }
    func latestID() -> RemoteBackupID? { documents.last?.id }
    func latestData() -> Data? { documents.last?.data }
    func storeAttemptCount() -> Int { storeAttempts }
    func maximumConcurrentStores() -> Int { maximumActiveStores }
    func setReportedByteCount(_ value: Int?) { reportedByteCount = value }
    func fetchAttemptCount() -> Int { fetchAttempts }
}

private struct ExpectedApplyFailure: Error {}
private struct ExpectedPersistenceFailure: Error {}
private struct ExpectedCredentialFailure: Error {}
