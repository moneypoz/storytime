import Foundation
import Speech
import AVFoundation

/// Real-time speech recognition for tracking script progress
/// Uses on-device recognition for privacy compliance
@MainActor
final class SpeechRecognizer: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isListening = false
    @Published private(set) var hasPermission = false
    @Published private(set) var transcript = ""
    @Published private(set) var recognizedWords: Set<String> = []
    @Published private(set) var confidence: Float = 0.0

    // MARK: - Private Properties

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()

    // MARK: - Initialization

    init() {
        // Use on-device recognition for privacy
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.supportsOnDeviceRecognition = true

        Task {
            await checkPermissions()
        }
    }

    // MARK: - Permissions

    func checkPermissions() async {
        // Check speech recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        switch speechStatus {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            hasPermission = granted
        default:
            hasPermission = false
        }

        // Also need microphone permission
        if hasPermission {
            let audioStatus = AVAudioApplication.shared.recordPermission
            if audioStatus == .undetermined {
                hasPermission = await AVAudioApplication.requestRecordPermission()
            } else {
                hasPermission = audioStatus == .granted
            }
        }
    }

    // MARK: - Recognition Control

    func startListening() {
        guard hasPermission,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            return
        }

        // Reset state
        transcript = ""
        recognizedWords = []
        confidence = 0.0

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else { return }

        // Configure for on-device, real-time results
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.processResult(result)
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Audio engine failed to start: \(error)")
            stopListening()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    // MARK: - Result Processing

    private func processResult(_ result: SFSpeechRecognitionResult) {
        transcript = result.bestTranscription.formattedString

        // Extract individual words (normalized to lowercase)
        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        recognizedWords = Set(words)

        // Calculate average confidence
        let segments = result.bestTranscription.segments
        if !segments.isEmpty {
            let totalConfidence = segments.reduce(0.0) { $0 + $1.confidence }
            confidence = Float(totalConfidence) / Float(segments.count)
        }
    }

    // MARK: - Word Matching

    /// Check if a phrase has been spoken (fuzzy matching)
    func hasSpoken(phrase: String, threshold: Double = 0.6) -> Bool {
        let phraseWords = phrase
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !phraseWords.isEmpty else { return false }

        let matchedCount = phraseWords.filter { recognizedWords.contains($0) }.count
        let matchRatio = Double(matchedCount) / Double(phraseWords.count)

        return matchRatio >= threshold
    }

    /// Check completion percentage for a set of key phrases
    func completionPercentage(for keyPhrases: [String]) -> Double {
        guard !keyPhrases.isEmpty else { return 0 }

        let completedCount = keyPhrases.filter { hasSpoken(phrase: $0, threshold: 0.5) }.count
        return Double(completedCount) / Double(keyPhrases.count)
    }
}
