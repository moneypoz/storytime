import SwiftUI

struct RecordingView: View {

    // MARK: - Environment

    @EnvironmentObject private var appState: AppState

    // MARK: - State Objects

    @StateObject private var audioManager = AudioInputManager()
    @StateObject private var secureStorage = SecureStorageService()

    // MARK: - State

    /// 0.0 → 1.0 over 30 seconds, drives the progress bar visually.
    @State private var progress: Double = 0.0
    /// Smoothed mic level fed to the Canvas sphere (updated at 20 Hz, rendered at 60 Hz).
    @State private var displayLevel: CGFloat = 0.0
    @State private var hasStarted = false
    @State private var isComplete = false
    @State private var showLibrary = false
    @State private var progressTimer: Timer?

    private let sessionDuration: Double = 30.0

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            if isComplete {
                successView
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                recordingView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: isComplete)
        // Smooth the raw mic level so the sphere doesn't jitter
        .onChange(of: audioManager.audioLevel) { _, level in
            displayLevel = displayLevel * 0.6 + CGFloat(level) * 0.4
        }
        // AudioInputManager auto-stops after 30 s — use that as the ground truth
        .onChange(of: audioManager.isRecording) { _, recording in
            if !recording, hasStarted {
                finishRecording()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView()
        }
        .onChange(of: showLibrary) { _, isShowing in
            if isShowing { appState.completeOnboarding() }
        }
    }

    // MARK: - Background

    private var background: some View {
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
    }

    // MARK: - Recording Layout

    private var recordingView: some View {
        VStack(spacing: 0) {
            metallicProgressBar

            ScrollView {
                VStack(spacing: 24) {
                    header
                        .padding(.top, 24)

                    voiceSphere

                    scriptDisplay
                        .padding(.bottom, 52)
                }
            }
        }
    }

    // MARK: - Metallic Progress Bar

    private var metallicProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(.white.opacity(0.07))

                // Metallic silver fill: dark silver → bright → near-white
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: "6b7280"), location: 0.0),
                                .init(color: Color(hex: "d1d5db"), location: 0.35),
                                .init(color: Color(hex: "f9fafb"), location: 0.65),
                                .init(color: Color(hex: "e5e7eb"), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.1), value: progress)

                // Bright leading-edge shimmer — gives the bar a liquid-metal quality
                if progress > 0, progress < 1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.55), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 28)
                        .offset(x: max(0, geo.size.width * progress - 28))
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
        }
        .frame(height: 3)
        .shadow(color: .white.opacity(0.25), radius: 6)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("Your Voice")
                .font(.system(.title, design: .rounded, weight: .bold))
                .fontWidth(.expanded)
                .foregroundStyle(.white)

            Text(audioManager.isRecording ? "Recording…" : "Tap the sphere to begin")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .animation(.easeInOut(duration: 0.3), value: audioManager.isRecording)
        }
    }

    // MARK: - Voice Sphere Canvas

    private var voiceSphere: some View {
        ZStack {
            // Canvas draws concentric ripple rings keyed to displayLevel.
            // TimelineView drives redraws at up to 60 fps; paused when idle
            // to avoid unnecessary GPU work.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !audioManager.isRecording)) { _ in
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let baseRadius: CGFloat = 58
                    let level = displayLevel

                    // Four concentric rings — each expands proportionally with level
                    for i in 0..<4 {
                        let radius = baseRadius + CGFloat(i) * 12 + level * 32
                        let opacity = Double(4 - i) / 4.0 * (audioManager.isRecording ? 0.38 : 0.07)
                        var ring = Path()
                        ring.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .zero,
                            endAngle: .degrees(360),
                            clockwise: false
                        )
                        context.stroke(ring, with: .color(.white.opacity(opacity)), lineWidth: 1.0)
                    }

                    // Soft filled glow that breathes with the voice
                    let glowRadius = baseRadius - 4 + level * 12
                    var glow = Path()
                    glow.addArc(
                        center: center,
                        radius: glowRadius,
                        startAngle: .zero,
                        endAngle: .degrees(360),
                        clockwise: false
                    )
                    context.fill(glow, with: .color(.white.opacity(0.04 + Double(level) * 0.13)))
                }
            }
            .frame(width: 180, height: 180)
            .allowsHitTesting(false)

            // Liquid Glass orb — tap target
            Button(action: handleOrbTap) {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 116, height: 116)
                        .glassEffect(.regular.interactive(), in: Circle())

                    Image(systemName: audioManager.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                        .symbolEffect(.pulse, isActive: audioManager.isRecording)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Script Display

    private var scriptDisplay: some View {
        VStack(spacing: 20) {
            ForEach(ExpressiveScript.sections) { section in
                scriptCard(for: section)
            }
        }
        .padding(.horizontal, 24)
    }

    private func scriptCard(for section: ExpressiveScript.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mood cue row
            HStack(spacing: 7) {
                Text(section.mood.emoji)
                    .font(.system(size: 15))

                Text(section.mood.direction)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(section.mood.orbColor)
            }

            // The words to read aloud
            Text(section.text)
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
                .fill(section.mood.orbColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(section.mood.orbColor.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: - Success State

    private var successView: some View {
        VStack(spacing: 40) {
            Spacer()

            // Checkmark with soft green halo
            ZStack {
                Circle()
                    .fill(Color(hex: "4ADE80").opacity(0.08))
                    .frame(width: 180, height: 180)

                Circle()
                    .stroke(Color(hex: "4ADE80").opacity(0.2), lineWidth: 1.5)
                    .frame(width: 180, height: 180)

                Image(systemName: "checkmark")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(Color(hex: "4ADE80"))
            }

            VStack(spacing: 16) {
                Text("Profile Created")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)

                Text("Your voice is ready to tell stories.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)

                // Lock badge — animates in once SecureStorageService confirms the
                // Keychain write. Proves the encryption handshake is complete.
                if secureStorage.hasVoiceProfile {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "4ADE80"))

                        Text("Encrypted & Secured")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color(hex: "4ADE80").opacity(0.85))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.5, bounce: 0.2), value: secureStorage.hasVoiceProfile)

            // Enter Library — enabled only after SecureStorageService confirms the write.
            // Prevents navigation before the voice profile is durably stored.
            Button {
                showLibrary = true
            } label: {
                Text("Enter the Library")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isComplete)
            .opacity(isComplete ? 1.0 : 0.35)
            .animation(.easeInOut(duration: 0.4), value: isComplete)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func handleOrbTap() {
        guard !audioManager.isRecording, !isComplete else { return }

        Task {
            await audioManager.checkPermission()
            guard audioManager.hasPermission else { return }

            hasStarted = true
            progress = 0.0
            audioManager.startRecording()
            startProgressTimer()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                progress = min(progress + 0.1 / sessionDuration, 1.0)
            }
        }
    }

    private func finishRecording() {
        progressTimer?.invalidate()
        progressTimer = nil

        withAnimation(.easeInOut(duration: 0.5)) {
            progress = 1.0
        }

        // Let the bar visibly complete, then bloom the success view.
        // Encryption starts immediately after — the lock icon animates in
        // independently once SecureStorageService.hasVoiceProfile flips to true.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
                isComplete = true
            }

            Task { @MainActor in
                await encryptAndStore()
            }
        }
    }

    /// Reads the raw audio file produced by AudioInputManager and passes the bytes
    /// directly to SecureStorageService.saveVoiceProfile(_:).
    ///
    /// Execution order inside saveVoiceProfile (verified against SecureStorageService):
    ///   1. loadOrCreateSEKey()  — SE key is generated before any Keychain write
    ///   2. ECDH + HKDF          — AES-256-GCM key derived from the shared secret
    ///   3. AES.GCM.seal         — data encrypted with a fresh random nonce
    ///   4. keychainSave × 3     — nonce, ciphertext, ephemeral key written to Keychain
    ///   5. hasVoiceProfile = true — triggers the lock icon in the success view
    @MainActor
    private func encryptAndStore() async {
        guard let audioURL = audioManager.recordedAudioURL else { return }

        do {
            let audioData = try Data(contentsOf: audioURL)
            try secureStorage.saveVoiceProfile(audioData)
        } catch {
            print("[SecureStorageService] Encryption failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecordingView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
