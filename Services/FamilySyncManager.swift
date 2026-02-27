import CloudKit
import Foundation
import VoiceboxCore

/// Coordinates between the CloudKit downloader and the local Voicebox file system.
///
/// Responsibilities:
///   • Accept a share link → download WAV → write to voice_profiles/ → register with VoiceboxService
///   • Persist the list of received profiles across launches (UserDefaults + file-existence guard)
///   • Expose `activateProfile(_:)` so the UI can switch the active voice on demand
@MainActor
public final class FamilySyncManager: ObservableObject {

    public static let shared = FamilySyncManager()

    // MARK: - Published

    @Published public private(set) var syncedProfiles: [SharedVoiceProfile] = []
    @Published public private(set) var activeProfileID: String?
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastError: String?

    /// Set when a new shared voice finishes downloading — triggers VoiceArrivalSheet at root.
    /// Cleared by the sheet's onActivate / onDismiss callbacks.
    @Published public var pendingArrival: SharedVoiceProfile?

    // MARK: - Persistence

    private static let defaultsKey = "syncedVoiceProfiles"

    private init() {
        loadPersistedProfiles()
    }

    // MARK: - Share acceptance

    /// Entry point called from AppDelegate when the user taps an iMessage share link.
    ///
    /// Pipeline:
    ///   CloudSharingService.fetchSharedVoiceProfile
    ///   → saveProfileLocally
    ///   → append to syncedProfiles + persist
    public func acceptShare(metadata: CKShare.Metadata) async throws {
        isSyncing  = true
        lastError  = nil
        defer { isSyncing = false }

        let (wavData, voiceName, ownerName) = try await CloudSharingService.shared
            .fetchSharedVoiceProfile(metadata: metadata)

        let filePath = try saveProfileLocally(
            wavData:   wavData,
            voiceName: voiceName,
            ownerName: ownerName
        )

        let profile = SharedVoiceProfile(
            id:         UUID().uuidString,
            voiceName:  voiceName,
            ownerName:  ownerName,
            filePath:   filePath,
            receivedAt: Date()
        )

        syncedProfiles.append(profile)
        persistProfiles()
        pendingArrival = profile
    }

    // MARK: - Local file management

    /// Saves WAV bytes to `voicebox_model_cache/voice_profiles/shared_<safeName>.wav`
    /// and returns the absolute path.
    ///
    /// The directory is the same one `ModelManager` uses so the Rust bridge can
    /// locate the file via `voiceProfilePath(for:)`.
    public func saveProfileLocally(
        wavData:   Data,
        voiceName: String,
        ownerName: String
    ) throws -> String {
        let safe = voiceName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        let path = ModelManager().voiceProfilePath(for: "shared_\(safe)")
        let url  = URL(fileURLWithPath: path)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try wavData.write(to: url, options: .atomic)
        return path
    }

    /// The voice name to show in the card badge when a shared family voice is active.
    /// Returns nil when the user's own recorded voice is selected (no badge needed).
    public var activeVoiceName: String? {
        guard let id = activeProfileID else { return nil }
        return syncedProfiles.first(where: { $0.id == id })?.voiceName
    }

    /// Registers a synced profile as the active voice in VoiceboxService.
    /// The TTSPlayer's `useVoicebox` gate reads `VoiceboxService.shared.hasVoiceProfile`,
    /// so calling this is all that's needed to switch voices.
    public func activateProfile(_ profile: SharedVoiceProfile) {
        VoiceboxService.shared.setVoiceProfile(path: profile.filePath)
        activeProfileID = profile.id
    }

    // MARK: - Persistence

    private func loadPersistedProfiles() {
        guard
            let data     = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let profiles = try? JSONDecoder().decode([SharedVoiceProfile].self, from: data)
        else { return }

        // Drop entries whose WAV files have been deleted from disk
        syncedProfiles = profiles.filter {
            FileManager.default.fileExists(atPath: $0.filePath)
        }
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(syncedProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - SharedVoiceProfile

public struct SharedVoiceProfile: Identifiable, Codable, Sendable {
    public let id:         String
    public let voiceName:  String
    public let ownerName:  String
    public let filePath:   String
    public let receivedAt: Date
}
