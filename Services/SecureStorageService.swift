import CryptoKit
import Security
import Foundation

// MARK: - Keychain Account Constants

/// Namespaced account keys under the `com.storytime.voiceprofile` service.
/// Each component of the ECIES payload is stored as a discrete Keychain item
/// so the encryption scheme is transparent and auditable.
private enum Account {
    static let service       = "com.storytime.voiceprofile"
    static let nonce         = "voice_nonce"          // 96-bit AES-GCM initialisation vector
    static let ciphertext    = "voice_ciphertext"     // AES-GCM ciphertext + 128-bit auth tag
    static let ephemeralKey  = "voice_ephemeral_key"  // Ephemeral P-256 public key (ECDH)
    static let seKeyToken    = "se_key_token"         // Secure Enclave key dataRepresentation
}

// MARK: - Secure Storage Service

/// Hardware-backed voice profile storage using ECIES over a Secure Enclave P-256 key.
///
/// ## Encryption Scheme (save)
/// 1. Load (or generate) a persistent P-256 key pair **inside the Secure Enclave**.
/// 2. Generate a fresh ephemeral P-256 key pair in application memory.
/// 3. **ECDH**: ephemeral private × SE public key → 256-bit shared secret.
/// 4. **HKDF-SHA256**: shared secret → 256-bit AES symmetric key.
/// 5. **AES-256-GCM seal**: random 96-bit nonce, plaintext → ciphertext + 128-bit auth tag.
/// 6. **Keychain persist**: nonce, ciphertext, ephemeral public key stored separately with
///    `.accessibleAfterFirstUnlock`; SE key token stored under the same attribute.
///
/// ## Decryption Scheme (load)
/// Steps 1 and 3–5 are reversed; ECDH runs inside the SE so the raw private key
/// bytes **never enter application memory** at any point.
///
/// ## Right to Erasure (deleteProfile)
/// Removing the SE key token from the Keychain orphans the corresponding SE key,
/// rendering all stored ciphertext cryptographically unrecoverable — even if an
/// attacker retains the nonce and ciphertext bytes.
///
/// - Important: Requires a physical device with Secure Enclave (A7 chip or later).
///   `SecureEnclave.P256.KeyAgreement.PrivateKey()` throws on the Simulator.
@MainActor
final class SecureStorageService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var hasVoiceProfile = false

    // MARK: - Init

    init() {
        hasVoiceProfile = profileExists()
    }

    // MARK: - Save

    /// Encrypts `data` with AES-256-GCM and persists the nonce (IV), ciphertext,
    /// and ephemeral public key to the System Keychain.
    ///
    /// A new ephemeral key pair is generated for every call, so each saved profile
    /// has unique key material — forward secrecy at the record level.
    func saveVoiceProfile(_ data: Data) throws {
        let seKey = try loadOrCreateSEKey()

        // Step 1 — Ephemeral P-256 key pair (lives only for this call)
        let ephemeral = P256.KeyAgreement.PrivateKey()

        // Step 2 — Convert SE public key to the CryptoKit type that the in-memory
        // ephemeral private key's sharedSecretFromKeyAgreement(with:) accepts.
        // The raw representation is the uncompressed P-256 point (65 bytes, 0x04 prefix).
        let sePublicKey = try P256.KeyAgreement.PublicKey(
            rawRepresentation: seKey.publicKey.rawRepresentation
        )

        // Step 3 — ECDH: ephemeral private × SE public key → shared secret
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: sePublicKey)

        // Step 4 — HKDF-SHA256: derive a 256-bit AES symmetric key
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "StoryTime-v1".data(using: .utf8)!,
            sharedInfo: "VoiceProfile-AES256GCM".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Step 5 — AES-256-GCM seal (CryptoKit generates a cryptographically random nonce)
        let sealed = try AES.GCM.seal(data, using: symmetricKey)

        // Step 6 — Persist each component as a discrete Keychain item
        // Nonce = the AES-GCM initialisation vector (12 bytes / 96 bits)
        let nonceData = Data(sealed.nonce)

        // Ciphertext = encrypted bytes + 16-byte GCM authentication tag concatenated
        let ciphertextAndTag = sealed.ciphertext + sealed.tag

        // Ephemeral public key stored so decryption can reproduce the shared secret
        let ephemeralPublicKeyData = ephemeral.publicKey.rawRepresentation

        try keychainSave(nonceData,            account: Account.nonce)
        try keychainSave(ciphertextAndTag,     account: Account.ciphertext)
        try keychainSave(ephemeralPublicKeyData, account: Account.ephemeralKey)

        hasVoiceProfile = true
    }

    // MARK: - Load

    /// Decrypts and returns the voice profile bytes from the Keychain.
    ///
    /// The ECDH step runs **inside the Secure Enclave** — the SE private key
    /// never touches application memory.
    func loadVoiceProfile() throws -> Data {
        let seKey = try loadOrCreateSEKey()

        let nonceData           = try keychainLoad(account: Account.nonce)
        let ciphertextAndTag    = try keychainLoad(account: Account.ciphertext)
        let ephemeralPublicKeyData = try keychainLoad(account: Account.ephemeralKey)

        // Reconstruct the ephemeral public key from its stored raw representation
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(
            rawRepresentation: ephemeralPublicKeyData
        )

        // ECDH (SE side): SE private key × ephemeral public key → same shared secret
        let sharedSecret = try seKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "StoryTime-v1".data(using: .utf8)!,
            sharedInfo: "VoiceProfile-AES256GCM".data(using: .utf8)!,
            outputByteCount: 32
        )

        // Split stored blob: ciphertext | auth tag (last 16 bytes)
        guard ciphertextAndTag.count > 16 else {
            throw SecureStorageError.malformedPayload
        }
        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag        = ciphertextAndTag.suffix(16)

        let nonce     = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Delete (Right to be Forgotten)

    /// Removes all voice profile data from the Keychain and deletes the SE key token.
    ///
    /// **GDPR Article 17 / CCPA compliance**: Once the SE key token is deleted, the
    /// Secure Enclave key that performed the ECDH can no longer be reconstructed.
    /// Even if an attacker retains the ciphertext and nonce from another source, the
    /// data is permanently unrecoverable — the encrypted bytes are mathematically
    /// locked to a key that no longer has a reachable reference.
    func deleteProfile() throws {
        try keychainDelete(account: Account.nonce)
        try keychainDelete(account: Account.ciphertext)
        try keychainDelete(account: Account.ephemeralKey)
        try keychainDelete(account: Account.seKeyToken)

        hasVoiceProfile = false
    }

    // MARK: - Profile Existence

    private func profileExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Account.service,
            kSecAttrAccount as String: Account.nonce
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Secure Enclave Key Lifecycle

    private func loadOrCreateSEKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        if let tokenData = try? keychainLoad(account: Account.seKeyToken) {
            // Reconstruct the key reference from the persisted token.
            // The private key itself never left the SE — this token is opaque
            // platform data that identifies the key within the SE's secure storage.
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: tokenData
            )
        }

        // First launch: generate a new key pair inside the Secure Enclave
        let newKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
        try keychainSave(newKey.dataRepresentation, account: Account.seKeyToken)
        return newKey
    }

    // MARK: - Keychain Primitives

    private func keychainSave(_ data: Data, account: String) throws {
        // Delete any pre-existing item under this account before writing
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Account.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Account.service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data,
            // Accessible after the device has been unlocked at least once since boot.
            // Supports background voice-engine access while blocking cold-boot attacks.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainWriteFailed(status)
        }
    }

    private func keychainLoad(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Account.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureStorageError.keychainReadFailed(status)
        }
        return data
    }

    private func keychainDelete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Account.service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is acceptable — the item may have already been removed
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainDeleteFailed(status)
        }
    }
}

// MARK: - Errors

enum SecureStorageError: LocalizedError {
    case malformedPayload
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .malformedPayload:
            return "The stored voice profile payload is corrupt or incomplete."
        case .keychainWriteFailed(let status):
            return "Keychain write failed (OSStatus \(status))."
        case .keychainReadFailed(let status):
            return "Keychain read failed (OSStatus \(status))."
        case .keychainDeleteFailed(let status):
            return "Keychain delete failed (OSStatus \(status))."
        }
    }
}
