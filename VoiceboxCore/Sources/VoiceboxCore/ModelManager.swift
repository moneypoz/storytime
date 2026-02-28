// VoiceboxCore/Sources/VoiceboxCore/ModelManager.swift
//
// Optimisation in this version
// ─────────────────────────────
//  3. Mood-matched profiles — voiceProfilePath(forMood:) returns a
//     mood-specific WAV if one exists, falling back to the default profile.
//     The onboarding currently saves one clip; future onboarding versions
//     can save "mood_excited.wav" / "mood_sleepy.wav" / "mood_normal.wav"
//     from the corresponding ExpressiveScript sections.

import Foundation

@MainActor
public final class ModelManager: ObservableObject {

    // MARK: - Published

    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadError: String?

    // MARK: - Paths

    public let modelCacheDirectory: String
    public private(set) var modelDirectory: String

    private static let modelDirKey = "VoiceboxModelDirectory"

    // MARK: - Init

    public init() {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]

        let cacheDir = docs
            .appendingPathComponent("voicebox_model_cache", isDirectory: true)
            .path

        self.modelCacheDirectory = cacheDir
        self.modelDirectory = UserDefaults.standard.string(forKey: Self.modelDirKey) ?? cacheDir
    }

    // MARK: - Readiness check

    public var isModelReady: Bool {
        let weights = URL(fileURLWithPath: modelDirectory)
            .appendingPathComponent("model.safetensors")
        return FileManager.default.fileExists(atPath: weights.path)
    }

    // MARK: - Download

    /// Download the model weights from `url` and report real byte-level progress.
    ///
    /// - Returns: an `AsyncThrowingStream` that yields `Double` values in `0...1`
    ///   as bytes arrive, then finishes.  The caller drives its progress UI by
    ///   iterating the stream with `for try await p in manager.downloadModel(from:)`.
    ///
    /// - Note: Uses a foreground `URLSession` by default.  To survive app suspension
    ///   on a slow connection, swap `.default` for `.background(withIdentifier:)` and
    ///   implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    ///   in your AppDelegate — that wiring lives in the app target, not this package.
    public func downloadModel(from url: URL) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await MainActor.run {
                    self.isDownloading = true
                    self.downloadError = nil
                    self.downloadProgress = 0.0
                }

                do {
                    let resolvedDir = try await fetchWeights(
                        from: url,
                        cacheDir: self.modelCacheDirectory
                    ) { progress in
                        Task { @MainActor in self.downloadProgress = progress }
                        continuation.yield(progress)
                    }

                    await MainActor.run {
                        self.modelDirectory = resolvedDir
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        UserDefaults.standard.set(resolvedDir, forKey: Self.modelDirKey)
                    }
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadError = error.localizedDescription
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Voice profile paths

    /// Default profile path — used when no mood-specific profile exists.
    public func voiceProfilePath(for parentID: String = "default") -> String {
        profilesDirectory.appendingPathComponent("\(parentID).wav").path
    }

    /// Mood-matched profile path.
    ///
    /// Returns `mood_<mood>.wav` if that file exists (recorded in a future
    /// mood-specific onboarding flow), otherwise falls back to the default
    /// profile so the app works with the current single-recording onboarding.
    ///
    /// `mood` should be one of: `"normal"`, `"excited"`, `"sleepy"`.
    public func voiceProfilePath(forMood mood: String) -> String {
        let moodPath = profilesDirectory
            .appendingPathComponent("mood_\(mood).wav")
            .path

        if FileManager.default.fileExists(atPath: moodPath) {
            return moodPath
        }
        return voiceProfilePath()   // default fallback
    }

    /// Removes all cached model weights (voice profiles are kept).
    public func clearModelCache() {
        let hubDir = URL(fileURLWithPath: modelCacheDirectory)
            .appendingPathComponent("hub", isDirectory: true)
        try? FileManager.default.removeItem(at: hubDir)
        UserDefaults.standard.removeObject(forKey: Self.modelDirKey)
        modelDirectory = modelCacheDirectory
    }

    // MARK: - Private

    private var profilesDirectory: URL {
        let dir = URL(fileURLWithPath: modelCacheDirectory)
            .appendingPathComponent("voice_profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Download internals

    /// Performs the actual URLSession download, moves the result to
    /// `<cacheDir>/model.safetensors`, and returns `cacheDir`.
    ///
    /// `onProgress` is called on the URLSession delegate queue — callers must
    /// hop to the main actor themselves (the public method above does this).
    private func fetchWeights(
        from url: URL,
        cacheDir: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> String {
        let destDir = URL(fileURLWithPath: cacheDir)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent("model.safetensors")

        let delegate = WeightsDownloadDelegate(onProgress: onProgress)
        let session  = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Wire the completion handler before the task starts so it can
                // never fire before the closure is assigned.
                delegate.onCompletion = { result in
                    switch result {
                    case .success(let tempURL):
                        // The temp file must be moved synchronously here — the
                        // system deletes it as soon as didFinishDownloadingTo returns.
                        do {
                            try? FileManager.default.removeItem(at: destURL)
                            try FileManager.default.moveItem(at: tempURL, to: destURL)
                            continuation.resume(returning: cacheDir)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

// MARK: - WeightsDownloadDelegate

/// URLSession delegate that bridges byte-level download events to Swift closures.
/// Kept private to the package — callers interact only through `ModelManager`.
private final class WeightsDownloadDelegate: NSObject, URLSessionDownloadDelegate {

    let onProgress:    (Double) -> Void
    var onCompletion:  ((Result<URL, Error>) -> Void)?

    /// Guards against both `didFinishDownloadingTo` and `didCompleteWithError`
    /// attempting to resume the same continuation.
    private var didSettle = false

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !didSettle else { return }
        didSettle = true
        onCompletion?(.success(location))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // This fires for both success (error == nil) and failure.
        // Only act on genuine errors; success is already handled above.
        guard let error, !didSettle else { return }
        didSettle = true
        onCompletion?(.failure(error))
    }
}
