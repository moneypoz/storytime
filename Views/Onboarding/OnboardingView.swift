import SwiftUI

/// Parent voice recording onboarding — paging TabView, one script section per page.
/// The Next button unlocks after the Record orb has been pressed on each page.
struct OnboardingView: View {

    // MARK: - Environment

    @EnvironmentObject private var appState: AppState

    // MARK: - State Objects

    @StateObject private var audioManager = AudioInputManager()
    @StateObject private var voiceTokenizer = VoiceTokenizer()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var progressTracker = ScriptProgressTracker()

    // MARK: - State

    @State private var currentPage = 0
    @State private var hasRecordedPage: Set<Int> = []
    @State private var showingPermissionAlert = false
    @State private var processingComplete = false
    @State private var showSuccessView = false
    @State private var showLibrary = false

    private let sections = ExpressiveScript.sections

    // MARK: - Body

    var body: some View {
        ZStack {
            if showSuccessView {
                SuccessView(showLibrary: $showLibrary)
                    .transition(.opacity)
            } else {
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
            progressTracker.updateProgress(from: speechRecognizer)
        }
        .onChange(of: showLibrary) { _, isShowing in
            if isShowing { appState.completeOnboarding() }
        }
    }

    // MARK: - Onboarding Content

    private var onboardingContent: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            StarsBackground()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 50)
                    .padding(.bottom, 16)

                // Paging carousel — one section per page
                TabView(selection: $currentPage) {
                    ForEach(sections.indices, id: \.self) { index in
                        scriptPage(for: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                // Next / Done button — fixed below the carousel
                nextButton
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Script Page

    @ViewBuilder
    private func scriptPage(for index: Int) -> some View {
        let section = sections[index]

        VStack(spacing: 20) {
            // Script card (always shown as active since it owns the page)
            ScriptSectionView(
                section: section,
                isActive: true,
                isComplete: progressTracker.sectionCompletions[section.mood] ?? 0 >= 1.0,
                completion: progressTracker.sectionCompletions[section.mood] ?? 0
            )
            .padding(.horizontal, 24)

            // Record orb
            GlowingOrbButton(
                audioLevel: audioManager.audioLevel,
                isRecording: audioManager.isRecording && currentPage == index,
                moodColor: section.mood.orbColor,
                glowColor: section.mood.glowColor
            ) {
                handleOrbTap(for: index)
            }

            // Mood direction
            Text(section.mood.direction)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Inline status (only when relevant to this page)
            if audioManager.isRecording && currentPage == index {
                recordingIndicator(for: section)
            } else if voiceTokenizer.isProcessing && index == sections.count - 1 {
                processingIndicator
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Next / Done Button

    private var nextButton: some View {
        let isLast = currentPage == sections.count - 1
        let canAdvance = hasRecordedPage.contains(currentPage)
        let section = sections[currentPage]

        return Button {
            advancePage(isLast: isLast)
        } label: {
            HStack(spacing: 10) {
                Text(isLast ? "Done" : "Next")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                if !isLast {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(canAdvance ? .white : .white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(canAdvance
                        ? AnyShapeStyle(LinearGradient(
                            colors: [section.mood.orbColor, section.mood.glowColor],
                            startPoint: .leading,
                            endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.1)))
            )
        }
        .disabled(!canAdvance)
        .buttonStyle(ScaleButtonStyle())
        .animation(.easeInOut(duration: 0.25), value: canAdvance)
    }

    // MARK: - Status Indicators

    private func recordingIndicator(for section: ExpressiveScript.Section) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progressTracker.sectionCompletions[section.mood] ?? 0)
                .tint(section.mood.orbColor)
                .padding(.horizontal, 60)

            Text("Recording…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var processingIndicator: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(sections.last?.mood.orbColor ?? .white)
            Text("Creating your voice profile…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    // MARK: - Header / Background

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

    // MARK: - Actions

    private func handleOrbTap(for pageIndex: Int) {
        if audioManager.isRecording {
            audioManager.stopRecording()
            speechRecognizer.stopListening()
        } else {
            // Mark this page as recorded — unlocks the Next button
            hasRecordedPage.insert(pageIndex)
            Task { await checkPermissionsAndStart(for: pageIndex) }
        }
    }

    private func advancePage(isLast: Bool) {
        if audioManager.isRecording {
            audioManager.stopRecording()
            speechRecognizer.stopListening()
        }
        if isLast {
            completeOnboarding()
        } else {
            withAnimation {
                currentPage += 1
            }
        }
    }

    private func checkPermissionsAndStart(for pageIndex: Int) async {
        await audioManager.checkPermission()
        await speechRecognizer.checkPermissions()

        if audioManager.hasPermission && speechRecognizer.hasPermission {
            progressTracker.currentMoodIndex = pageIndex
            audioManager.startRecording()
            speechRecognizer.startListening()
        } else {
            showingPermissionAlert = true
        }
    }

    private func completeOnboarding() {
        audioManager.stopRecording()
        speechRecognizer.stopListening()

        if let audioURL = audioManager.recordedAudioURL {
            Task {
                try? await voiceTokenizer.tokenize(audioURL: audioURL)
                processingComplete = true
                withAnimation(.easeInOut(duration: 0.5)) { showSuccessView = true }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.5)) { showSuccessView = true }
        }
    }
}

// MARK: - Script Section View (unchanged)

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
        .animation(.spring(duration: 0.3), value: isActive)
        .animation(.easeInOut(duration: 0.3), value: isComplete)
    }

    private var headerColor: Color {
        if isComplete { return .white }
        if isActive   { return section.mood.orbColor }
        return .white.opacity(0.4)
    }

    private var textColor: Color {
        if isComplete { return .white.opacity(0.9) }
        if isActive   { return .white.opacity(0.8) }
        return .white.opacity(0.35)
    }

    private var cardBackground: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(LinearGradient(
                colors: [section.mood.orbColor.opacity(0.15), section.mood.orbColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            return AnyShapeStyle(Color.white.opacity(0.03))
        }
    }

    private var borderColor: Color {
        if isComplete { return .green.opacity(0.5) }
        if isActive   { return section.mood.orbColor.opacity(0.6) }
        return .white.opacity(0.1)
    }
}

// MARK: - Stars Background (unchanged)

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
