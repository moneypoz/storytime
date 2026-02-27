import CloudKit
import Foundation
import VoiceboxCore

/// Handles CloudKit CRUD for voice profile sharing.
///
/// Zone strategy:
///   SpouseInviteService → "FamilyZone"   (general family access, read/write library)
///   CloudSharingService → "FamilyStories" (voice file transfer via CKAsset, read-only)
///
/// Flow (sender):
///   setupZone() → createVoiceProfileShare(wav:name:owner:) → UICloudSharingController
///
/// Flow (receiver, after tapping iMessage link):
///   AppDelegate.userDidAcceptCloudKitShare → FamilySyncManager.acceptShare
///   → CloudSharingService.fetchSharedVoiceProfile → save WAV to disk
@MainActor
public final class CloudSharingService: ObservableObject {

    public static let shared = CloudSharingService()

    // MARK: - Published

    @Published public private(set) var isReady = false
    @Published public private(set) var lastError: String?

    // MARK: - CloudKit

    let container = CKContainer(identifier: "iCloud.com.storytime.app")
    private(set) var zone: CKRecordZone?

    private static let zoneName = "FamilyStories"

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB:  CKDatabase { container.sharedCloudDatabase  }

    // MARK: - Record field keys

    static let recordType  = "VoiceProfile"
    static let voiceFile   = "voiceFile"    // CKAsset — the WAV
    static let voiceName   = "voiceName"    // String — display name
    static let ownerName   = "ownerName"    // String — device/user name

    private init() {}

    // MARK: - Zone setup

    /// Creates the "FamilyStories" custom zone if it does not already exist.
    /// Must complete before any save or share operation.
    public func setupZone() async throws {
        let zoneID = CKRecordZone.ID(
            zoneName: Self.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let (saveResults, _) = try await privateDB.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
        zone = (try? saveResults[zoneID]?.get()) ?? CKRecordZone(zoneID: zoneID)
        isReady = true
    }

    // MARK: - Create share (sender path)

    /// Writes the WAV bytes to CloudKit as a CKAsset, creates a private CKShare,
    /// and returns both objects ready for UICloudSharingController.
    ///
    /// - Important: Call `setupZone()` before this method.
    public func createVoiceProfileShare(
        wavData: Data,
        voiceName: String,
        ownerName: String
    ) async throws -> (record: CKRecord, share: CKShare) {
        guard let zone else { throw SharingError.zoneNotSetup }

        // CKAsset requires a file URL — write to a unique temp path
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckasset_\(UUID().uuidString).wav")
        try wavData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Build record
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
        )
        record[Self.voiceFile]  = CKAsset(fileURL: tmp)
        record[Self.voiceName]  = voiceName  as CKRecordValue
        record[Self.ownerName]  = ownerName  as CKRecordValue

        // Attach a private-only share
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "\(ownerName)'s Voice" as CKRecordValue
        share.publicPermission = .none   // Privacy guard: invited participants only

        // Save record + share in one round-trip
        let (saveResults, _) = try await privateDB.modifyRecords(
            saving: [record, share],
            deleting: []
        )

        guard
            let savedRecord = try? saveResults[record.recordID]?.get(),
            let savedShare  = try? saveResults[share.recordID]?.get() as? CKShare
        else { throw SharingError.shareCreationFailed }

        return (savedRecord, savedShare)
    }

    // MARK: - Fetch shared record (receiver path)

    /// Accepts the CloudKit share and downloads the voice WAV from the shared DB.
    ///
    /// Returns the raw WAV bytes plus display metadata.
    public func fetchSharedVoiceProfile(
        metadata: CKShare.Metadata
    ) async throws -> (wavData: Data, voiceName: String, ownerName: String) {
        // Accept into the recipient's iCloud account
        try await container.accept(metadata)

        // Fetch the root record from the shared database
        let record = try await sharedDB.record(for: metadata.rootRecordID)

        guard
            let asset   = record[Self.voiceFile] as? CKAsset,
            let fileURL = asset.fileURL
        else { throw SharingError.missingAsset }

        let data      = try Data(contentsOf: fileURL)
        let voiceName = record[Self.voiceName] as? String ?? "Shared Voice"
        let ownerName = record[Self.ownerName] as? String ?? "Family Member"

        return (data, voiceName, ownerName)
    }
}

// MARK: - Errors

public enum SharingError: LocalizedError {
    case zoneNotSetup
    case shareCreationFailed
    case missingAsset

    public var errorDescription: String? {
        switch self {
        case .zoneNotSetup:        return "CloudKit zone not initialized. Call setupZone() first."
        case .shareCreationFailed: return "Failed to create the CloudKit share."
        case .missingAsset:        return "Voice file missing from shared record."
        }
    }
}
