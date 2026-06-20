import Foundation
import CryptoKit

/// Encrypts and decrypts local data files using AES-256-GCM.
///
/// The symmetric key is generated once and stored as a permission-restricted
/// file (readable only by the current user) alongside the app's data. This
/// avoids Keychain permission prompts that plague ad-hoc signed apps.
/// If the key file is deleted, data becomes unrecoverable — appropriate for
/// a privacy-first health app where "delete everything" is an acceptable
/// failure mode.
enum DataEncryptor {

    // MARK: - Public API

    /// Encrypt arbitrary data. Returns the sealed-box representation
    /// (nonce + ciphertext + tag) as a single `Data` blob.
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try retrieveOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    /// Decrypt data previously produced by `encrypt(_:)`.
    static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try retrieveOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    /// Convenience: encrypt a `Codable` value to `Data`.
    static func encrypt<T: Encodable>(_ value: T, encoder: JSONEncoder = .moonly) throws -> Data {
        let json = try encoder.encode(value)
        return try encrypt(json)
    }

    /// Convenience: decrypt `Data` back into a `Codable` value.
    static func decrypt<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder = .moonly) throws -> T {
        let json = try decrypt(data)
        return try decoder.decode(T.self, from: json)
    }

    // MARK: - Key Management (file-based, chmod 600)

    private static var keyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/.encryption-key", isDirectory: false)
    }

    private static func retrieveOrCreateKey() throws -> SymmetricKey {
        let fm = FileManager.default
        let url = keyURL

        if fm.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }

        // Ensure parent directory exists.
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Write with owner-only permissions (chmod 600).
        try keyData.write(to: url, options: .atomic)
        try fm.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )

        return newKey
    }

    // MARK: - Migration

    /// Reads a file, trying decryption first; if that fails, tries reading as
    /// plaintext JSON (pre-encryption migration). Returns nil if the file
    /// doesn't exist or is completely unreadable.
    static func readMigrating(from url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }

        // Already encrypted: AES-GCM combined format starts with a 12-byte nonce,
        // not a `{` or `[` character.
        if let decrypted = try? decrypt(raw) {
            return decrypted
        }

        // Plaintext JSON from before encryption was added.
        if raw.first == 0x7B || raw.first == 0x5B { // '{' or '['
            return raw
        }

        return nil
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case sealFailed

        var errorDescription: String? {
            switch self {
            case .sealFailed:
                return "AES-GCM seal produced no combined data."
            }
        }
    }
}
