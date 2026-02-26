import Foundation
import CloudKit
import UIKit

/// Service for managing spouse/family member invitations via iCloud sharing
/// Creates separate shares for Voice Profile (Read-Only) and Book Library (Read/Write)
@MainActor
final class SpouseInviteService: ObservableObject {

    // MARK: - Singleton

    static let shared = SpouseInviteService()

    // MARK: - Published State

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var familyZoneCreated = false
    @Published var activeShares: [ShareType: CKShare] = [:]

    // MARK: - Constants

    private let container = CKContainer(identifier: "iCloud.com.storytime.app")
    private let familyZoneName = "FamilyZone"

    // MARK: - Zone IDs

    private var familyZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: familyZoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - Record Types

    enum RecordType: String {
        case voiceProfile = "VoiceProfile"
        case bookLibrary = "BookLibrary"
        case familyMember = "FamilyMember"
    }

    // MARK: - Share Types

    enum ShareType: String, CaseIterable {
        case voiceProfile = "VoiceProfileShare"
        case bookLibrary = "BookLibraryShare"

        var title: String {
            switch self {
            case .voiceProfile: return "Voice Profile"
            case .bookLibrary: return "Story Library"
            }
        }

        var permission: CKShare.ParticipantPermission {
            switch self {
            case .voiceProfile: return .readOnly
            case .bookLibrary: return .readWrite
            }
        }
    }

    // MARK: - Initialization

    private init() {
        Task {
            await setupFamilyZone()
        }
    }

    // MARK: - Zone Setup

    /// Creates the private Family Zone if it doesn't exist
    func setupFamilyZone() async {
        isLoading = true
        errorMessage = nil

        do {
            let zone = CKRecordZone(zoneID: familyZoneID)
            let database = container.privateCloudDatabase

            // Create zone (idempotent - won't fail if exists)
            _ = try await database.modifyRecordZones(
                saving: [zone],
                deleting: []
            )

            familyZoneCreated = true
            print("Family Zone created/verified: \(familyZoneName)")

        } catch {
            errorMessage = "Failed to create Family Zone: \(error.localizedDescription)"
            print(errorMessage ?? "")
        }

        isLoading = false
    }

    // MARK: - Invite Spouse

    /// Creates shares and presents the native iOS Share Sheet
    /// - Parameter viewController: The presenting view controller
    /// - Returns: The UICloudSharingController for presentation
    func createSpouseInvitation(from viewController: UIViewController) async throws -> UICloudSharingController {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Ensure zone exists
        if !familyZoneCreated {
            await setupFamilyZone()
        }

        // Create the combined family share
        let share = try await createFamilyShare()

        // Configure the sharing controller
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = SpouseInviteCoordinator.shared

        // Store active share reference
        activeShares[.bookLibrary] = share

        return controller
    }

    // MARK: - Create Family Share

    /// Creates a CKShare for the family with appropriate permissions
    private func createFamilyShare() async throws -> CKShare {
        let database = container.privateCloudDatabase

        // Create root record for the share
        let familyRootRecord = CKRecord(
            recordType: RecordType.familyMember.rawValue,
            recordID: CKRecord.ID(recordName: "FamilyRoot", zoneID: familyZoneID)
        )
        familyRootRecord["createdAt"] = Date() as CKRecordValue
        familyRootRecord["ownerName"] = UIDevice.current.name as CKRecordValue

        // Create the share attached to family root
        let share = CKShare(rootRecord: familyRootRecord)
        share[CKShare.SystemFieldKey.title] = "StoryTime Family" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.storytime.family" as CKRecordValue

        // Set default permission for new participants
        share.publicPermission = .none // Private only

        // Save root record and share
        _ = try await database.modifyRecords(
            saving: [familyRootRecord, share],
            deleting: []
        )

        return share
    }

    // MARK: - Create Voice Profile Share (Read-Only)

    /// Creates a separate read-only share for the voice profile
    func createVoiceProfileShare(voiceProfileRecordID: CKRecord.ID) async throws -> CKShare {
        let database = container.privateCloudDatabase

        // Fetch the voice profile record
        let voiceProfileRecord = try await database.record(for: voiceProfileRecordID)

        // Create share with read-only intent
        let share = CKShare(rootRecord: voiceProfileRecord)
        share[CKShare.SystemFieldKey.title] = "Voice Profile (Listen Only)" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.storytime.voiceprofile" as CKRecordValue
        share.publicPermission = .none

        // Save the share
        _ = try await database.modifyRecords(
            saving: [voiceProfileRecord, share],
            deleting: []
        )

        activeShares[.voiceProfile] = share
        return share
    }

    // MARK: - Create Book Library Share (Read/Write)

    /// Creates a read/write share for the book library
    func createBookLibraryShare(libraryRecordID: CKRecord.ID) async throws -> CKShare {
        let database = container.privateCloudDatabase

        // Fetch the library record
        let libraryRecord = try await database.record(for: libraryRecordID)

        // Create share with read/write intent
        let share = CKShare(rootRecord: libraryRecord)
        share[CKShare.SystemFieldKey.title] = "Story Library" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.storytime.library" as CKRecordValue
        share.publicPermission = .none

        // Save the share
        _ = try await database.modifyRecords(
            saving: [libraryRecord, share],
            deleting: []
        )

        activeShares[.bookLibrary] = share
        return share
    }

    // MARK: - Configure Participant Permissions

    /// Sets appropriate permissions when a spouse accepts the invitation
    func configureSpousePermissions(
        for participant: CKShare.Participant,
        shareType: ShareType
    ) async throws {
        guard let share = activeShares[shareType] else {
            throw SpouseInviteError.shareNotFound
        }

        let database = container.privateCloudDatabase

        // Update participant permission based on share type
        participant.permission = shareType.permission
        participant.role = .privateUser

        // Save updated share
        _ = try await database.modifyRecords(
            saving: [share],
            deleting: []
        )

        print("Configured \(shareType.rawValue) with \(shareType.permission) for participant")
    }

    // MARK: - Accept Share (Called when spouse accepts)

    /// Processes an accepted share invitation
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await container.accept(metadata)
        print("Share accepted successfully")
    }

    // MARK: - Fetch Shared Records

    /// Fetches records shared with the current user
    func fetchSharedRecords() async throws -> [CKRecord] {
        let database = container.sharedCloudDatabase

        let query = CKQuery(
            recordType: RecordType.bookLibrary.rawValue,
            predicate: NSPredicate(value: true)
        )

        let (results, _) = try await database.records(matching: query)

        return results.compactMap { try? $0.1.get() }
    }

    // MARK: - Get Family Members

    /// Returns all participants in the family share
    func getFamilyMembers() async throws -> [FamilyParticipant] {
        guard let share = activeShares[.bookLibrary] else {
            return []
        }

        return share.participants.map { participant in
            FamilyParticipant(
                id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                name: participant.userIdentity.nameComponents?.formatted() ?? "Family Member",
                role: participant.role,
                permission: participant.permission,
                acceptanceStatus: participant.acceptanceStatus
            )
        }
    }

    // MARK: - Revoke Access

    /// Removes a participant from all shares
    func revokeAccess(for participantRecordID: CKRecord.ID) async throws {
        let database = container.privateCloudDatabase

        for (_, share) in activeShares {
            if let participant = share.participants.first(where: {
                $0.userIdentity.userRecordID == participantRecordID
            }) {
                share.removeParticipant(participant)

                _ = try await database.modifyRecords(
                    saving: [share],
                    deleting: []
                )
            }
        }

        print("Access revoked for participant: \(participantRecordID.recordName)")
    }

    // MARK: - Check Sharing Status

    /// Checks if the current user is the owner or participant of a share
    func checkSharingStatus() async -> SharingStatus {
        do {
            let database = container.privateCloudDatabase

            // Try to fetch shares from private database (owner)
            let zones = try await database.allRecordZones()
            let hasFamilyZone = zones.contains { $0.zoneID.zoneName == familyZoneName }

            if hasFamilyZone {
                return .owner
            }

            // Check shared database (participant)
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            if !sharedZones.isEmpty {
                return .participant
            }

            return .none

        } catch {
            print("Error checking sharing status: \(error)")
            return .none
        }
    }
}

// MARK: - Supporting Types

struct FamilyParticipant: Identifiable {
    let id: String
    let name: String
    let role: CKShare.ParticipantRole
    let permission: CKShare.ParticipantPermission
    let acceptanceStatus: CKShare.ParticipantAcceptanceStatus

    var isOwner: Bool {
        role == .owner
    }

    var statusDescription: String {
        switch acceptanceStatus {
        case .accepted: return "Active"
        case .pending: return "Pending"
        case .removed: return "Removed"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    var permissionDescription: String {
        switch permission {
        case .readOnly: return "Can listen"
        case .readWrite: return "Can edit"
        case .none: return "No access"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}

enum SharingStatus {
    case owner
    case participant
    case none
}

enum SpouseInviteError: LocalizedError {
    case shareNotFound
    case zoneNotCreated
    case permissionDenied
    case networkError

    var errorDescription: String? {
        switch self {
        case .shareNotFound:
            return "Family share not found. Please try again."
        case .zoneNotCreated:
            return "Failed to create family zone."
        case .permissionDenied:
            return "Permission denied. Please check iCloud settings."
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}

// MARK: - Spouse Invite Coordinator (Delegate)

class SpouseInviteCoordinator: NSObject, UICloudSharingControllerDelegate {

    static let shared = SpouseInviteCoordinator()

    // Called when share is saved successfully
    func cloudSharingController(
        _ csc: UICloudSharingController,
        failedToSaveShareWithError error: Error
    ) {
        print("Failed to save share: \(error.localizedDescription)")

        Task { @MainActor in
            SpouseInviteService.shared.errorMessage = error.localizedDescription
        }
    }

    // Provide share title
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "StoryTime Family Library"
    }

    // Optional: Provide thumbnail
    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        // Could return app icon data here
        return nil
    }

    // Called when participant is added
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        print("Share saved successfully")

        // Configure permissions for new participants
        if let share = csc.share {
            Task {
                for participant in share.participants where participant.role != .owner {
                    // Voice profile gets read-only
                    try? await SpouseInviteService.shared.configureSpousePermissions(
                        for: participant,
                        shareType: .voiceProfile
                    )
                }
            }
        }
    }

    // Called when sharing controller is dismissed
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        print("Sharing stopped")
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// SwiftUI wrapper for presenting the spouse invite share sheet
struct SpouseInviteSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onComplete: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented,
              uiViewController.presentedViewController == nil else {
            return
        }

        Task { @MainActor in
            do {
                let controller = try await SpouseInviteService.shared.createSpouseInvitation(
                    from: uiViewController
                )

                controller.modalPresentationStyle = .formSheet

                uiViewController.present(controller, animated: true) {
                    // Dismissed
                    isPresented = false
                    onComplete?(true)
                }
            } catch {
                print("Failed to create invitation: \(error)")
                isPresented = false
                onComplete?(false)
            }
        }
    }
}

// MARK: - View Extension for Easy Access

extension View {
    func spouseInviteSheet(
        isPresented: Binding<Bool>,
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        self.background(
            SpouseInviteSheet(isPresented: isPresented, onComplete: onComplete)
        )
    }
}
