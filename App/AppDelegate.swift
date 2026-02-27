import CloudKit
import UIKit

/// UIApplicationDelegate added via @UIApplicationDelegateAdaptor.
///
/// Its sole responsibility is intercepting CloudKit share-acceptance callbacks
/// and routing them to FamilySyncManager, which handles the download and
/// local file write.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Called by iOS when the user taps a CloudKit share link in iMessage,
    /// AirDrop, Mail, etc.  The system hands us the share metadata; we
    /// forward it to FamilySyncManager which fetches the CKAsset (voice WAV),
    /// writes it to disk, and registers it with VoiceboxService.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            do {
                try await FamilySyncManager.shared.acceptShare(
                    metadata: cloudKitShareMetadata
                )
            } catch {
                print("[AppDelegate] Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
