import Foundation
import CryptoKit

/// Local voice tokenization using ExecuTorch
/// Privacy-first: Raw audio NEVER leaves the device
/// Tokens are encrypted with AES-256 before any sync
@MainActor
final class VoiceTokenizer: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var tokenizationProgress: Double = 0.0
    @Published private(set) var voiceProfile: VoiceProfile?

    // MARK: - Private Properties

    private var executorchModule: ExecuTorchModule?
    private let encryptionKey: SymmetricKey

    // MARK: - Initialization

    init() {
        // Generate device-bound encryption key from Keychain or create new
        self.encryptionKey = Self.loadOrCreateEncryptionKey()
        loadModel()
    }

    // MARK: - Model Loading

    private func loadModel() {
        Task {
            do {
                // Load the Sarah Expressive 1.7B tokenizer model
                executorchModule = try await ExecuTorchModule.load(
                    modelPath: "sarah_expressive_tokenizer_1_7b"
                )
            } catch {
                print("Failed to load ExecuTorch model: \(error)")
            }
        }
    }

    // MARK: - Tokenization

    /// Tokenizes audio locally and returns encrypted voice profile
    /// Raw audio is immediately discarded after tokenization
    func tokenize(audioURL: URL) async throws -> VoiceProfile {
        isProcessing = true
        tokenizationProgress = 0.0

        defer {
            isProcessing = false
            // CRITICAL: Delete raw audio immediately after processing
            try? FileManager.default.removeItem(at: audioURL)
        }

        guard let module = executorchModule else {
            throw VoiceTokenizerError.modelNotLoaded
        }

        // Read audio data
        let audioData = try Data(contentsOf: audioURL)
        tokenizationProgress = 0.2

        // Extract voice embeddings locally using ExecuTorch
        let embeddings = try await module.extractVoiceEmbeddings(from: audioData)
        tokenizationProgress = 0.6

        // Generate voice tokens (prosody, pitch, timbre characteristics)
        let tokens = try await module.generateTokens(from: embeddings)
        tokenizationProgress = 0.8

        // Encrypt tokens with AES-256
        let encryptedTokens = try encryptTokens(tokens)
        tokenizationProgress = 1.0

        let profile = VoiceProfile(
            id: UUID(),
            encryptedTokens: encryptedTokens,
            createdAt: Date(),
            householdID: nil
        )

        self.voiceProfile = profile
        return profile
    }

    // MARK: - Encryption (AES-256)

    private func encryptTokens(_ tokens: [Float]) throws -> Data {
        let tokenData = tokens.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        let sealedBox = try AES.GCM.seal(tokenData, using: encryptionKey)

        guard let combined = sealedBox.combined else {
            throw VoiceTokenizerError.encryptionFailed
        }

        return combined
    }

    func decryptTokens(_ encryptedData: Data) throws -> [Float] {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

        return decryptedData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    // MARK: - Key Management

    private static func loadOrCreateEncryptionKey() -> SymmetricKey {
        let keychainKey = "com.storytime.voiceEncryptionKey"

        // Try to load existing key from Keychain
        if let existingKeyData = KeychainHelper.load(key: keychainKey) {
            return SymmetricKey(data: existingKeyData)
        }

        // Generate new AES-256 key
        let newKey = SymmetricKey(size: .bits256)

        // Store in Keychain
        newKey.withUnsafeBytes { buffer in
            let keyData = Data(buffer)
            KeychainHelper.save(key: keychainKey, data: keyData)
        }

        return newKey
    }
}

// MARK: - Supporting Types

struct VoiceProfile: Codable, Identifiable {
    let id: UUID
    let encryptedTokens: Data
    let createdAt: Date
    var householdID: String?
}

enum VoiceTokenizerError: Error, LocalizedError {
    case modelNotLoaded
    case tokenizationFailed
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Voice model not loaded"
        case .tokenizationFailed:
            return "Failed to tokenize voice"
        case .encryptionFailed:
            return "Failed to encrypt voice profile"
        }
    }
}

// MARK: - ExecuTorch Module Wrapper

/// Wrapper for ExecuTorch runtime
/// In production, this interfaces with the actual ExecuTorch framework
class ExecuTorchModule {
    private let modelPath: String

    private init(modelPath: String) {
        self.modelPath = modelPath
    }

    static func load(modelPath: String) async throws -> ExecuTorchModule {
        // TODO: Load actual .pte model file from bundle
        // let modelURL = Bundle.main.url(forResource: modelPath, withExtension: "pte")
        return ExecuTorchModule(modelPath: modelPath)
    }

    func extractVoiceEmbeddings(from audioData: Data) async throws -> [Float] {
        // ExecuTorch inference for voice embedding extraction
        // This runs the encoder portion of Sarah Expressive 1.7B

        // Placeholder: Returns mock embeddings
        // In production: Run actual ExecuTorch inference
        return Array(repeating: 0.0, count: 512)
    }

    func generateTokens(from embeddings: [Float]) async throws -> [Float] {
        // Generate voice characteristic tokens from embeddings
        // Captures: prosody, pitch contour, timbre, speaking rate

        // Placeholder: Returns mock tokens
        // In production: Run actual ExecuTorch inference
        return Array(repeating: 0.0, count: 256)
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        return result as? Data
    }
}
