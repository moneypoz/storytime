import SwiftUI
import AVFoundation

/// Full-screen story player with dreamscape background and liquid glass orb.
/// Uses AVSpeechSynthesizer for expressive TTS playback with mood-based prosody.
/// Falls back to a progress timer for books without a script.
struct PlayerView: View {

    // MARK: - Properties

    let book: Book
    let namespace: Namespace.ID
    let onDismiss: () -> Void

    // MARK: - State Objects

    @StateObject private var ttsPlayer: TTSPlayer

    // MARK: - Atmosphere

    @State private var glowVibrancy: AIGlowVibrancy = .standard
    @State private var atmosphereOpacity: Double = 1.0

    // MARK: - Init

    init(book: Book, namespace: Namespace.ID, onDismiss: @escaping () -> Void) {
        self.book = book
        self.namespace = namespace
        self.onDismiss = onDismiss
        self._ttsPlayer = StateObject(wrappedValue: TTSPlayer(script: book.script))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dreamscape background
            DreamscapeBackground(atmosphereOpacity: atmosphereOpacity)

            // Content
            VStack(spacing: 0) {
                closeButton
                    .padding(.top, 16)

                Spacer()

                titleSection
                    .padding(.bottom, 40)

                // Liquid glass orb — animated by real TTS audio level
                LiquidGlassOrb(
                    audioLevel: ttsPlayer.audioLevel,
                    progress: ttsPlayer.progress,
                    accentColor: book.coverGradient.first ?? DesignSystem.primaryPurple
                )
                .aiGlowBackground(
                    vibrancy: glowVibrancy,
                    color: book.coverGradient.first ?? DesignSystem.primaryPurple
                )
                .matchedGeometryEffect(id: book.id, in: namespace)

                Spacer()

                playPauseButton
                    .padding(.bottom, 60)
            }
            // Fade controls out as the finish view blooms in
            .opacity(ttsPlayer.isFinished ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: ttsPlayer.isFinished)

            // Story finish celebration
            if ttsPlayer.isFinished {
                StoryFinishView(
                    book: book,
                    onReadAgain: restartPlayback,
                    onFinish: onDismiss
                )
                .zIndex(2)
            }
        }
        .onChange(of: ttsPlayer.currentSegmentIndex) {
            updateAtmosphere()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            ttsPlayer.stop()
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(DesignSystem.slowTransition) {
                    ttsPlayer.stop()
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 24)
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(book.title)
                .font(DesignSystem.headlineFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(playbackStatus)
                .font(DesignSystem.captionFont)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 40)
    }

    private var playbackStatus: String {
        if ttsPlayer.isPlaying {
            return "Playing.."
        } else if ttsPlayer.progress > 0 {
            return "Paused"
        } else {
            return "Tap to begin"
        }
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Button {
            if ttsPlayer.isPlaying {
                ttsPlayer.pause()
            } else {
                ttsPlayer.play()
            }
        } label: {
            ZStack {
                // Glass background
                Circle()
                    .fill(.clear)
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive(), in: .circle)

                // Icon
                Image(systemName: ttsPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(x: ttsPlayer.isPlaying ? 0 : 3) // Visual centering for play icon
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(GlassButtonStyle())
    }

    // MARK: - Actions

    private func restartPlayback() {
        ttsPlayer.restart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            ttsPlayer.play()
        }
    }

    private func updateAtmosphere() {
        withAnimation(.easeInOut(duration: 1.5)) {
            switch ttsPlayer.currentMood {
            case .excited:
                glowVibrancy = .vivid
                atmosphereOpacity = 1.0
            case .sleepy:
                glowVibrancy = .subtle
                atmosphereOpacity = 0.2
            case .normal, nil:
                glowVibrancy = .standard
                atmosphereOpacity = 1.0
            }
        }
    }
}

// MARK: - TTS Player

/// Observable TTS engine wrapping AVSpeechSynthesizer.
/// Plays StoryScript segments sequentially with mood-based prosody.
/// Falls back to a progress timer for books without a script.
final class TTSPlayer: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var isFinished = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentMood: StoryScript.Segment.Mood?

    private let synthesizer = AVSpeechSynthesizer()
    private let segments: [StoryScript.Segment]
    private var levelTimer: Timer?
    private var progressTimer: Timer?
    private let fallbackDuration: Double = 180

    init(script: StoryScript?) {
        self.segments = script?.segments ?? []
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Control

    func play() {
        guard !isFinished else { return }
        configureAudioSession()
        isPlaying = true

        if segments.isEmpty {
            startFallbackTimer()
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else if !synthesizer.isSpeaking {
            speakCurrentSegment()
        }

        startLevelSimulation()
    }

    func pause() {
        isPlaying = false
        if segments.isEmpty {
            progressTimer?.invalidate()
        } else {
            synthesizer.pauseSpeaking(at: .word)
        }
        stopLevelSimulation()
    }

    func stop() {
        isPlaying = false
        progressTimer?.invalidate()
        synthesizer.stopSpeaking(at: .immediate)
        stopLevelSimulation()
    }

    func restart() {
        stop()
        currentSegmentIndex = 0
        progress = 0
        isFinished = false
        currentMood = nil
    }

    // MARK: - Private

    private func speakCurrentSegment() {
        guard currentSegmentIndex < segments.count else {
            DispatchQueue.main.async {
                self.isFinished = true
                self.isPlaying = false
                self.stopLevelSimulation()
            }
            return
        }

        let segment = segments[currentSegmentIndex]
        currentMood = segment.mood

        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(segment.mood.rate)
        utterance.pitchMultiplier = Float(segment.mood.pitch)
        utterance.postUtteranceDelay = 0.4

        synthesizer.speak(utterance)
        progress = Double(currentSegmentIndex) / Double(segments.count)
    }

    private func startFallbackTimer() {
        let tickInterval: Double = 0.1
        let increment = tickInterval / fallbackDuration
        progressTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.progress < 1.0 {
                    self.progress += increment
                } else {
                    self.progressTimer?.invalidate()
                    self.isFinished = true
                    self.isPlaying = false
                    self.stopLevelSimulation()
                }
            }
        }
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startLevelSimulation() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            let base: Float = 0.3
            let variation = Float.random(in: -0.2...0.35)
            let target = max(0, min(1, base + variation))
            DispatchQueue.main.async {
                self.audioLevel = self.audioLevel * 0.6 + target * 0.4
            }
        }
    }

    private func stopLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = nil
        DispatchQueue.main.async { self.audioLevel = 0 }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.currentSegmentIndex += 1
            if self.isPlaying {
                self.speakCurrentSegment()
            }
        }
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @Namespace var namespace

    PlayerView(
        book: Book.samples[0],
        namespace: namespace,
        onDismiss: {}
    )
}
