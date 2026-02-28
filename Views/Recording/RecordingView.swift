import SwiftUI
import VoiceboxCore

struct RecordingView: View {

    // MARK: - Environment / ViewModel

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = RecordingViewModel()

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            phaseContent
                .animation(.spring(duration: 0.5, bounce: 0.1), value: viewModel.phase)

            if case .ready = viewModel.phase, !viewModel.isEngineReady {
                modelEngineOverlay
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: viewModel.isEngineReady)
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .done = phase { appState.completeOnboarding() }
        }
        .statusBarHidden()
    }

    // MARK: - Background

    /// Accent colour shifts with the current act, giving each recording a distinct
    /// ambient feel without changing the overall midnight tone.
    private var background: some View {
        let accent: Color = {
            switch viewModel.phase {
            case .recording(let act):  return act.accentColor
            case .between(let next):   return next.accentColor
            default:                   return Color(hex: "6366f1")
            }
        }()

        return ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "020617"),
                    Color(hex: "1e1b4b").opacity(0.35),
                    Color(hex: "020617")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(accent.opacity(0.1))
                .frame(width: 480)
                .blur(radius: 90)
                .animation(.easeInOut(duration: 1.2), value: viewModel.phase)
        }
        .ignoresSafeArea()
    }

    // MARK: - Phase dispatch

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {

        case .ready:
            readyContent
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

        case .countdown(let n):
            countdownContent(n)
                .transition(.opacity.combined(with: .scale(scale: 1.15)))

        case .recording(let act):
            recordingContent(act: act)
                .transition(.opacity)

        case .between(let next):
            betweenContent(next: next)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    )
                )

        case .processing(let completed, let total):
            processingContent(completed: completed, total: total)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .validation:
            validationContent
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

        case .done:
            Color.clear   // onChange handles navigation

        case .failed(let message):
            failedContent(message: message)
                .transition(.opacity)
        }
    }

    // MARK: - Engine-not-ready overlay

    /// Full-screen blur overlay shown while VoiceboxService is still loading its
    /// weights into memory.  Sits above `.ready` content so the Begin button is
    /// visible but unreachable — the guard in RecordingViewModel.start() is the
    /// hard gate; this provides the soft visual affordance.
    private var modelEngineOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))
                    .symbolEffect(.pulse)

                VStack(spacing: 10) {
                    Text("Fine-tuning your storyteller's studio…")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("This only takes a moment.")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                StudioShimmerBar()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Ready

    private var readyContent: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 68, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                Text("Capture Your Voice")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)

                Text("Three short recordings capture the full range\nof your storytelling voice.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.bottom, 40)

            // Act preview pills
            HStack(spacing: 10) {
                ForEach(RecordingViewModel.Act.allCases) { act in
                    Label(act.displayName, systemImage: act.icon)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(act.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(act.accentColor.opacity(0.14), in: Capsule())
                }
            }
            .padding(.bottom, 56)

            Button(action: viewModel.start) {
                Text("Begin")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
    }

    // MARK: - Countdown

    private func countdownContent(_ count: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text("\(count)")
                .font(.system(size: 112, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .id(count)

            Text("Get ready…")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            Spacer()
        }
    }

    // MARK: - Recording

    private func recordingContent(act: RecordingViewModel.Act) -> some View {
        VStack(spacing: 0) {

            // Metallic progress bar — same visual language as the original view
            metallicProgressBar(color: act.accentColor)

            actBadge(act: act)
                .padding(.top, 28)
                .padding(.bottom, 24)

            // Canvas voice sphere (preserved from original RecordingView)
            voiceSphere(isRecording: true, accentColor: act.accentColor)
                .padding(.bottom, 28)

            // Single script card for the current act
            scriptCard(act: act)
                .padding(.horizontal, 24)
                .id(act)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))

            Spacer()

            // Seconds remaining
            let remaining = Int(ceil((1 - viewModel.actProgress) * actDuration))
            Text("\(max(0, remaining))s")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
                .contentTransition(.numericText(countsDown: true))
                .padding(.bottom, 32)
        }
    }

    private let actDuration: Double = 12

    // MARK: - Between acts

    private func betweenContent(next: RecordingViewModel.Act) -> some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: "4ADE80").opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color(hex: "4ADE80"))
            }

            VStack(spacing: 10) {
                Text("Nice work!")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Next up:")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))

                Label(next.displayName, systemImage: next.icon)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(next.accentColor)

                Text(next.instruction)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
            }

            Spacer()
        }
    }

    // MARK: - Processing

    private func processingContent(completed: Int, total: Int) -> some View {
        VStack(spacing: 44) {
            Spacer()

            VStack(spacing: 10) {
                Text("Building your voice…")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)

                Text("Applying noise reduction and profile encoding")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 20) {
                ForEach(Array(RecordingViewModel.Act.allCases.enumerated()), id: \.offset) { i, act in
                    let isDone   = i < completed
                    let isActive = i == completed

                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    isDone    ? Color(hex: "4ADE80")       :
                                    isActive  ? act.accentColor.opacity(0.3) :
                                                Color.white.opacity(0.07)
                                )
                                .frame(width: 40, height: 40)

                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if isActive {
                                ProgressView()
                                    .tint(act.accentColor)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: act.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                        .animation(.spring(duration: 0.5), value: completed)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(act.displayName)
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                                .foregroundStyle(isDone ? .white : .white.opacity(0.4))

                            Text(act.instruction)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.25))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
    }

    // MARK: - Validation (Voice Preview Card)

    private var validationContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Text("Your Voice is Ready")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)

                Text("Hear how your stories will sound")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.bottom, 32)

            voicePreviewCard

            Spacer()

            // CTA — visible once synthesis has completed
            if viewModel.isValidationReady {
                VStack(spacing: 14) {
                    Button(action: viewModel.confirmVoice) {
                        Text("Sounds great — Enter Library")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .fontWidth(.expanded)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("Record again", action: viewModel.restart)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 32)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()
                .frame(height: 48)
        }
        .animation(.spring(duration: 0.5, bounce: 0.15), value: viewModel.isValidationReady)
    }

    private var voicePreviewCard: some View {
        VStack(spacing: 0) {

            // Header row — voice name + live indicator
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "6366f1"))
                    .symbolEffect(.pulse, isActive: viewModel.isPlayingValidation)

                Text("Your Voice")
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.isPlayingValidation {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "4ADE80"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "4ADE80").opacity(0.15), in: Capsule())
                }
            }
            .padding(.bottom, 24)

            // Waveform visualizer — real audio levels during playback,
            // idle bars while synthesizing / after playback ends
            waveformVisualizer
                .frame(height: 56)
                .padding(.bottom, 24)

            Divider()
                .overlay(.white.opacity(0.08))
                .padding(.bottom, 16)

            // Controls row
            HStack {
                // Replay button
                Button(action: viewModel.replayValidation) {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(
                            viewModel.isPlayingValidation
                                ? .white.opacity(0.25)
                                : .white.opacity(0.65)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPlayingValidation)

                Spacer()

                // Loading spinner while synthesis is running
                if !viewModel.isValidationReady {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.75)
                        Text("Synthesizing…")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 28)
        .shadow(color: Color(hex: "6366f1").opacity(0.15), radius: 24, y: 12)
    }

    /// Waveform bars driven by real `audioLevel` during playback;
    /// shows a gentle idle state while synthesizing or after playback ends.
    private var waveformVisualizer: some View {
        HStack(spacing: 4) {
            ForEach(0..<28, id: \.self) { i in
                LiveWaveformBar(
                    index:     i,
                    level:     viewModel.audioLevel,
                    isLive:    viewModel.isPlayingValidation,
                    color:     Color(hex: "6366f1")
                )
            }
        }
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("Something went wrong")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: viewModel.restart) {
                Text("Try Again")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Components

    /// Metallic silver bar from the original RecordingView, adapted for per-act progress.
    private func metallicProgressBar(color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.07))

                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: color.opacity(0.6), location: 0.0),
                                .init(color: color,              location: 0.5),
                                .init(color: .white.opacity(0.9), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * viewModel.actProgress)
                    .animation(.linear(duration: 0.05), value: viewModel.actProgress)

                if viewModel.actProgress > 0, viewModel.actProgress < 1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.5), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 24)
                        .offset(x: max(0, geo.size.width * viewModel.actProgress - 24))
                        .animation(.linear(duration: 0.05), value: viewModel.actProgress)
                }
            }
        }
        .frame(height: 3)
        .shadow(color: color.opacity(0.4), radius: 6)
    }

    private func actBadge(act: RecordingViewModel.Act) -> some View {
        VStack(spacing: 10) {
            // Dot progress — filled segments show which acts are done
            HStack(spacing: 6) {
                ForEach(RecordingViewModel.Act.allCases) { a in
                    Capsule()
                        .fill(a.rawValue <= act.rawValue ? act.accentColor : .white.opacity(0.15))
                        .frame(width: a == act ? 28 : 12, height: 5)
                        .animation(.spring(duration: 0.4), value: act)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: act.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(act.accentColor)

                Text(act.displayName)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(act.accentColor)

                Text("· \(act.rawValue + 1) of \(RecordingViewModel.Act.allCases.count)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text(act.instruction)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// Canvas-based voice sphere preserved from the original RecordingView.
    /// Four concentric rings breathe with the audio level.
    private func voiceSphere(isRecording: Bool, accentColor: Color) -> some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRecording)) { _ in
                Canvas { context, size in
                    let center     = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseRadius: CGFloat = 58
                    let level      = CGFloat(viewModel.audioLevel)

                    for i in 0..<4 {
                        let radius  = baseRadius + CGFloat(i) * 12 + level * 32
                        let opacity = Double(4 - i) / 4.0 * (isRecording ? 0.38 : 0.07)
                        var ring = Path()
                        ring.addArc(
                            center:     center,
                            radius:     radius,
                            startAngle: .zero,
                            endAngle:   .degrees(360),
                            clockwise:  false
                        )
                        context.stroke(ring, with: .color(.white.opacity(opacity)), lineWidth: 1.0)
                    }

                    let glowRadius = baseRadius - 4 + level * 12
                    var glow = Path()
                    glow.addArc(
                        center:     center,
                        radius:     glowRadius,
                        startAngle: .zero,
                        endAngle:   .degrees(360),
                        clockwise:  false
                    )
                    context.fill(glow, with: .color(.white.opacity(0.04 + Double(level) * 0.13)))
                }
            }
            .frame(width: 180, height: 180)
            .allowsHitTesting(false)

            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 116, height: 116)
                    .glassEffect(.regular, in: Circle())

                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .symbolEffect(.pulse, isActive: isRecording)
            }
        }
    }

    private func scriptCard(act: RecordingViewModel.Act) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Read aloud", systemImage: "text.alignleft")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(act.accentColor.opacity(0.8))

            Text(act.prompt)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(act.accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(act.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

}

// MARK: - StudioShimmerBar

/// Indeterminate metallic shimmer bar — identical visual language to the
/// download and recording progress bars, but looping forever rather than
/// filling toward a known total.
private struct StudioShimmerBar: View {

    /// Drives the shimmer blob's horizontal travel.  Animates 0 → 1 on appear,
    /// repeating linearly so the blob sweeps left-to-right continuously.
    @State private var phase: CGFloat = 0

    private let shimmerWidth: CGFloat = 80
    private let duration: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            // Blob starts fully off the left edge and exits fully off the right.
            let travel = geo.size.width + shimmerWidth
            let offset = -shimmerWidth + phase * travel

            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(.white.opacity(0.07))

                // Traveling metallic blob — soft-edged gradient fades to clear
                // at both ends so entry and exit are seamless.
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear,                                  location: 0.0),
                                .init(color: Color(hex: "6b7280").opacity(0.5),       location: 0.2),
                                .init(color: Color(hex: "d1d5db"),                    location: 0.4),
                                .init(color: Color(hex: "f9fafb"),                    location: 0.5),
                                .init(color: Color(hex: "d1d5db"),                    location: 0.6),
                                .init(color: Color(hex: "6b7280").opacity(0.5),       location: 0.8),
                                .init(color: .clear,                                  location: 1.0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: shimmerWidth)
                    .offset(x: offset)
            }
            .clipped()
        }
        .frame(height: 3)
        .shadow(color: .white.opacity(0.25), radius: 6)
        .onAppear {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - LiveWaveformBar

/// Waveform bar with two modes:
///  • Live (`isLive = true`): height driven by real `level` from AVAudioPlayer meters.
///    Each bar has a distinct sensitivity so they don't move in lockstep.
///  • Idle (`isLive = false`): true organic breathing via @State + repeatForever.
///    Each bar breathes between its own min/max range at its own speed and phase,
///    so the group looks like a living thing rather than a synchronised graphic.
private struct LiveWaveformBar: View {
    let index: Int
    let level: Float
    let isLive: Bool
    let color: Color

    // Deterministic per-bar constants (stable across renders, derived from index)
    private let sensitivity: CGFloat   // how much this bar reacts to audio level
    private let breathMin:   CGFloat   // idle floor height
    private let breathMax:   CGFloat   // idle peak height
    private let breathSpeed: Double    // full cycle duration in seconds
    private let breathDelay: Double    // stagger so bars are out of phase

    /// Drives the idle breathing oscillation.
    /// withAnimation(.repeatForever) in onAppear animates this between breathMin ↔ breathMax.
    @State private var breathTarget: CGFloat

    init(index: Int, level: Float, isLive: Bool, color: Color) {
        self.index   = index
        self.level   = level
        self.isLive  = isLive
        self.color   = color

        let s        = Double(index)
        sensitivity  = 0.65 + CGFloat((s * 0.13).truncatingRemainder(dividingBy: 0.55))
        breathMin    = 3  + CGFloat((s * 3.7).truncatingRemainder(dividingBy: 6))   //  3–9 pt floor
        breathMax    = 10 + CGFloat((s * 7.1).truncatingRemainder(dividingBy: 22))  // 10–32 pt peak
        breathSpeed  = 0.8 + (s * 0.09).truncatingRemainder(dividingBy: 0.7)        // 0.8–1.5 s/cycle
        breathDelay  = (s * 0.11).truncatingRemainder(dividingBy: 0.6)              // 0–0.6 s stagger

        // Start at floor so the first animation sweeps upward
        _breathTarget = State(initialValue: 3 + CGFloat((s * 3.7).truncatingRemainder(dividingBy: 6)))
    }

    private var liveHeight: CGFloat {
        let base: CGFloat = 5
        return max(base, min(52, base + CGFloat(level) * 46 * sensitivity))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(0.42 + Double(index % 7) * 0.08))
            .frame(width: 4, height: isLive ? liveHeight : breathTarget)
            .animation(isLive ? .easeOut(duration: 0.05) : .spring(duration: 0.35), value: isLive)
            .animation(isLive ? .easeOut(duration: 0.05) : nil, value: liveHeight)
            .onAppear { startBreathing() }
    }

    private func startBreathing() {
        withAnimation(
            .easeInOut(duration: breathSpeed)
                .repeatForever(autoreverses: true)
                .delay(breathDelay)
        ) {
            breathTarget = breathMax
        }
    }
}

// MARK: - Preview

#Preview {
    RecordingView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
