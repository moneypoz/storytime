import AVFoundation
import SwiftUI
import VoiceboxCore

/// Full-screen story player with dreamscape background and liquid glass orb.
///
/// TTSPlayer uses two paths:
///   • Voicebox (primary)  — if VoiceboxService is loaded and a voice profile
///     is registered.  Segments are synthesized on Tokio's blocking pool and
///     played via AVAudioPlayer.  The next segment is pre-fetched while the
///     current one plays, so gaps between segments are eliminated.
///   • AVSpeechSynthesizer (fallback) — used when the model is not yet
///     downloaded or no voice profile has been recorded.
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
    @State private var heroOpacity: Double = 1.0

    // MARK: - Init

    init(book: Book, namespace: Namespace.ID, onDismiss: @escaping () -> Void) {
        self.book = book
        self.namespace = namespace
        self.onDismiss = onDismiss

        // Restore saved segment index.  If the story was previously finished,
        // start from the beginning so the user gets a fresh playthrough.
        let saved = PersistenceController.shared.fetchProgress(for: book.id)
        let startSegment = (saved.map { !$0.isFinished && $0.segmentIndex > 0 } == true)
            ? Int(saved!.segmentIndex) : 0

        self._ttsPlayer = StateObject(
            wrappedValue: TTSPlayer(
                script: book.script,
                bookID: book.id,
                startSegment: startSegment
            )
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DreamscapeBackground(atmosphereOpacity: atmosphereOpacity)

            // Hero gradient — springs from card position → full screen, then fades to
            // reveal DreamscapeBackground. On dismiss, snapped back to opacity 1 so the
            // reverse geometry animation is visible.
            LinearGradient(
                colors: book.coverGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .matchedGeometryEffect(id: book.id, in: namespace)
            .ignoresSafeArea()
            .opacity(heroOpacity)

            VStack(spacing: 0) {
                closeButton
                    .padding(.top, 16)

                Spacer()

                titleSection
                    .padding(.bottom, 24)

                storySection
                    .padding(.bottom, 32)

                LiquidGlassOrb(
                    audioLevel: ttsPlayer.audioLevel,
                    progress: ttsPlayer.progress,
                    accentColor: book.coverGradient.first ?? DesignSystem.primaryPurple
                )
                .aiGlowBackground(
                    vibrancy: glowVibrancy,
                    color: book.coverGradient.first ?? DesignSystem.primaryPurple
                )

                Spacer()

                playPauseButton
                    .padding(.bottom, 60)
            }
            .opacity(ttsPlayer.isFinished ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: ttsPlayer.isFinished)

            if ttsPlayer.isFinished {
                StoryFinishView(
                    book: book,
                    onReadAgain: restartPlayback,
                    onFinish: onDismiss
                )
                .zIndex(2)
            }
        }
        .onAppear {
            // Fade hero out after the spring has settled
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                heroOpacity = 0
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
                // Snap hero visible instantly so the reverse geometry animation
                // (player → card) is visible during the dismiss spring.
                heroOpacity = 1
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
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

    // MARK: - Story Section

    /// Glass text card with the character bubble anchored to its top-left corner.
    ///
    /// Layout math (CharacterNarratorView.containerSize = 120 pt):
    ///   • The bubble container starts at the card's top-left via `.overlay(alignment: .topLeading)`.
    ///   • Offset (x: 8, y: -12) nudges the 120×120 frame so the visual circle (72 pt,
    ///     centered at 60,60 within the container) sits mostly inside the card while
    ///     its top 12 pt hangs above the card edge.
    ///   • `.padding(.top, 80)` pushes the first text line clear of the bubble's bottom
    ///     edge (container y = 108 after offset), avoiding overlap.
    @ViewBuilder
    private var storySection: some View {
        if let text = ttsPlayer.currentText {
            Text(text)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                // Top padding reserves space for the bubble; horizontal padding is
                // kept uniform so text reflows cleanly as segment length varies.
                .padding(.top, 80)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )
                // Crossfade text on each segment advance
                .id(ttsPlayer.currentSegmentIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: ttsPlayer.currentSegmentIndex)
                // Character bubble — top-left corner of the card
                .overlay(alignment: .topLeading) {
                    if ttsPlayer.currentEmoji != nil {
                        CharacterNarratorView(
                            emoji:       ttsPlayer.currentEmoji,
                            audioLevel:  CGFloat(ttsPlayer.audioLevel),
                            accentColor: book.coverGradient.first ?? DesignSystem.primaryPurple
                        )
                        .offset(x: 8, y: -12)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal:   .opacity
                        ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ttsPlayer.currentEmoji)
        }
    }

    private var playbackStatus: String {
        if ttsPlayer.isPlaying    { return "Playing.." }
        if ttsPlayer.progress > 0 { return "Paused" }
        return "Tap to begin"
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Button {
            if ttsPlayer.isPlaying { ttsPlayer.pause() } else { ttsPlayer.play() }
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive(), in: .circle)

                Image(systemName: ttsPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(x: ttsPlayer.isPlaying ? 0 : 3)
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
            case .excited:       glowVibrancy = .vivid;    atmosphereOpacity = 1.0
            case .sleepy:        glowVibrancy = .subtle;   atmosphereOpacity = 0.2
            case .normal, nil:   glowVibrancy = .standard; atmosphereOpacity = 1.0
            }
        }
    }
}

// MARK: - TTSPlayer

/// Observable playback engine.
///
/// Pipeline (Voicebox path):
///   playSegment(N) → start synthesis of N
///                 → when N ready, play via AVAudioPlayer
///                 → immediately prefetch segment N+1 in background
///                 → AVAudioPlayerDelegate fires → playSegment(N+1) with zero gap
///
/// Fallback (AVSpeechSynthesizer path):
///   Used when VoiceboxService.isLoaded == false or hasVoiceProfile == false.
final class TTSPlayer: NSObject, ObservableObject {

    @Published private(set) var isPlaying = false
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var isFinished = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentMood: StoryScript.Segment.Mood?

    /// Speaker emoji for the active segment (e.g. 🦁 / 🐭 / 🌿).
    /// Derived from `currentSegmentIndex` — updates automatically as playback advances.
    var currentEmoji: String? { segments[safe: currentSegmentIndex]?.speakerEmoji ?? nil }
    /// Full text of the active segment for UI highlighting.
    var currentText: String?  { segments[safe: currentSegmentIndex]?.text }

    // ── Shared ──────────────────────────────────────────────────────────────

    private let segments: [StoryScript.Segment]
    private let bookID: String
    private var levelTimer: Timer?

    // ── Voicebox pipeline ────────────────────────────────────────────────────

    /// WAV bytes cached per segment index.  Survives pause/resume.
    private var wavCache: [Int: Data] = [:]
    private var currentPlayer: AVAudioPlayer?
    private var prefetchTask: Task<Void, Never>?

    // ── AVSpeechSynthesizer fallback ─────────────────────────────────────────

    private let synthesizer = AVSpeechSynthesizer()
    private var progressTimer: Timer?
    private let fallbackDuration: Double = 180

    // ── Path selection ───────────────────────────────────────────────────────

    private var useVoicebox: Bool {
        VoiceboxService.shared.isLoaded && VoiceboxService.shared.hasVoiceProfile
    }

    // MARK: - Init

    init(script: StoryScript?, bookID: String, startSegment: Int = 0) {
        self.segments = script?.segments ?? []
        self.bookID   = bookID
        super.init()
        synthesizer.delegate = self

        // Restore state — must happen after super.init()
        currentSegmentIndex = startSegment
        if !segments.isEmpty, startSegment > 0 {
            progress = Double(startSegment) / Double(segments.count)
        }
    }

    // MARK: - Public control

    func play() {
        guard !isFinished else { return }
        configureAudioSession()
        isPlaying = true

        if segments.isEmpty {
            startFallbackTimer()
        } else if useVoicebox {
            // If the player is mid-segment and just paused, resume it
            if let player = currentPlayer, !player.isPlaying {
                player.play()
            } else if currentPlayer == nil {
                playVoiceboxSegment(at: currentSegmentIndex)
            }
        } else {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            } else if !synthesizer.isSpeaking {
                speakCurrentSegment()
            }
        }

        startLevelSimulation()
    }

    func pause() {
        isPlaying = false
        prefetchTask?.cancel()
        currentPlayer?.pause()
        if segments.isEmpty {
            progressTimer?.invalidate()
        } else if !useVoicebox {
            synthesizer.pauseSpeaking(at: .word)
        }
        stopLevelSimulation()
        PersistenceController.shared.saveProgress(
            bookID: bookID,
            segmentIndex: currentSegmentIndex,
            isFinished: false
        )
    }

    func stop() {
        isPlaying = false
        prefetchTask?.cancel()
        prefetchTask = nil
        currentPlayer?.stop()
        currentPlayer = nil
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
        wavCache.removeAll()   // clear cache so re-play uses fresh audio
        PersistenceController.shared.resetProgress(for: bookID)
    }

    // MARK: - Voicebox pipeline

    private func playVoiceboxSegment(at index: Int) {
        guard index < segments.count else { markFinished(); return }

        currentSegmentIndex = index
        currentMood = segments[index].mood
        progress = Double(index) / Double(segments.count)
        PersistenceController.shared.saveProgress(
            bookID: bookID,
            segmentIndex: index,
            isFinished: false
        )

        // Mood-aware profile selection (falls back to default if mood clip absent)
        let profilePath = ModelManager().voiceProfilePath(
            forMood: segments[index].mood.rawValue
        )

        if let cached = wavCache[index] {
            // Zero gap — already synthesized while previous segment played
            startPlayer(wav: cached, segmentIndex: index)
            prefetchSegment(index + 1, profilePath: profilePath)
        } else {
            // Synthesize now (first segment, or cache miss after restart)
            Task { @MainActor [weak self] in
                guard let self, isPlaying else { return }
                do {
                    let wav = try await VoiceboxService.shared.synthesize(segments[index].text)
                    wavCache[index] = wav
                    guard isPlaying else { return }
                    startPlayer(wav: wav, segmentIndex: index)
                    prefetchSegment(index + 1, profilePath: profilePath)
                } catch {
                    segmentDidFinish(index)   // skip on error, advance to next
                }
            }
        }
    }

    private func prefetchSegment(_ index: Int, profilePath: String) {
        guard index < segments.count, wavCache[index] == nil else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard let wav = try? await VoiceboxService.shared.synthesize(
                segments[index].text
            ) else { return }
            guard !Task.isCancelled else { return }
            wavCache[index] = wav
        }
    }

    private func startPlayer(wav: Data, segmentIndex: Int) {
        do {
            let player = try AVAudioPlayer(data: wav)
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()
            player.play()
            currentPlayer = player
        } catch {
            segmentDidFinish(segmentIndex)
        }
    }

    private func segmentDidFinish(_ index: Int) {
        guard isPlaying else { return }
        currentPlayer = nil
        if useVoicebox {
            playVoiceboxSegment(at: index + 1)
        } else {
            currentSegmentIndex = index + 1
            speakCurrentSegment()
        }
    }

    private func markFinished() {
        isFinished = true
        isPlaying = false
        stopLevelSimulation()
        PersistenceController.shared.saveProgress(
            bookID: bookID,
            segmentIndex: segments.count,
            isFinished: true
        )
    }

    // MARK: - AVSpeechSynthesizer fallback

    private func speakCurrentSegment() {
        guard currentSegmentIndex < segments.count else { markFinished(); return }

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
        progressTimer = Timer.scheduledTimer(
            withTimeInterval: tickInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.progress < 1.0 {
                    self.progress += increment
                } else {
                    self.progressTimer?.invalidate()
                    self.markFinished()
                }
            }
        }
    }

    // MARK: - Audio session + level simulation

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startLevelSimulation() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }

            let target: Float
            if let player = currentPlayer, player.isPlaying {
                // Real metering from AVAudioPlayer — convert dBFS to linear [0, 1]
                player.updateMeters()
                let db = player.averagePower(forChannel: 0)  // typically -160…0 dBFS
                let linear = pow(10.0, db / 20.0)            // linear amplitude
                target = max(0, min(1, linear * 3.5))        // scale up for orb visibility
            } else {
                // Fallback for AVSpeechSynthesizer path (no metering API)
                target = max(0, min(1, 0.3 + Float.random(in: -0.2...0.35)))
            }

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
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async {
            self.currentSegmentIndex += 1
            if self.isPlaying { self.speakCurrentSegment() }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension TTSPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, isPlaying else { return }
            segmentDidFinish(currentSegmentIndex)
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - GlassButtonStyle

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
    PlayerView(book: Book.samples[0], namespace: namespace, onDismiss: {})
}
