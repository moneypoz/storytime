import Foundation
import VoiceboxCore

// MARK: - StoryPrefetchService

/// Eagerly synthesizes the first segments of a story the moment its card is tapped,
/// so audio is ready for instant playback when the user hits Play.
///
/// ## How it works
///
/// `VoiceboxService.synthesize()` already writes every result to a disk cache keyed
/// by SHA-256(profilePath + text).  TTSPlayer calls the same `synthesize()` method
/// and hits that disk cache automatically — zero gap, zero cross-service coupling.
///
/// Calling `prepare(book:)` before `PlayerView` appears means segment 0 and 1 are
/// already on disk by the time TTSPlayer calls `playVoiceboxSegment(at: 0)`.
///
/// ## Why not AVAudioEngine buffering
///
/// `AVAudioPlayer.prepareToPlay()` primes the hardware codec in ~50 ms once WAV
/// bytes exist.  The only meaningful latency is synthesis time (~500 ms–2 s
/// depending on text length and device).  Pre-synthesizing eliminates that latency
/// at the right moment; an additional buffer layer adds complexity with no benefit.
///
/// ## Why not a warmUp() call
///
/// The Qwen3 model is loaded into memory during app launch via
/// `VoiceboxService.load(modelPath:)`.  Once `isLoaded == true` the engine is
/// already warm.  A separate warmUp step would be redundant.
@MainActor
final class StoryPrefetchService {

    static let shared = StoryPrefetchService()

    // MARK: - Private

    /// One active prefetch task per book ID.  Cancelling before starting a new
    /// one prevents a slow prefetch for the previous card from wasting CPU.
    private var activeTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Public

    /// Synthesize the first `segmentCount` segments of `book` in the background.
    ///
    /// - Safe to call from the tap handler before `PlayerView` is presented.
    /// - Silently no-ops if the engine isn't loaded or no voice profile is set.
    /// - Cancels any in-flight task for the same book before starting a new one.
    func prepare(book: Book, segmentCount: Int = 2) {
        guard VoiceboxService.shared.isLoaded,
              VoiceboxService.shared.hasVoiceProfile,
              let segments = book.script?.segments,
              !segments.isEmpty
        else { return }

        activeTasks[book.id]?.cancel()

        let targets = Array(segments.prefix(segmentCount))

        activeTasks[book.id] = Task.detached(priority: .userInitiated) {
            for segment in targets {
                guard !Task.isCancelled else { return }
                // Disk-cache hit on any subsequent call costs ~1 ms.
                _ = try? await VoiceboxService.shared.synthesize(segment.text)
            }
        }
    }

    /// Cancel any active prefetch for the given book (e.g. user backs out of
    /// the player before synthesis finishes).
    func cancel(bookID: String) {
        activeTasks[bookID]?.cancel()
        activeTasks.removeValue(forKey: bookID)
    }
}
