import SwiftUI

/// A large liquid glass orb that pulses and ripples with audio
/// Uses PhaseAnimator for organic, fluid motion
/// Supports adaptive tinting based on book cover color
struct LiquidGlassOrb: View {

    // MARK: - Properties

    let audioLevel: Float
    let progress: Double
    var accentColor: Color = DesignSystem.primaryPurple

    // MARK: - Constants

    private let orbSize: CGFloat = 240

    // MARK: - Computed Colors

    private var tintedPrimary: Color {
        accentColor
    }

    private var tintedSecondary: Color {
        // Blend accent with soft pink for secondary
        accentColor.opacity(0.6)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Progress ring (glowing, completes with story)
            progressRing

            // Outer ripple layers
            PhaseAnimator([
                OrbPhase(scale: 1.0, blur: 0, opacity: 0.3),
                OrbPhase(scale: 1.05, blur: 2, opacity: 0.2),
                OrbPhase(scale: 1.02, blur: 1, opacity: 0.25)
            ]) { phase in
                rippleLayer(phase: phase, index: 0)
            } animation: { _ in
                .easeInOut(duration: 2.5)
            }

            PhaseAnimator([
                OrbPhase(scale: 1.02, blur: 1, opacity: 0.25),
                OrbPhase(scale: 1.0, blur: 0, opacity: 0.3),
                OrbPhase(scale: 1.04, blur: 1.5, opacity: 0.22)
            ]) { phase in
                rippleLayer(phase: phase, index: 1)
            } animation: { _ in
                .easeInOut(duration: 3.0)
            }

            // Main orb with liquid glass effect
            mainOrb

            // Inner glow responsive to audio
            innerGlow

            // Highlight reflection
            highlightReflection
        }
        .tint(accentColor)
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(
                    colors: [
                        tintedSecondary.opacity(0.8),
                        tintedPrimary.opacity(0.6),
                        tintedSecondary.opacity(0.4),
                        tintedPrimary.opacity(0.8)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: orbSize + 40, height: orbSize + 40)
            .rotationEffect(.degrees(-90))
            .shadow(color: tintedPrimary.opacity(0.6), radius: 8)
            .animation(.easeInOut(duration: 0.5), value: progress)
    }

    // MARK: - Ripple Layer

    private func rippleLayer(phase: OrbPhase, index: Int) -> some View {
        let audioBoost = 1.0 + CGFloat(audioLevel) * 0.1

        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tintedPrimary.opacity(phase.opacity),
                        tintedSecondary.opacity(phase.opacity * 0.5),
                        .clear
                    ],
                    center: .center,
                    startRadius: orbSize * 0.3,
                    endRadius: orbSize * 0.6
                )
            )
            .frame(width: orbSize * 1.3, height: orbSize * 1.3)
            .scaleEffect(phase.scale * audioBoost)
            .blur(radius: phase.blur)
    }

    // MARK: - Main Orb

    private var mainOrb: some View {
        let audioScale = 1.0 + CGFloat(audioLevel) * 0.08

        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        tintedPrimary.opacity(0.3),
                        tintedPrimary.opacity(0.5)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: orbSize
                )
            )
            .frame(width: orbSize, height: orbSize)
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .white.opacity(0.1),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .scaleEffect(audioScale)
            .shadow(
                color: tintedPrimary.opacity(0.4),
                radius: 30 + CGFloat(audioLevel) * 20
            )
            .animation(.easeOut(duration: 0.15), value: audioLevel)
    }

    // MARK: - Inner Glow

    private var innerGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tintedPrimary.opacity(0.2 + Double(audioLevel) * 0.3),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: orbSize * 0.4
                )
            )
            .frame(width: orbSize * 0.6, height: orbSize * 0.6)
            .blur(radius: 20)
            .animation(.easeOut(duration: 0.1), value: audioLevel)
    }

    // MARK: - Highlight Reflection

    private var highlightReflection: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: orbSize * 0.5, height: orbSize * 0.25)
            .offset(x: -orbSize * 0.1, y: -orbSize * 0.3)
            .blur(radius: 8)
    }
}

// MARK: - Phase Model

struct OrbPhase: Equatable {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
}

// MARK: - Preview

#Preview {
    ZStack {
        DreamscapeBackground()

        VStack(spacing: 60) {
            // Default purple
            LiquidGlassOrb(audioLevel: 0.5, progress: 0.65)

            // Green tinted (like a forest book)
            LiquidGlassOrb(
                audioLevel: 0.3,
                progress: 0.4,
                accentColor: Color(hex: "4facfe")
            )
        }
    }
}
