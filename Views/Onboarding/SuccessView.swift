import SwiftUI
import UIKit
import AVFoundation

/// Success screen shown after voice recording completes
/// Features magic pulse animation and auto-transition to Library
struct SuccessView: View {

    // MARK: - Bindings

    @Binding var showLibrary: Bool

    // MARK: - State

    @State private var pulseStates: [PulseState] = [
        PulseState(scale: 0.5, opacity: 0),
        PulseState(scale: 0.5, opacity: 0),
        PulseState(scale: 0.5, opacity: 0)
    ]
    @State private var showText = false
    @State private var textShimmer: CGFloat = 0
    @State private var shimmerPlayer: AVAudioPlayer?
    @State private var backgroundBrightness: Double = 0

    // MARK: - Constants

    private let baseOrbSize: CGFloat = 120
    private let pulseColors: [Color] = [
        Color(hex: "6366f1"), // Indigo
        Color(hex: "8B5CF6"), // Purple
        Color(hex: "A78BFA")  // Light purple
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            // Ambient particles
            ParticleField()

            VStack(spacing: 60) {
                Spacer()

                // Magic Pulse Animation
                magicPulseOrb

                // Success Text with Metallic Shimmer
                if showText {
                    successText
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            startMagicPulseAnimation()
            scheduleTransition()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(hex: "020617"),
                    Color(hex: "0f0a1f"),
                    Color(hex: "020617")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Center glow
            RadialGradient(
                colors: [
                    Color(hex: "6366f1").opacity(0.15),
                    .clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )

            // Adaptive light flash - "Magic lighting up the room"
            RadialGradient(
                colors: [
                    Color(hex: "6366f1").opacity(0.4 * backgroundBrightness),
                    Color(hex: "8B5CF6").opacity(0.2 * backgroundBrightness),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )

            // Subtle white bloom overlay
            Color.white
                .opacity(0.08 * backgroundBrightness)
                .blendMode(.plusLighter)
        }
    }

    // MARK: - Magic Pulse Orb

    private var magicPulseOrb: some View {
        ZStack {
            // Ripple circles (expanding outward)
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .aiGlow(vibrancy: .vivid, color: pulseColors[index])
                    .frame(
                        width: baseOrbSize * pulseStates[index].scale,
                        height: baseOrbSize * pulseStates[index].scale
                    )
                    .opacity(pulseStates[index].opacity)
            }

            // Core orb (stable center)
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "6366f1").opacity(0.6),
                                Color(hex: "6366f1").opacity(0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: baseOrbSize * 0.3,
                            endRadius: baseOrbSize * 0.8
                        )
                    )
                    .frame(width: baseOrbSize * 1.5, height: baseOrbSize * 1.5)
                    .blur(radius: 20)

                // Main orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.95),
                                Color(hex: "6366f1").opacity(0.8),
                                Color(hex: "4F46E5")
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: baseOrbSize * 0.6
                        )
                    )
                    .frame(width: baseOrbSize * 0.6, height: baseOrbSize * 0.6)
                    .overlay(
                        // Glass highlight
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .frame(width: baseOrbSize * 0.4, height: baseOrbSize * 0.25)
                            .offset(x: -baseOrbSize * 0.08, y: -baseOrbSize * 0.12)
                            .blur(radius: 4)
                    )
                    .shadow(color: Color(hex: "6366f1").opacity(0.8), radius: 30)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: baseOrbSize * 3, height: baseOrbSize * 3)
    }

    // MARK: - Success Text with Metallic Shimmer

    private var successText: some View {
        VStack(spacing: 12) {
            // Main message
            Text("Your voice is ready.")
                .font(.system(.title, design: .rounded).bold())
                .foregroundStyle(metallicGradient)

            // Subtitle
            Text("Let's tell some stories")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .multilineTextAlignment(.center)
    }

    private var metallicGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "A8A8A8"), location: 0),      // Silver
                .init(color: .white, location: 0.3 + textShimmer),    // Bright
                .init(color: Color(hex: "D4D4D4"), location: 0.5),    // Light silver
                .init(color: .white, location: 0.7 - textShimmer),    // Bright
                .init(color: Color(hex: "B8B8B8"), location: 1)       // Silver
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Animations

    private func startMagicPulseAnimation() {
        // Trigger success haptic - the classic Apple "Tap-Tap" feel
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)

        // Prepare shimmer sound
        prepareShimmerSound()

        // Stagger the pulse animations
        for index in 0..<3 {
            let delay = Double(index) * 0.15

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(duration: 0.8, bounce: 0.4)) {
                    pulseStates[index] = PulseState(
                        scale: 2.5 + CGFloat(index) * 0.5,
                        opacity: 0.8 - Double(index) * 0.2
                    )
                }

                // Fade out the pulse
                withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                    pulseStates[index].opacity = 0
                }
            }
        }

        // Play shimmer sound and flash background at animation peak (~0.4 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            playShimmerSound()

            // Adaptive Light: brighten the room
            withAnimation(.easeOut(duration: 0.15)) {
                backgroundBrightness = 1.0
            }

            // Fade back to normal over 0.5 seconds
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                backgroundBrightness = 0
            }
        }

        // Show text after pulses start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                showText = true
            }

            // Start shimmer animation
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                textShimmer = 0.15
            }
        }
    }

    private func prepareShimmerSound() {
        guard let url = Bundle.main.url(forResource: "shimmer", withExtension: "wav") else {
            return
        }

        do {
            // Configure audio session for playback mixed with others
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            shimmerPlayer = try AVAudioPlayer(contentsOf: url)
            // -12dB = 10^(-12/20) ≈ 0.25 linear volume
            shimmerPlayer?.volume = 0.25
            shimmerPlayer?.prepareToPlay()
        } catch {
            print("Failed to prepare shimmer sound: \(error)")
        }
    }

    private func playShimmerSound() {
        shimmerPlayer?.play()
    }

    private func scheduleTransition() {
        // Auto-transition after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showLibrary = true
        }
    }
}

// MARK: - Pulse State

private struct PulseState {
    var scale: CGFloat
    var opacity: Double
}

// MARK: - Particle Field

struct ParticleField: View {
    @State private var particles: [Particle] = (0..<20).map { _ in Particle() }

    var body: some View {
        GeometryReader { geometry in
            ForEach(particles) { particle in
                Circle()
                    .fill(.white)
                    .frame(width: particle.size, height: particle.size)
                    .position(
                        x: particle.x * geometry.size.width,
                        y: particle.y * geometry.size.height
                    )
                    .opacity(particle.opacity)
                    .blur(radius: particle.size > 2 ? 1 : 0)
            }
        }
        .onAppear {
            animateParticles()
        }
    }

    private func animateParticles() {
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            particles = particles.map { particle in
                var p = particle
                p.opacity = Double.random(in: 0.2...0.6)
                p.y = particle.y + CGFloat.random(in: -0.02...0.02)
                return p
            }
        }
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat = CGFloat.random(in: 0...1)
    var y: CGFloat = CGFloat.random(in: 0...1)
    var size: CGFloat = CGFloat.random(in: 1...3)
    var opacity: Double = Double.random(in: 0.2...0.5)
}

// MARK: - Preview

#Preview {
    SuccessView(showLibrary: .constant(false))
}
