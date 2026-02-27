import CoreData

/// Core Data entity that stores how far a user has listened through a story.
///
/// Synced to iCloud via NSPersistentCloudKitContainer so progress is
/// shared across the parent's devices (iPhone → iPad) automatically.
@objc(PlaybackProgress)
public class PlaybackProgress: NSManagedObject {

    /// Matches `Book.id` — a stable slug like "lion-and-mouse".
    @NSManaged public var bookID: String

    /// Index of the last segment that started playing.
    @NSManaged public var segmentIndex: Int32

    /// True once the final segment finishes — triggers a fresh start on next open.
    @NSManaged public var isFinished: Bool

    /// Updated on every save; used to resolve CloudKit merge conflicts
    /// (last-write-wins is appropriate for progress tracking).
    @NSManaged public var lastPlayedAt: Date?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlaybackProgress> {
        NSFetchRequest<PlaybackProgress>(entityName: "PlaybackProgress")
    }
}
