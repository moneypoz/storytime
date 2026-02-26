import SwiftUI

/// Parent voice recording onboarding screen with 30-second expressive script
/// Tracks progress through three mood sections: Excited, Normal, Sleepy
struct OnboardingView: View {

    // MARK: - Environment

    @EnvironmentObject private var appState: AppState

    // MARK: - State Objects

    @StateObject private var audioManager = AudioInputManager()
    @StateObject private var voiceTokenizer = VoiceTokenizer()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var progressTracker = ScriptProgressTracker()

    // MARK: - State

    @State private var showingPermissionAlert = false
    @State private var processingComplete = false
    @State private var showSuccessView = false
    @State private var showLibrary = false

    // MARK: - Body

    var body: some View {
        ZStack {
            if showSuccessView {
                // Success view with magic pulse animation
                SuccessView(showLibrary: $showLibrary)
                    .transition(.opacity)
            } else {
                // Main onboarding content
                onboardingContent
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showSuccessView)
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView()
                .transition(.opacity)
        }
        .alert("Microphone & Speech Access", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("StoryTime needs microphone and speech recognition access to capture your voice..")
        }
        .onChange(of: speechRecognizer.recognizedWords) { _, _ in
            // Update progress when new words are recognized
            progressTracker.updateProgress(from: speechRecognizer)
        }
        .onChange(of: progressTracker.isComplete) { _, isComplete in
            if isComplete {
                completeOnboarding()
            }
        }
        .onChange(of: showLibrary) { _, isShowing in
            if isShowing {
                // Mark onboarding as complete when transitioning to library
                appState.completeOnboarding()
            }
        }
    }

    // MARK: - Onboarding Content

    private var onboardingContent: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            // Floating stars decoration
            StarsBackground()

            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.top, 50)
                    .padding(.bottom, 24)

                // Script sections
                ScrollView(showsIndicators: false) {
                    scriptSections
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                // Glowing Orb Button (color changes with mood)
                GlowingOrbButton(
                    audioLevel: audioManager.audioLevel,
                    isRecording: audioManager.isRecording,
                    moodColor: currentMood.orbColor,
                    glowColor: currentMood.glowColor
                ) {
                    handleOrbTap()
                }

                // Current mood indicator
                moodIndicator
                    .padding(.top, 16)

                Spacer()

                // Status section
                statusSection
                    .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Current Mood

    private var currentMood: ExpressiveScript.Mood {
        progressTracker.currentMood
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "020617"),
                Color(hex: "1e1b4b").opacity(0.6),
                Color(hex: "020617")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Your Voice")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Read each section with the matching emotion..")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Script Sections

    private var scriptSections: some View {
        VStack(spacing: 20) {
            ForEach(ExpressiveScript.sections) { section in
                ScriptSectionView(
                    section: section,
                    isActive: progressTracker.currentMood == section.mood,
                    isComplete: progressTracker.sectionCompletions[section.mood] ?? 0 >= 1.0,
                    completion: progressTracker.sectionCompletions[section.mood] ?? 0
                )
            }
        }
    }

    // MARK: - Mood Indicator

    private var moodIndicator: some View {
        HStack(spacing: 8) {
            Text(currentMood.emoji)
                .font(.system(size: 20))

            Text(currentMood.direction)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(duration: 0.4), value: currentMood)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Group {
            if voiceTokenizer.isProcessing {
                processingView
            } else if audioManager.isRecording {
                recordingProgressView
            } else if processingComplete {
                completedView
            } else {
                instructionText
            }
        }
        .animation(.easeInOut(duration: 0.3), value: audioManager.isRecording)
        .animation(.easeInOut(duration: 0.3), value: voiceTokenizer.isProcessing)
    }

    private var instructionText: some View {
        Text("Tap the orb to begin recording")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
    }

    private var recordingProgressView: some View {
        VStack(spacing: 12) {
            // Overall progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ExpressiveScript.Mood.excited.orbColor,
                                    ExpressiveScript.Mood.normal.orbColor,
                                    ExpressiveScript.Mood.sleepy.orbColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressTracker.overallProgress, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 60)

            Text("Recording... \(Int(progressTracker.overallProgress * 100))% complete")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(currentMood.orbColor)

            Text("Creating your voice profile...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text("Your voice stays on this device")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSystem.moonGlow.opacity(0.5))
        }
    }

    private var completedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Voice profile created")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Actions

    private func handleOrbTap() {
        if audioManager.isRecording {
            // Stop recording
            audioManager.stopRecording()
            speechRecognizer.stopListening()

            if progressTracker.isComplete, let audioURL = audioManager.recordedAudioURL {
                Task {
                    try await voiceTokenizer.tokenize(audioURL: audioURL)
                }
            }
        } else {
            // Start recording
            Task {
                await checkPermissionsAndStart()
            }
        }
    }

    private func checkPermissionsAndStart() async {
        await audioManager.checkPermission()
        await speechRecognizer.checkPermissions()

        if audioManager.hasPermission && speechRecognizer.hasPermission {
            progressTracker.reset()
            audioManager.startRecording()
            speechRecognizer.startListening()
        } else {
            showingPermissionAlert = true
        }
    }

    private func completeOnboarding() {
        // Stop recording
        audioManager.stopRecording()
        speechRecognizer.stopListening()

        // Process the voice
        if let audioURL = audioManager.recordedAudioURL {
            Task {
                try await voiceTokenizer.tokenize(audioURL: audioURL)
                processingComplete = true

                // Show success view with magic pulse animation
                withAnimation(.easeInOut(duration: 0.5)) {
                    showSuccessView = true
                }
                // SuccessView handles the 2-second delay and sets showLibrary = true
            }
        }
    }
}

// MARK: - Script Section View

struct ScriptSectionView: View {
    let section: ExpressiveScript.Section
    let isActive: Bool
    let isComplete: Bool
    let completion: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Mood header
            HStack(spacing: 8) {
                Text(section.mood.emoji)
                    .font(.system(size: 16))

                Text(section.mood.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(headerColor)

                Spacer()

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16))
                } else if isActive {
                    // Progress indicator
                    Circle()
                        .trim(from: 0, to: completion)
                        .stroke(section.mood.orbColor, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(-90))
                }
            }

            // Script text
            Text(section.formattedText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: isActive ? 2 : 1)
        )
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.spring(duration: 0.3), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: isComplete)
    }

    private var headerColor: Color {
        if isComplete {
            return .white
        } else if isActive {
            return section.mood.orbColor
        } else {
            return .white.opacity(0.4)
        }
    }

    private var textColor: Color {
        if isComplete {
            return .white.opacity(0.9)
        } else if isActive {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.35)
        }
    }

    private var cardBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        section.mood.orbColor.opacity(0.15),
                        section.mood.orbColor.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color.white.opacity(0.03))
        }
    }

    private var borderColor: Color {
        if isComplete {
            return .green.opacity(0.5)
        } else if isActive {
            return section.mood.orbColor.opacity(0.6)
        } else {
            return .white.opacity(0.1)
        }
    }
}

// MARK: - Stars Background

struct StarsBackground: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<25, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: CGFloat.random(in: 1...3))
                    .position(
                        x: CGFloat(index * 37 % Int(geometry.size.width)),
                        y: CGFloat(index * 53 % Int(geometry.size.height))
                    )
                    .opacity(opacity * Double.random(in: 0.5...1.0))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                opacity = 0.8
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
