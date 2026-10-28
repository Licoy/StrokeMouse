import CommonCrypto
import CryptoKit
import Foundation
import Security

enum BackupCodec {
    static let maximumEncodedSize = 10 * 1024 * 1024
    static let saltByteCount = 16
    static let pbkdf2Iterations = 600_000

    static func deriveKey(
        password: String,
        keyID: UUID = UUID()
    ) throws -> BackupDerivedKey {
        try deriveKey(
            password: password,
            salt: BackupCrypto.randomBytes(count: saltByteCount),
            keyID: keyID,
            iterations: pbkdf2Iterations
        )
    }

    static func deriveKey(
        password: String,
        salt: Data,
        keyID: UUID,
        iterations: Int = pbkdf2Iterations
    ) throws -> BackupDerivedKey {
        guard password.count >= 12 else {
            throw BackupCodecError.passwordTooShort
        }
        guard password.utf8.count <= 256 else {
            throw BackupCodecError.passwordTooLong
        }
        guard salt.count == saltByteCount,
              iterations == pbkdf2Iterations
        else {
            throw BackupCodecError.invalidEncryptionDescriptor
        }
        return BackupDerivedKey(
            keyID: keyID,
            salt: salt,
            iterations: iterations,
            keyData: try BackupCrypto.deriveKey(
                password: password,
                salt: salt,
                iterations: iterations
            )
        )
    }

    static func encodePlaintext(
        payload: BackupPayloadV1,
        metadata: BackupMetadataV1
    ) throws -> BackupEncodingResult {
        let payloadData = try encodeAndValidate(payload, scope: metadata.scope)
        let envelope = BackupEnvelopeV1(
            metadata: metadata,
            encryption: .plaintext,
            payloadDigest: digest(payloadData),
            payloadRepresentation: payloadData
        )
        return BackupEncodingResult(
            data: try encodeEnvelope(envelope),
            envelope: envelope,
            derivedKey: nil
        )
    }

    static func encodeEncrypted(
        payload: BackupPayloadV1,
        metadata: BackupMetadataV1,
        password: String,
        keyID: UUID = UUID()
    ) throws -> BackupEncodingResult {
        try encodeEncrypted(
            payload: payload,
            metadata: metadata,
            derivedKey: deriveKey(password: password, keyID: keyID)
        )
    }

    static func encodeEncrypted(
        payload: BackupPayloadV1,
        metadata: BackupMetadataV1,
        derivedKey: BackupDerivedKey
    ) throws -> BackupEncodingResult {
        try validate(derivedKey)
        let payloadData = try encodeAndValidate(payload, scope: metadata.scope)
        let digest = digest(payloadData)
        var envelope = BackupEnvelopeV1(
            metadata: metadata,
            encryption: derivedKey.encryptionDescriptor,
            payloadDigest: digest,
            payloadRepresentation: Data()
        )
        envelope.payloadRepresentation = try BackupCrypto.seal(
            payloadData,
            keyData: derivedKey.keyData,
            authenticating: try authenticatedMetadata(for: envelope)
        )
        return BackupEncodingResult(
            data: try encodeEnvelope(envelope),
            envelope: envelope,
            derivedKey: derivedKey
        )
    }

    /// Decodes metadata and the stored representation without decrypting it.
    static func decodeEnvelope(from data: Data) throws -> BackupEnvelopeV1 {
        try enforceSize(data)
        let envelope: BackupEnvelopeV1
        do {
            envelope = try decoder().decode(BackupEnvelopeV1.self, from: data)
        } catch {
            throw BackupCodecError.invalidEnvelope
        }
        try validate(envelope)
        return envelope
    }

    /// Decodes plaintext backups and rejects encrypted input explicitly.
    static func decode(_ data: Data) throws -> BackupDecodedBackup {
        let envelope = try decodeEnvelope(from: data)
        guard envelope.encryption.kind == .none else {
            throw BackupCodecError.decryptionKeyRequired
        }
        return try decodePayload(in: envelope, keyData: nil)
    }

    static func decode(
        _ data: Data,
        password: String
    ) throws -> BackupDecodedBackup {
        let envelope = try decodeEnvelope(from: data)
        guard envelope.encryption.kind == .aes256GCM else {
            return try decodePayload(in: envelope, keyData: nil)
        }
        guard let keyID = envelope.encryption.keyID,
              let salt = envelope.encryption.salt,
              let iterations = envelope.encryption.iterations
        else { throw BackupCodecError.invalidEncryptionDescriptor }
        let key = try deriveKey(
            password: password,
            salt: salt,
            keyID: keyID,
            iterations: iterations
        )
        return try decodePayload(in: envelope, keyData: key.keyData)
    }

    static func decode(
        _ data: Data,
        derivedKey: BackupDerivedKey
    ) throws -> BackupDecodedBackup {
        let envelope = try decodeEnvelope(from: data)
        guard envelope.encryption.kind == .aes256GCM else {
            return try decodePayload(in: envelope, keyData: nil)
        }
        try validate(derivedKey)
        guard envelope.encryption == derivedKey.encryptionDescriptor else {
            throw BackupCodecError.encryptionKeyMismatch
        }
        return try decodePayload(in: envelope, keyData: derivedKey.keyData)
    }

    private static func decodePayload(
        in envelope: BackupEnvelopeV1,
        keyData: Data?
    ) throws -> BackupDecodedBackup {
        let payloadData: Data
        switch envelope.encryption.kind {
        case .none:
            payloadData = envelope.payloadRepresentation
        case .aes256GCM:
            guard let keyData else {
                throw BackupCodecError.decryptionKeyRequired
            }
            do {
                payloadData = try BackupCrypto.open(
                    envelope.payloadRepresentation,
                    keyData: keyData,
                    authenticating: try authenticatedMetadata(for: envelope)
                )
            } catch let error as BackupCodecError {
                throw error
            } catch {
                throw BackupCodecError.decryptionFailed
            }
        }
        try enforceSize(payloadData)
        guard digest(payloadData) == envelope.payloadDigest else {
            throw BackupCodecError.payloadDigestMismatch
        }
        let payload: BackupPayloadV1
        do {
            payload = try decoder().decode(BackupPayloadV1.self, from: payloadData)
        } catch {
            throw BackupCodecError.invalidPayload
        }
        try validate(payload, scope: envelope.scope)
        return BackupDecodedBackup(envelope: envelope, payload: payload)
    }

    private static func encodeAndValidate(
        _ payload: BackupPayloadV1,
        scope: SyncScope
    ) throws -> Data {
        try validate(payload, scope: scope)
        let data: Data
        do { data = try encoder().encode(payload) }
        catch { throw BackupCodecError.invalidPayload }
        try enforceSize(data)
        return data
    }

    private static func validate(
        _ payload: BackupPayloadV1,
        scope: SyncScope
    ) throws {
        guard payload.gestures.hasSupportedVersion else {
            throw BackupCodecError.unsupportedGestureConfigVersion(
                payload.gestures.version
            )
        }
        switch (scope, payload.settings) {
        case (.gesturesOnly, nil):
            break
        case (.allConfiguration, .some(let settings)):
            do { try settings.validate() }
            catch { throw BackupCodecError.invalidPortableSettings }
        default:
            throw BackupCodecError.scopePayloadMismatch
        }
    }

    private static func validate(_ envelope: BackupEnvelopeV1) throws {
        guard envelope.formatVersion == BackupEnvelopeV1.currentFormatVersion else {
            throw BackupCodecError.unsupportedFormatVersion(envelope.formatVersion)
        }
        guard !envelope.deviceName.isEmpty,
              !envelope.appVersion.isEmpty,
              !envelope.appBuild.isEmpty,
              envelope.payloadDigest.count == SHA256.byteCount,
              !envelope.payloadRepresentation.isEmpty
        else { throw BackupCodecError.invalidEnvelope }
        try enforceSize(envelope.payloadRepresentation)
        switch envelope.encryption.kind {
        case .none:
            guard envelope.encryption.keyID == nil,
                  envelope.encryption.salt == nil,
                  envelope.encryption.iterations == nil
            else { throw BackupCodecError.invalidEncryptionDescriptor }
        case .aes256GCM:
            guard envelope.encryption.keyID != nil,
                  envelope.encryption.salt?.count == saltByteCount,
                  envelope.encryption.iterations == pbkdf2Iterations
            else { throw BackupCodecError.invalidEncryptionDescriptor }
        }
    }

    private static func validate(_ key: BackupDerivedKey) throws {
        guard key.keyData.count == BackupDerivedKey.byteCount else {
            throw BackupCodecError.invalidDerivedKeyLength
        }
        guard key.salt.count == saltByteCount,
              key.iterations == pbkdf2Iterations
        else { throw BackupCodecError.invalidEncryptionDescriptor }
    }

    private static func encodeEnvelope(_ envelope: BackupEnvelopeV1) throws -> Data {
        let data: Data
        do { data = try encoder().encode(envelope) }
        catch { throw BackupCodecError.invalidEnvelope }
        try enforceSize(data)
        return data
    }

    private static func enforceSize(_ data: Data) throws {
        guard data.count <= maximumEncodedSize else {
            throw BackupCodecError.sizeLimitExceeded(
                actual: data.count,
                maximum: maximumEncodedSize
            )
        }
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func authenticatedMetadata(
        for envelope: BackupEnvelopeV1
    ) throws -> Data {
        try encoder().encode(AuthenticatedBackupMetadataV1(envelope: envelope))
    }
}

private struct AuthenticatedBackupMetadataV1: Encodable {
    let formatVersion: Int
    let snapshotID: UUID
    let createdAt: Date
    let kind: BackupKind
    let deviceID: UUID
    let deviceName: String
    let appVersion: String
    let appBuild: String
    let scope: SyncScope
    let encryption: BackupEncryptionDescriptorV1
    let payloadDigest: Data

    init(envelope: BackupEnvelopeV1) {
        formatVersion = envelope.formatVersion
        snapshotID = envelope.snapshotID
        createdAt = envelope.createdAt
        kind = envelope.kind
        deviceID = envelope.deviceID
        deviceName = envelope.deviceName
        appVersion = envelope.appVersion
        appBuild = envelope.appBuild
        scope = envelope.scope
        encryption = envelope.encryption
        payloadDigest = envelope.payloadDigest
    }
}

private enum BackupCrypto {
    static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int
    ) throws -> Data {
        let passwordData = Data(password.utf8)
        var output = [UInt8](repeating: 0, count: BackupDerivedKey.byteCount)
        let status: Int32 = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &output,
                    output.count
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupCodecError.keyDerivationFailed(status)
        }
        return Data(output)
    }

    static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BackupCodecError.randomGenerationFailed(status)
        }
        return data
    }

    static func seal(
        _ plaintext: Data,
        keyData: Data,
        authenticating metadata: Data
    ) throws -> Data {
        do {
            let box = try AES.GCM.seal(
                plaintext,
                using: SymmetricKey(data: keyData),
                authenticating: metadata
            )
            guard let combined = box.combined else {
                throw BackupCodecError.encryptionFailed
            }
            return combined
        } catch let error as BackupCodecError {
            throw error
        } catch {
            throw BackupCodecError.encryptionFailed
        }
    }

    static func open(
        _ combined: Data,
        keyData: Data,
        authenticating metadata: Data
    ) throws -> Data {
        do {
            return try AES.GCM.open(
                AES.GCM.SealedBox(combined: combined),
                using: SymmetricKey(data: keyData),
                authenticating: metadata
            )
        } catch {
            throw BackupCodecError.decryptionFailed
        }
    }
}

enum BackupCodecError: Error, Equatable, Sendable {
    case sizeLimitExceeded(actual: Int, maximum: Int)
    case unsupportedFormatVersion(Int)
    case unsupportedGestureConfigVersion(Int)
    case invalidEnvelope
    case invalidPayload
    case invalidPortableSettings
    case scopePayloadMismatch
    case invalidEncryptionDescriptor
    case passwordTooShort
    case passwordTooLong
    case invalidDerivedKeyLength
    case encryptionKeyMismatch
    case decryptionKeyRequired
    case payloadDigestMismatch
    case keyDerivationFailed(Int32)
    case randomGenerationFailed(OSStatus)
    case encryptionFailed
    case decryptionFailed
}
