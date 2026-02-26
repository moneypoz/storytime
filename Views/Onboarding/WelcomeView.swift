import SwiftUI

// MARK: - Page Data

private struct WelcomePage {
    let icon: String
    let headline: String
    let body: String
}

private let welcomePages: [WelcomePage] = [
    // Act 1 — The Vision
    WelcomePage(
        icon: "wand.and.stars",
        headline: "Your voice.\nTheir magic.",
        body: "Bring stories to life with a voice they know and love."
    ),
    // Act 2 — Privacy First
    WelcomePage(
        icon: "lock.shield.fill",
        headline: "Secure.\nPrivate. Local.",
        body: "Your voice data never leaves your device. It's for your family's ears only."
    ),
    // Act 3 — The Setup (CTA)
    WelcomePage(
        icon: "waveform.and.mic",
        headline: "Let's find your\nstoryteller.",
        body: "We'll record 30 seconds of your voice to create your profile."
    )
]

// MARK: - Mesh Gradient Themes
// File-scope so they can be used as @State default values inside the view struct.

private let meshThemes: [[Color]] = [
    // Act 1 — Midnight navy (calm, dreamlike vision)
    [
        Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b"),
        Color(hex: "0f172a"), Color(hex: "1e1b4b"), Color(hex: "312e81"),
        Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b")
    ],
    // Act 2 — Violet bloom (trustworthy, secure, deep indigo)
    [
        Color(hex: "1e1b4b"), Color(hex: "2d1b69"), Color(hex: "4c1d95"),
        Color(hex: "0f172a"), Color(hex: "3b0764"), Color(hex: "581c87"),
        Color(hex: "020617"), Color(hex: "1e1b4b"), Color(hex: "2d1b69")
    ],
    // Act 3 — Amber warmth (action, energy, leads into recording)
    [
        Color(hex: "1c1917"), Color(hex: "292524"), Color(hex: "1e1b4b"),
        Color(hex: "0f172a"), Color(hex: "431407"), Color(hex: "312e81"),
        Color(hex: "020617"), Color(hex: "1c1917"), Color(hex: "1e1b4b")
    ]
]

private let meshPoints: [SIMD2<Float>] = [
    .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
    .init(0.0, 0.5), .init(0.5, 0.5), .init(1.0, 0.5),
    .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
]

// MARK: - Background Mesh Gradient

private struct BackgroundMeshGradient: View {

    let page: Int

    // Initialised from the file-scope constant — avoids a circular self-reference
    // that would occur if themes were a static member of this struct.
    @State private var colors: [Color] = meshThemes[0]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: meshPoints, colors: colors)
            .ignoresSafeArea()
            .onChange(of: page) { _, newPage in
                // Smoothly cross-fade to the theme for the incoming page.
                withAnimation(.easeInOut(duration: 0.8)) {
                    colors = meshThemes[min(newPage, meshThemes.count - 1)]
                }
            }
    }
}

// MARK: - Glass Effect Card

/// Wraps any content in a 40pt Liquid Glass container.
private struct GlassEffectCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(32)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 40, style: .continuous)
            )
    }
}

// MARK: - Magic Pulse Button

/// "Get Started" CTA — slow-expanding amber rings draw the parent's eye
/// before they tap through to RecordingView.
private struct MagicPulseButton: View {

    @State private var expanding = false

    private let accentColor = Color(hex: "F59E0B") // amber — matches Lion & Mouse cover

    var body: some View {
        NavigationLink(destination: RecordingView()) {
            ZStack {
                // Two concentric pulse rings, staggered by 0.85 s
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(accentColor.opacity(0.45), lineWidth: 1.5)
                        .scaleEffect(expanding ? 1.9 : 1.0)
                        .opacity(expanding ? 0.0 : 0.8)
                        .animation(
                            .easeOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(ring) * 0.85),
                            value: expanding
                        )
                }

                // Pill button — Liquid Glass with interactive style so it
                // responds to the finger press with the native glass squish.
                Text("Get Started")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            // Start pulsing on first render.
            // A brief delay ensures the animation engine has settled.
            expanding = true
        }
    }
}

// MARK: - Welcome Page Content

private struct WelcomePageContent: View {

    let page: WelcomePage
    let isLast: Bool

    var body: some View {
        // Full-screen frame so the TabView page fills the display edge-to-edge.
        VStack {
            Spacer()

            GlassEffectCard {
                VStack(spacing: 28) {
                    // Icon
                    Image(systemName: page.icon)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .white.opacity(0.2), radius: 20)

                    // SF Pro Rounded + .expanded width = SF Liquid feel
                    Text(page.headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .fontWidth(.expanded)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Text(page.body)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    if isLast {
                        MagicPulseButton()
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 28)

            // Reserve space below the card for the page dot indicator.
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {

    @State private var currentPage = 0

    var body: some View {
        ZStack {
            // Mesh background — shifts colour palette on every page change.
            BackgroundMeshGradient(page: currentPage)

            TabView(selection: $currentPage) {
                ForEach(welcomePages.indices, id: \.self) { index in
                    WelcomePageContent(
                        page: welcomePages[index],
                        isLast: index == welcomePages.count - 1
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .statusBarHidden()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WelcomeView()
    }
    .preferredColorScheme(.dark)
}
