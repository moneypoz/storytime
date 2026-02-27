import AVFoundation
import SwiftUI
import VoiceboxCore

// MARK: - RecordingViewModel

/// Drives the three-act voice capture flow.
///
/// Pipeline per launch:
///   beginCountdown → startRecording (12 s) → onRecordingFinished
///   → [repeat × 3 acts] → processProfiles (sequential) → runValidation → .done
///
/// Option B profile layout:
///   Act .warmth      → mood_normal.wav   (used as default)
///   Act .excitement  → mood_excited.wav
///   Act .mystery     → mood_sleepy.wav
///
/// PlayerView already calls ModelManager.voiceProfilePath(forMood:) per segment,
/// so all three files are consumed immediately with no further wiring required.
@MainActor
final class RecordingViewModel: NSObject, ObservableObject {

    // MARK: - Act

    enum Act: Int, CaseIterable, Identifiable {
        case warmth      // mood_normal.wav
        case excitement  // mood_excited.wav
        case mystery     // mood_sleepy.wav

        var id: Int { rawValue }

        var moodToken: String {
            switch self {
            case .warmth:      return "normal"
            case .excitement:  return "excited"
            case .mystery:     return "sleepy"
            }
        }

        var displayName: String {
            switch self {
            case .warmth:      return "Warmth"
            case .excitement:  return "Excitement"
            case .mystery:     return "Mystery"
            }
        }

        var instruction: String {
            switch self {
            case .warmth:      return "Your natural, warm storytelling voice"
            case .excitement:  return "Energy and wonder — bring the adventure!"
            case .mystery:     return "Soft and hushed, like a secret"
            }
        }

        /// The text the user reads aloud during this act.
        /// ~10 s at an easy bedtime-story pace with 2 s breathing room.
        var prompt: String {
            switch self {
            case .warmth:
                return "The little bear walked along the quiet path. The trees whispered to each other in the breeze, and the soft sunlight filtered through the leaves, painting golden patterns on the ground below."
            case .excitement:
                return "Wow! Guess what? Tonight we're going on the most amazing adventure ever! Are you ready? Pack your bags — we're heading to the land where stars dance and dragons sing lullabies!"
            case .mystery:
                return "Now... close your eyes. The stars are twinkling just for you. Listen... do you hear that? Somewhere, far away, a little moon bunny is getting ready to dream. And so are you..."
            }
        }

        var accentColor: Color {
            switch self {
            case .warmth:      return Color(hex: "4ADE80")
            case .excitement:  return Color(hex: "FF6B35")
            case .mystery:     return Color(hex: "7DD3FC")
            }
        }

        var icon: String {
            switch self {
            case .warmth:      return "heart.fill"
            case .excitement:  return "star.fill"
            case .mystery:     return "moon.stars.fill"
            }
        }

        var next: Act? { Act(rawValue: rawValue + 1) }
    }

    // MARK: - Phase

    enum Phase: Equatable {
        case ready
        case countdown(Int)                             // 3 → 2 → 1
        case recording(Act)
        case between(next: Act)                         // 2-second pause between acts
        case processing(completed: Int, total: Int)
        case validation                                 // playback preview
        case done
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.ready, .ready), (.validation, .validation), (.done, .done):
                return true
            case let (.countdown(a), .countdown(b)):
                return a == b
            case let (.recording(a), .recording(b)):
                return a == b
            case let (.between(a), .between(b)):
                return a == b
            case let (.processing(a1, a2), .processing(b1, b2)):
                return a1 == b1 && a2 == b2
            case let (.failed(a), .failed(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Published

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var actProgress: Double = 0.0
    /// True once synthesis completes and the preview player has started.
    @Published private(set) var isValidationReady = false
    /// True while the preview audio is actively playing (drives waveform animation).
    @Published private(set) var isPlayingValidation = false

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var meteringTask: Task<Void, Never>?
    private var actAudioURLs: [Act: URL] = [:]
    private var currentAct: Act = .warmth
    private var actStartTime: Date = .now
    /// Cached validation WAV so the user can replay without re-synthesizing.
    private var validationWAV: Data?
    private var validationPlayer: AVAudioPlayer?

    private let actDuration: TimeInterval = 12.0
    private let manager = ModelManager()

    // MARK: - Public control

    func start() {
        Task { await beginCountdown(for: .warmth) }
    }

    func restart() {
        meteringTask?.cancel()
        meteringTask = nil
        recorder?.stop()
        recorder = nil
        validationPlayer?.stop()
        validationPlayer = nil
        validationWAV = nil
        audioLevel = 0
        actProgress = 0
        isValidationReady = false
        isPlayingValidation = false
        actAudioURLs.removeAll()
        phase = .ready
    }

    // MARK: - Countdown

    private func beginCountdown(for act: Act) async {
        for count in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(count)
            try? await Task.sleep(for: .seconds(1))
        }
        startRecording(act: act)
    }

    // MARK: - Recording

    private func startRecording(act: Act) {
        currentAct = act
        configureAudioSession()

        let url = tempURL(for: act)
        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           24_000,       // Qwen3-TTS native rate
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let newRecorder = try? AVAudioRecorder(url: url, settings: settings) else {
            phase = .failed("Could not start recording. Check microphone permissions.")
            return
        }

        newRecorder.isMeteringEnabled = true
        newRecorder.delegate = self
        newRecorder.prepareToRecord()
        newRecorder.record(forDuration: actDuration)

        recorder     = newRecorder
        actAudioURLs[act] = url
        actStartTime = .now
        actProgress  = 0
        phase        = .recording(act)

        startMeteringTask()
    }

    /// Async loop (~30 fps) that reads AVAudioRecorder meters and publishes
    /// smoothed level + elapsed-time progress. Cancelled when act ends.
    private func startMeteringTask() {
        meteringTask?.cancel()
        meteringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let r = self.recorder, r.isRecording else { break }
                r.updateMeters()
                let db     = r.averagePower(forChannel: 0)
                let linear = pow(10.0, db / 20.0)
                self.audioLevel  = self.audioLevel * 0.65 + Float(min(1.0, linear * 4.5)) * 0.35
                self.actProgress = min(Date().timeIntervalSince(self.actStartTime) / self.actDuration, 1.0)
                try? await Task.sleep(nanoseconds: 33_333_333)   // ~30 fps
            }
        }
    }

    // MARK: - Act completion (called from delegate)

    private func onRecordingFinished(successfully: Bool) {
        meteringTask?.cancel()
        meteringTask = nil
        audioLevel  = 0
        actProgress = 1.0

        guard successfully else {
            phase = .failed("Recording failed for \(currentAct.displayName). Please try again.")
            return
        }

        if let next = currentAct.next {
            Task {
                phase = .between(next: next)
                try? await Task.sleep(for: .seconds(2))
                await beginCountdown(for: next)
            }
        } else {
            Task { await processProfiles() }
        }
    }

    // MARK: - Profile processing (sequential — single VoiceboxEngine)

    private func processProfiles() async {
        phase = .processing(completed: 0, total: Act.allCases.count)
        do {
            for (i, act) in Act.allCases.enumerated() {
                guard let url = actAudioURLs[act] else {
                    throw RecordingError.missingAudio(act.displayName)
                }
                let audioData  = try Data(contentsOf: url)
                let outputPath = manager.voiceProfilePath(forMood: act.moodToken)

                // Encrypt the primary (warmth) recording for secure backup
                if act == .warmth {
                    try? SecureStorageService().saveVoiceProfile(audioData)
                }

                try await VoiceboxService.shared.createVoiceProfile(
                    audioData:  audioData,
                    outputPath: outputPath
                )

                try? FileManager.default.removeItem(at: url)
                phase = .processing(completed: i + 1, total: Act.allCases.count)
            }

            // Register the warmth/normal profile as the active voice
            VoiceboxService.shared.setVoiceProfile(
                path: manager.voiceProfilePath(forMood: "normal")
            )

            await runValidation()

        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Validation

    private func runValidation() async {
        phase = .validation
        do {
            let wav = try await VoiceboxService.shared.synthesize(
                "Hello! I'm so happy to be your storyteller. Let's go on a magical adventure tonight."
            )
            validationWAV = wav
            playValidationAudio(wav: wav)
        } catch {
            // Synthesis failed — skip preview and let user proceed manually
            isValidationReady = true   // show card in "no audio" state
        }
    }

    private func playValidationAudio(wav: Data) {
        guard let player = try? VoiceboxService.shared.play(wav: wav) else { return }
        player.isMeteringEnabled = true
        validationPlayer    = player
        audioLevel          = 0          // clear carry-over before smoothing loop starts
        isValidationReady   = true
        isPlayingValidation = true

        // Metering loop — reuses audioLevel so waveform bars respond to real output
        meteringTask?.cancel()
        meteringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let p = self.validationPlayer else { break }
                guard p.isPlaying else {
                    self.isPlayingValidation = false
                    self.audioLevel = 0
                    break
                }
                p.updateMeters()
                let db     = p.averagePower(forChannel: 0)
                let linear = pow(10.0, db / 20.0)
                self.audioLevel = self.audioLevel * 0.6 + Float(min(1.0, linear * 3.5)) * 0.4
                try? await Task.sleep(nanoseconds: 33_333_333)
            }
        }
    }

    /// Called by the replay button — plays the cached WAV without re-synthesizing.
    func replayValidation() {
        guard let wav = validationWAV, !isPlayingValidation else { return }
        playValidationAudio(wav: wav)
    }

    /// Called by "Sounds great" CTA — advances to library.
    func confirmVoice() {
        meteringTask?.cancel()
        meteringTask = nil
        validationPlayer?.stop()
        validationPlayer = nil
        audioLevel = 0
        phase = .done
    }

    // MARK: - Helpers

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func tempURL(for act: Act) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("storytime_act_\(act.rawValue).wav")
    }
}

// MARK: - AVAudioRecorderDelegate

extension RecordingViewModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.onRecordingFinished(successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "Unknown encoding error"
        Task { @MainActor [weak self] in
            self?.phase = .failed("Recording error: \(message)")
        }
    }
}

// MARK: - Error

private enum RecordingError: LocalizedError {
    case missingAudio(String)
    var errorDescription: String? {
        if case .missingAudio(let name) = self {
            return "Audio file missing for the \(name) act."
        }
        return nil
    }
}
