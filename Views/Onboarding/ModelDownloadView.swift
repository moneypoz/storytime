import SwiftUI
import VoiceboxCore

/// Downloads the Qwen3-TTS model with a metallic progress bar.
///
/// Two use-cases:
///   • Onboarding (default) — `onComplete` is nil; transitions to LibraryView
///     and calls `appState.completeOnboarding()` when done.
///   • Dashboard re-download — `onComplete` is provided; dismisses itself and
///     calls the closure so the dashboard can refresh its model-status row.
struct ModelDownloadView: View {

    // MARK: - Init

    /// Called on successful download instead of navigating to LibraryView.
    /// When nil the view navigates to LibraryView (onboarding path).
    var onComplete: (() -> Void)? = nil

    // MARK: - Environment

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: - State Objects

    @StateObject private var manager = ModelManager()

    // MARK: - State

    @State private var progress: Double = 0.0
    @State private var phase: Phase = .downloading
    @State private var errorMessage: String?
    @State private var showLibrary = false

    enum Phase { case downloading, done, failed }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                iconSection
                    .padding(.bottom, 36)

                headlineSection
                    .padding(.bottom, 52)
                    .padding(.horizontal, 40)

                progressSection
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView()
        }
        .onChange(of: showLibrary) { _, isShowing in
            if isShowing { appState.completeOnboarding() }
        }
        .task { await startDownload() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Background

    private var background: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                .init(0.0, 0.5), .init(0.5, 0.5), .init(1.0, 0.5),
                .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
            ],
            colors: [
                Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b"),
                Color(hex: "0f172a"), Color(hex: "1e1b4b"), Color(hex: "312e81"),
                Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b")
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Icon

    private var iconSection: some View {
        let isDone = phase == .done
        let accent = Color(hex: isDone ? "4ADE80" : "6366f1")

        return ZStack {
            Circle()
                .fill(accent.opacity(0.08))
                .frame(width: 148, height: 148)

            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 1)
                .frame(width: 148, height: 148)

            Image(systemName: isDone ? "checkmark" : "arrow.down.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isDone ? Color(hex: "4ADE80") : .white.opacity(0.9))
                .symbolEffect(.pulse, isActive: phase == .downloading)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    // MARK: - Headlines

    private var headlineSection: some View {
        VStack(spacing: 14) {
            Text(phase == .done ? "Ready to tell stories" : "Preparing your storyteller")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: phase)

            Text(phase == .done
                 ? "Your voice model is loaded and ready."
                 : "Downloading once.\nStored privately on your device.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .animation(.easeInOut(duration: 0.3), value: phase)

            if let error = errorMessage {
                VStack(spacing: 14) {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        errorMessage = nil
                        phase = .downloading
                        Task { await startDownload() }
                    }
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: errorMessage != nil)
    }

    // MARK: - Progress Bar

    private var progressSection: some View {
        VStack(spacing: 10) {
            // Metallic bar — identical style to RecordingView's progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(.white.opacity(0.07))

                    // Metallic fill
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
                        .animation(.linear(duration: 0.3), value: progress)

                    // Leading-edge shimmer
                    if progress > 0 && progress < 1 {
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
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
            }
            .frame(height: 3)
            .shadow(color: .white.opacity(0.25), radius: 6)

            // Percentage label
            Text(phase == .done ? "Complete" : "\(Int(progress * 100))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .animation(.easeInOut, value: phase)
        }
    }

    // MARK: - Download

    // TODO: Replace with your production CDN URL before shipping.
    // Host model.safetensors behind HTTPS with a valid TLS cert.
    // Consider CloudFront + S3, Cloudflare R2, or Hugging Face Hub private endpoint.
    private static let modelURL = URL(string: "https://cdn.example.com/storytime/v1/model.safetensors")!

    private func startDownload() async {
        do {
            for try await p in manager.downloadModel(from: Self.modelURL) {
                progress = p
            }

            // Load the engine immediately after download completes
            let modelDir = manager.modelDirectory
            try? await VoiceboxService.shared.load(modelPath: modelDir)

            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .done
                progress = 1.0
            }

            // Let the user see the completion state briefly
            try? await Task.sleep(nanoseconds: 900_000_000)

            if let onComplete {
                dismiss()
                onComplete()
            } else {
                showLibrary = true
            }

        } catch {
            withAnimation {
                phase = .failed
                errorMessage = "Download failed. Check your connection and try again."
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ModelDownloadView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
