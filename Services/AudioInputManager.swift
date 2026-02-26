import AVFoundation
import Combine

/// Manages audio input from the microphone for voice recording and level detection
@MainActor
final class AudioInputManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var hasPermission = false
    @Published private(set) var recordedAudioURL: URL?

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    // MARK: - Constants

    private let targetDuration: TimeInterval = 30.0
    private let levelUpdateInterval: TimeInterval = 0.05

    // MARK: - Initialization

    init() {
        Task {
            await checkPermission()
        }
    }

    // MARK: - Permission

    func checkPermission() async {
        let status = AVAudioApplication.shared.recordPermission

        switch status {
        case .granted:
            hasPermission = true
        case .denied:
            hasPermission = false
        case .undetermined:
            hasPermission = await AVAudioApplication.requestRecordPermission()
        @unknown default:
            hasPermission = false
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard hasPermission else { return }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("parent_voice_sample.wav")

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: recordingSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record(forDuration: targetDuration)

            isRecording = true
            startLevelMonitoring()

            // Auto-stop after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + targetDuration) { [weak self] in
                self?.stopRecording()
            }

        } catch {
            print("Recording failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        recordedAudioURL = audioRecorder?.url
        isRecording = false
        audioLevel = 0.0
    }

    // MARK: - Level Monitoring

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: levelUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAudioLevel()
            }
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0.0
            return
        }

        recorder.updateMeters()

        // Convert decibels to normalized value (0.0 - 1.0)
        let decibels = recorder.averagePower(forChannel: 0)
        let normalizedLevel = pow(10, decibels / 20)

        // Smooth the level changes for better visual feedback
        audioLevel = audioLevel * 0.7 + normalizedLevel * 0.3
    }

    // MARK: - Cleanup

    func deleteRecording() {
        guard let url = recordedAudioURL else { return }

        try? FileManager.default.removeItem(at: url)
        recordedAudioURL = nil
    }
}
