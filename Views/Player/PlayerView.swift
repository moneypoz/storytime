import SwiftUI

/// Full-screen story player with dreamscape background and liquid glass orb
/// Single primary action: Play/Pause
struct PlayerView: View {

    // MARK: - Properties

    let book: Book
    let namespace: Namespace.ID
    let onDismiss: () -> Void

    // MARK: - State

    @State private var isPlaying = false
    @State private var audioLevel: Float = 0.0
    @State private var progress: Double = 0.0
    @State private var showControls = true
    @State private var isFinished = false

    // MARK: - Atmosphere

    @State private var glowVibrancy: AIGlowVibrancy = .standard
    @State private var atmosphereOpacity: Double = 1.0

    // MARK: - Timers

    @State private var playbackTimer: Timer?
    @State private var levelSimulator: Timer?

    // MARK: - Constants

    private let storyDuration: Double = 180 // 3 minutes

    // MARK: - Segment Tracking

    private var currentSegmentIndex: Int {
        guard let count = book.script?.segments.count, count > 0 else { return 0 }
        return min(Int(progress * Double(count)), count - 1)
    }

    private var currentMood: StoryScript.Segment.Mood? {
        guard let segments = book.script?.segments else { return nil }
        return segments[currentSegmentIndex].mood
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dreamscape background
            DreamscapeBackground(atmosphereOpacity: atmosphereOpacity)

            // Content
            VStack(spacing: 0) {
                // Close button
                closeButton
                    .padding(.top, 16)

                Spacer()

                // Book title
                titleSection
                    .padding(.bottom, 40)

                // Liquid glass orb with progress (adaptive tinting from book cover)
                LiquidGlassOrb(
                    audioLevel: audioLevel,
                    progress: progress,
                    accentColor: book.coverGradient.first ?? DesignSystem.primaryPurple
                )
                .aiGlowBackground(
                    vibrancy: glowVibrancy,
                    color: book.coverGradient.first ?? DesignSystem.primaryPurple
                )
                .matchedGeometryEffect(id: book.id, in: namespace)

                Spacer()

                // Play/Pause control
                playPauseButton
                    .padding(.bottom, 60)
            }
            // Fade player controls out as the finish view blooms in
            .opacity(isFinished ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isFinished)

            // Story finish celebration — appears over the dreamscape background
            if isFinished {
                StoryFinishView(
                    book: book,
                    onReadAgain: restartPlayback,
                    onFinish: onDismiss
                )
                .zIndex(2)
            }
        }
        .onChange(of: currentSegmentIndex) {
            updateAtmosphere()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            stopPlayback()
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(DesignSystem.slowTransition) {
                    stopPlayback()
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
        if isPlaying {
            return "Playing.."
        } else if progress > 0 {
            return "Paused"
        } else {
            return "Tap to begin"
        }
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            ZStack {
                // Glass background
                Circle()
                    .fill(.clear)
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive(), in: .circle)

                // Icon
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 3) // Visual centering for play icon
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(GlassButtonStyle())
    }

    // MARK: - Playback Control

    private func togglePlayback() {
        withAnimation(DesignSystem.slowTransition) {
            isPlaying.toggle()
        }

        if isPlaying {
            startPlayback()
        } else {
            pausePlayback()
        }
    }

    private func startPlayback() {
        // Progress timer
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if progress < 1.0 {
                progress += 0.1 / storyDuration
            } else {
                stopPlayback()
                withAnimation(.easeInOut(duration: 0.6)) {
                    isFinished = true
                }
            }
        }

        // Audio level simulator (replace with real TTS levels)
        levelSimulator = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            // Simulate natural speech patterns
            let base: Float = 0.3
            let variation = Float.random(in: -0.2...0.3)
            let newLevel = max(0, min(1, base + variation))

            // Smooth transition
            audioLevel = audioLevel * 0.6 + newLevel * 0.4
        }
    }

    private func pausePlayback() {
        playbackTimer?.invalidate()
        levelSimulator?.invalidate()

        withAnimation(.easeOut(duration: 0.3)) {
            audioLevel = 0
        }
    }

    private func restartPlayback() {
        progress = 0
        audioLevel = 0
        withAnimation(.easeInOut(duration: 0.4)) {
            isFinished = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPlaying = true
            startPlayback()
        }
    }

    private func updateAtmosphere() {
        withAnimation(.easeInOut(duration: 1.5)) {
            switch currentMood {
            case .excited:
                glowVibrancy = .vivid
                atmosphereOpacity = 1.0
            case .sleepy:
                glowVibrancy = .subtle
                atmosphereOpacity = 0.2
            case .normal, .none:
                glowVibrancy = .standard
                atmosphereOpacity = 1.0
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        levelSimulator?.invalidate()
        playbackTimer = nil
        levelSimulator = nil
        audioLevel = 0
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
