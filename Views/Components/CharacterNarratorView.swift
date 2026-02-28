import SwiftUI

/// A reactive character bubble that shows the active story speaker (🦁 / 🐭 / 🌿).
///
/// ## Audio reactivity
/// `audioLevel` (0–1, sourced from the 30 fps metering loop in TTSPlayer) drives two
/// simultaneous effects:
///   • The aura ring scales outward — a visible "voice wave" emanating from the character.
///   • The bubble itself scales slightly — the character visually "talks".
///
/// ## Idle breathing
/// When `audioLevel` is near zero (during synthesis gaps between segments), a continuous
/// `repeatForever` animation keeps the bubble alive.  The breathing and audio-reactive
/// scales are additive so they blend smoothly as speaking starts and stops.
///
/// ## Character transitions
/// `.phaseAnimator([0, 1], trigger: emoji)` gives a two-phase spring pop-in each time
/// the speaker changes — no `.id` swap needed.
struct CharacterNarratorView: View {

    // MARK: - Input

    let emoji: String?
    /// Live amplitude from the 30 fps metering loop. Expected range 0–1.
    let audioLevel: CGFloat
    /// Tinted to the book's accent colour.  Defaults to indigo.
    var accentColor: Color = Color(hex: "6366f1")

    // MARK: - Idle breathing

    @State private var breathScale: CGFloat = 1.0

    // MARK: - Layout constants

    /// The outermost frame — must comfortably contain the aura at peak volume.
    private let containerSize: CGFloat = 120
    /// Aura ring at rest.  At max `audioLevel` (×1.4 scale) it reaches ~84 pt,
    /// well inside the 120 pt container.
    private let auraSize: CGFloat      = 60
    /// Bubble at rest.
    private let bubbleSize: CGFloat    = 72

    // MARK: - Derived scales

    /// Audio-reactive growth for the aura (0 → +40 %).
    private var auraScale: CGFloat { 1.0 + audioLevel * 0.4 }
    /// Breathing + audio-reactive growth for the bubble.
    /// Breathing oscillates ±0.06; speaking adds up to +0.15 on top.
    private var bubbleScale: CGFloat  { breathScale + audioLevel * 0.15 }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let emoji {
                // ── Aura ring ──────────────────────────────────────────────────
                // Grows with volume; color-tinted to the active book's accent.
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: auraSize, height: auraSize)
                    .scaleEffect(auraScale)
                    .blur(radius: 6)
                    .animation(.linear(duration: 0.033), value: audioLevel)  // 30 fps

                // ── Main bubble ────────────────────────────────────────────────
                Text(emoji)
                    .font(.system(size: 34))
                    .padding(16)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                    .frame(width: bubbleSize, height: bubbleSize)
                    .scaleEffect(bubbleScale)
                    .animation(.linear(duration: 0.033), value: audioLevel)  // 30 fps
                    // ── Character swap pop-in ──────────────────────────────────
                    .phaseAnimator([0, 1], trigger: emoji) { content, phase in
                        content
                            .scaleEffect(phase == 0 ? 0.7 : 1.0)
                            .opacity(phase == 0 ? 0   : 1.0)
                    } animation: { _ in
                        .spring(response: 0.4, dampingFraction: 0.7)
                    }
            }
        }
        .frame(width: containerSize, height: containerSize)
        .onAppear {
            // Breathing starts at 1.0 and oscillates up to 1.06.
            // The animation runs independently of the audio-reactive scale.
            withAnimation(
                .easeInOut(duration: 2)
                .repeatForever(autoreverses: true)
            ) {
                breathScale = 1.06
            }
        }
    }
}

// MARK: - Preview

#Preview("Audio reactive + transitions") {
    struct Demo: View {
        private let characters: [(String, Color)] = [
            ("🌿", Color(hex: "4ADE80")),
            ("🦁", Color(hex: "F59E0B")),
            ("🐭", Color(hex: "7DD3FC")),
        ]
        @State private var index      = 0
        @State private var audioLevel: CGFloat = 0

        var body: some View {
            ZStack {
                Color(hex: "020617").ignoresSafeArea()

                VStack(spacing: 40) {
                    CharacterNarratorView(
                        emoji:       characters[index].0,
                        audioLevel:  audioLevel,
                        accentColor: characters[index].1
                    )

                    // Simulate audio level with a slider
                    VStack(spacing: 8) {
                        Text("Audio level: \(String(format: "%.2f", audioLevel))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.5))
                        Slider(value: $audioLevel)
                            .padding(.horizontal, 40)
                            .tint(.white)
                    }

                    Button("Next character") {
                        withAnimation {
                            index = (index + 1) % characters.count
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }

    return Demo()
}
