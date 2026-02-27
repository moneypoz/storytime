import CoreData

/// Sets up NSPersistentCloudKitContainer for playback-progress sync.
///
/// Why NSPersistentCloudKitContainer and not raw CloudKit:
///   • Story metadata (segment index, finished flag) is tiny structured data —
///     Core Data's automatic diff-and-sync is ideal for this shape.
///   • Voice WAV blobs go through CloudSharingService as CKAssets (separate path).
///   • Container reuses the same iCloud.com.storytime.app container so no extra
///     provisioning is needed beyond the CloudKit capability already required.
///
/// Conflict policy: NSMergeByPropertyObjectTrumpMergePolicy (last-write-wins).
/// For progress tracking this is always correct — the most recent device wins.
final class PersistenceController {

    // MARK: - Singleton

    static let shared = PersistenceController()

    /// In-memory store for SwiftUI previews and unit tests.
    static let preview: PersistenceController = PersistenceController(inMemory: true)

    // MARK: - Container

    let container: NSPersistentCloudKitContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "StoryTime")

        if inMemory {
            container.persistentStoreDescriptions.first!.url =
                URL(fileURLWithPath: "/dev/null")
        } else {
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("[PersistenceController] No persistent store description found.")
            }

            // Required for NSPersistentCloudKitContainer to track remote changes
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey
            )
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )

            // Sync to the same container used by CloudSharingService
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.storytime.app"
                )
        }

        container.loadPersistentStores { _, error in
            if let error {
                // Surface configuration problems early during development.
                // In production a graceful fallback (local-only store) would be preferable.
                fatalError("[PersistenceController] Store failed to load: \(error)")
            }
        }

        // Merge CloudKit changes pushed from other devices into the view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        // Last-write-wins is correct for progress records
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Progress CRUD

    /// Fetches the saved progress record for a book, or nil if never started.
    ///
    /// Runs synchronously on the view context (main thread). Safe to call from
    /// a SwiftUI view initializer.
    func fetchProgress(for bookID: String) -> PlaybackProgress? {
        let request = PlaybackProgress.fetchRequest()
        request.predicate  = NSPredicate(format: "bookID == %@", bookID)
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

    /// Upserts the progress record for a book and saves immediately.
    ///
    /// NSPersistentCloudKitContainer will pick up the save and sync it
    /// to iCloud in the background on its own schedule.
    func saveProgress(bookID: String, segmentIndex: Int, isFinished: Bool) {
        let ctx     = container.viewContext
        let request = PlaybackProgress.fetchRequest()
        request.predicate  = NSPredicate(format: "bookID == %@", bookID)
        request.fetchLimit = 1

        let record         = (try? ctx.fetch(request))?.first ?? PlaybackProgress(context: ctx)
        record.bookID       = bookID
        record.segmentIndex = Int32(segmentIndex)
        record.isFinished   = isFinished
        record.lastPlayedAt = Date()

        try? ctx.save()
    }

    /// Deletes the progress record so the book starts fresh next time.
    func resetProgress(for bookID: String) {
        let ctx     = container.viewContext
        let request = PlaybackProgress.fetchRequest()
        request.predicate = NSPredicate(format: "bookID == %@", bookID)
        (try? ctx.fetch(request))?.forEach { ctx.delete($0) }
        try? ctx.save()
    }
}
