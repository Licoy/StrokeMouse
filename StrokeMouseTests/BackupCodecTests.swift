import XCTest
@testable import StrokeMouse

final class BackupCodecTests: XCTestCase {
    func testFnBackupRoundTripsAndRejectsMislabeledOrFutureConfigVersions() throws {
        var payload = makePayload(scope: .gesturesOnly)
        payload.gestures.gestures[0].secondaryAction = .shortcut(
            chord: ShortcutChord(modifiers: [.function], keyCode: nil)
        )
        payload.gestures.version = 3
        let metadata = makeMetadata(scope: .gesturesOnly)
        let encoded = try BackupCodec.encodePlaintext(payload: payload, metadata: metadata)
        XCTAssertEqual(try BackupCodec.decode(encoded.data).payload, payload)
        for version in [2, 99] {
            payload.gestures.version = version
            XCTAssertThrowsError(try BackupCodec.encodePlaintext(payload: payload, metadata: metadata)) { error in
                XCTAssertEqual(error as? BackupCodecError, .unsupportedGestureConfigVersion(version))
            }
        }
    }

    func testPlaintextRoundTripKeepsListableMetadata() throws {
        let payload = makePayload(scope: .gesturesOnly)
        let metadata = makeMetadata(scope: .gesturesOnly)

        let encoded = try BackupCodec.encodePlaintext(
            payload: payload,
            metadata: metadata
        )
        let listed = try BackupCodec.decodeEnvelope(from: encoded.data)
        let decoded = try BackupCodec.decode(encoded.data)

        XCTAssertEqual(listed.metadata, metadata)
        XCTAssertEqual(listed.encryption, .plaintext)
        XCTAssertEqual(listed.payloadDigest.count, 32)
        XCTAssertEqual(decoded.payload, payload)
    }

    func testPasswordEncryptionRoundTripsWithReturnedDerivedKey() throws {
        let payload = makePayload(scope: .allConfiguration)
        let metadata = makeMetadata(scope: .allConfiguration)
        let keyID = UUID(uuidString: "20D89653-E26B-49AB-A194-9DBEACC9ED16")!

        let encoded = try BackupCodec.encodeEncrypted(
            payload: payload,
            metadata: metadata,
            password: "correct horse battery staple",
            keyID: keyID
        )
        let key = try XCTUnwrap(encoded.derivedKey)
        let listed = try BackupCodec.decodeEnvelope(from: encoded.data)
        let decoded = try BackupCodec.decode(encoded.data, derivedKey: key)

        XCTAssertEqual(listed.metadata, metadata)
        XCTAssertEqual(listed.encryption.kind, .aes256GCM)
        XCTAssertEqual(listed.encryption.keyID, keyID)
        XCTAssertEqual(listed.encryption.salt?.count, 16)
        XCTAssertEqual(listed.encryption.iterations, 600_000)
        XCTAssertEqual(key.keyData.count, 32)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertFalse(
            String(data: listed.payloadRepresentation, encoding: .utf8)?
                .contains("Encrypted gesture") == true
        )
    }

    func testPasswordAndStableProfileDeriveTheSameKey() throws {
        let keyID = UUID(uuidString: "B1B5B3E7-6373-44D3-B12E-17039D627393")!
        let salt = Data((0..<16).map(UInt8.init))

        let first = try BackupCodec.deriveKey(
            password: "same password",
            salt: salt,
            keyID: keyID,
            iterations: 600_000
        )
        let second = try BackupCodec.deriveKey(
            password: "same password",
            salt: salt,
            keyID: keyID,
            iterations: 600_000
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.keyData.count, 32)
    }

    func testPasswordLengthBoundariesAndWhitespaceArePreserved() throws {
        let salt = Data((0..<16).map(UInt8.init))
        let keyID = UUID(uuidString: "35646D51-D20D-4F26-86B0-99BF38147CE9")!

        XCTAssertThrowsError(try BackupCodec.deriveKey(
            password: String(repeating: "a", count: 11),
            salt: salt,
            keyID: keyID
        )) { error in
            XCTAssertEqual(error as? BackupCodecError, .passwordTooShort)
        }
        XCTAssertNoThrow(try BackupCodec.deriveKey(
            password: String(repeating: "a", count: 12),
            salt: salt,
            keyID: keyID
        ))
        XCTAssertNoThrow(try BackupCodec.deriveKey(
            password: String(repeating: "a", count: 256),
            salt: salt,
            keyID: keyID
        ))
        XCTAssertThrowsError(try BackupCodec.deriveKey(
            password: String(repeating: "a", count: 257),
            salt: salt,
            keyID: keyID
        )) { error in
            XCTAssertEqual(error as? BackupCodecError, .passwordTooLong)
        }

        let spaced = try BackupCodec.deriveKey(
            password: "  password  ",
            salt: salt,
            keyID: keyID
        )
        let unspaced = try BackupCodec.deriveKey(
            password: "passwordxxxx",
            salt: salt,
            keyID: keyID
        )
        XCTAssertNotEqual(spaced.keyData, unspaced.keyData)
    }

    func testWrongPasswordAndTamperedMetadataFailExplicitly() throws {
        let encoded = try BackupCodec.encodeEncrypted(
            payload: makePayload(scope: .gesturesOnly),
            metadata: makeMetadata(scope: .gesturesOnly),
            password: "right password"
        )

        XCTAssertThrowsError(
            try BackupCodec.decode(encoded.data, password: "wrong password")
        ) { error in
            XCTAssertEqual(error as? BackupCodecError, .decryptionFailed)
        }

        var tampered = encoded.envelope
        tampered.deviceName = "A different Mac"
        XCTAssertThrowsError(
            try BackupCodec.decode(
                try encodeEnvelopeForTamperTest(tampered),
                derivedKey: XCTUnwrap(encoded.derivedKey)
            )
        ) { error in
            XCTAssertEqual(error as? BackupCodecError, .decryptionFailed)
        }
    }

    func testTamperedCiphertextOrAuthenticationTagFailsExplicitly() throws {
        let encoded = try BackupCodec.encodeEncrypted(
            payload: makePayload(scope: .gesturesOnly),
            metadata: makeMetadata(scope: .gesturesOnly),
            password: "right password"
        )
        let representation = encoded.envelope.payloadRepresentation
        let nonceByteCount = 12
        let authenticationTagByteCount = 16
        XCTAssertGreaterThan(
            representation.count,
            nonceByteCount + authenticationTagByteCount
        )
        let mutationIndices = [
            (
                "ciphertext",
                representation.index(
                    representation.startIndex,
                    offsetBy: nonceByteCount
                )
            ),
            (
                "authentication tag",
                representation.index(before: representation.endIndex)
            ),
        ]
        let key = try XCTUnwrap(encoded.derivedKey)

        for (component, index) in mutationIndices {
            var tampered = encoded.envelope
            tampered.payloadRepresentation[index] ^= 0x01

            XCTAssertThrowsError(
                try BackupCodec.decode(
                    encodeEnvelopeForTamperTest(tampered),
                    derivedKey: key
                ),
                "Tampering with the \(component) must fail authentication"
            ) { error in
                XCTAssertEqual(error as? BackupCodecError, .decryptionFailed)
            }
        }
    }

    func testFutureEnvelopeAndCorruptJSONAreRejectedExplicitly() throws {
        let encoded = try BackupCodec.encodePlaintext(
            payload: makePayload(scope: .gesturesOnly),
            metadata: makeMetadata(scope: .gesturesOnly)
        )
        var future = encoded.envelope
        future.formatVersion = BackupEnvelopeV1.currentFormatVersion + 1

        XCTAssertThrowsError(
            try BackupCodec.decodeEnvelope(
                from: encodeEnvelopeForTamperTest(future)
            )
        ) { error in
            XCTAssertEqual(
                error as? BackupCodecError,
                .unsupportedFormatVersion(future.formatVersion)
            )
        }
        XCTAssertThrowsError(
            try BackupCodec.decodeEnvelope(from: Data("{broken".utf8))
        ) { error in
            XCTAssertEqual(error as? BackupCodecError, .invalidEnvelope)
        }
    }

    func testScopeMismatchAndOversizedDocumentAreRejected() throws {
        let invalid = BackupPayloadV1(
            gestures: .empty,
            settings: PortableSettingsV1.capture(from: ephemeralDefaults()),
            restoredFromSnapshotID: nil
        )
        XCTAssertThrowsError(
            try BackupCodec.encodePlaintext(
                payload: invalid,
                metadata: makeMetadata(scope: .gesturesOnly)
            )
        ) { error in
            XCTAssertEqual(error as? BackupCodecError, .scopePayloadMismatch)
        }

        let oversized = Data(
            repeating: 0,
            count: BackupCodec.maximumEncodedSize + 1
        )
        XCTAssertThrowsError(try BackupCodec.decodeEnvelope(from: oversized)) {
            guard case .sizeLimitExceeded = $0 as? BackupCodecError else {
                return XCTFail("Expected size limit error, got \($0)")
            }
        }
    }

    func testInMemoryCredentialVaultMatchesSetGetDeleteContract() async throws {
        let vault = InMemoryCredentialVault()
        let credential = Data("secret".utf8)

        let initiallyStored = try await vault.credential(for: "provider")
        XCTAssertNil(initiallyStored)
        try await vault.setCredential(credential, for: "provider")
        let stored = try await vault.credential(for: "provider")
        XCTAssertEqual(stored, credential)
        try await vault.deleteCredential(for: "provider")
        let deleted = try await vault.credential(for: "provider")
        XCTAssertNil(deleted)
    }

    private func makePayload(scope: SyncScope) -> BackupPayloadV1 {
        let profile = GestureProfile(
            name: scope == .allConfiguration
                ? "Encrypted gesture"
                : "Plain gesture",
            pattern: .freePath(PathTemplates.up),
            action: .openURL("https://example.com")
        )
        return BackupPayloadV1(
            gestures: GestureConfigFile(
                version: Constants.configVersion,
                gestures: [profile]
            ),
            settings: scope == .allConfiguration
                ? PortableSettingsV1.capture(from: ephemeralDefaults())
                : nil,
            restoredFromSnapshotID: nil
        )
    }

    private func makeMetadata(scope: SyncScope) -> BackupMetadataV1 {
        BackupMetadataV1(
            snapshotID: UUID(uuidString: "D9AE0098-4BE8-4B4E-8F5B-2904FF5B80CB")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .manual,
            deviceID: UUID(uuidString: "3898CD75-73B7-4CD3-9DB5-BF7C492A9726")!,
            deviceName: "Test Mac",
            appVersion: "1.2.3",
            appBuild: "123",
            scope: scope
        )
    }

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BackupCodecTests-\(UUID().uuidString)")!
    }

    private func encodeEnvelopeForTamperTest(
        _ envelope: BackupEnvelopeV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }
}
