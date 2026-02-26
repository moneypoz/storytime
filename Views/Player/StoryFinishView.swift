import SwiftUI
import UIKit

// MARK: - Shimmer View Modifier

/// Sweeps an animated white-to-iridescent highlight diagonally across any view.
/// Apply with `.shimmer()` on the target view.
private struct ShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = -0.4

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear,                                     location: max(0.0, phase - 0.25)),
                        .init(color: .white.opacity(0.95),                       location: phase),
                        .init(color: Color(hex: "EDE9FE").opacity(0.65),         location: phase + 0.05),
                        .init(color: Color(hex: "F9A8D4").opacity(0.45),         location: phase + 0.11),
                        .init(color: .white.opacity(0.25),                       location: phase + 0.18),
                        .init(color: .clear,                                     location: min(1.0, phase + 0.45)),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    /// Animates an iridescent shimmer sweep across the view.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Confetti Particle

/// A single glassmorphic confetti particle rendered in the celebration Canvas.
private struct ConfettiParticle {

    let normalizedX: Double     // 0…1 — scaled to canvas width at draw time
    let velocityX: Double       // pts/sec horizontal drift
    let fallSpeed: Double       // pts/sec vertical drop (gravity adds on top)
    let rotationSpeed: Double   // degrees/sec
    let size: CGFloat
    let colorIndex: Int
    let isCircle: Bool          // circle vs. rounded rect
    let delay: Double           // seconds before particle begins falling
    let swayAmplitude: CGFloat  // horizontal sine-wave amplitude in pts
    let swayFrequency: Double   // sine-wave cycles/sec

    /// Generates `count` deterministic particles using a linear-congruential sequence.
    /// No randomness — same burst on every appearance.
    static func generate(count: Int) -> [ConfettiParticle] {
        (0..<count).map { i in
            let d = Double(i)
            return ConfettiParticle(
                normalizedX:    fmod(d * 0.13742 + 0.05, 1.0),
                velocityX:      (fmod(d * 0.27193, 1.0) - 0.5) * 60,
                fallSpeed:      130 + fmod(d * 0.61327, 1.0) * 230,
                rotationSpeed:  (fmod(d * 0.41871, 1.0) - 0.5) * 420,
                size:           4 + fmod(d * 0.50311, 1.0) * 7,
                colorIndex:     Int(fmod(d * 0.31722, 1.0) * 6),
                isCircle:       fmod(d * 0.71148, 1.0) > 0.5,
                delay:          fmod(d * 0.25739, 1.6),
                swayAmplitude:  CGFloat(8 + fmod(d * 0.44901, 1.0) * 22),
                swayFrequency:  0.4 + fmod(d * 0.33178, 1.0) * 1.1
            )
        }
    }
}

// MARK: - Story Finish View

/// Full-screen celebration modal shown when a story ends.
///
/// Embed inside `PlayerView` once `progress >= 1.0`:
/// ```swift
/// StoryFinishView(book: book, onReadAgain: restartPlayer, onFinish: dismissAll)
/// ```
struct StoryFinishView: View {

    // MARK: - Properties

    let book: Book
    let onReadAgain: () -> Void
    let onFinish: () -> Void

    // MARK: - State

    @State private var isVisible = false
    @State private var confettiStart: Date = .now
    @State private var particles: [ConfettiParticle] = []

    // MARK: - Glass Namespace

    @Namespace private var glassNamespace

    // MARK: - Haptics

    private let successHaptic = UINotificationFeedbackGenerator()

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: Dreamscape background (matches PlayerView)
            DreamscapeBackground()
                .ignoresSafeArea()

            // Layer 2: Glassmorphic confetti burst
            confettiLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Layer 3: Central content
            VStack(spacing: 0) {
                Spacer()

                theEndTitle

                Spacer()

                actionButtons
                    .padding(.bottom, 64)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.93)
        .transition(.opacity)
        .onAppear {
            confettiStart = .now
            particles = ConfettiParticle.generate(count: 52)
            successHaptic.notificationOccurred(.success)
            withAnimation(.spring(duration: 0.65, bounce: 0.25)) {
                isVisible = true
            }
        }
    }

    // MARK: - Confetti Layer

    private var confettiLayer: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(confettiStart)
                drawConfetti(into: context, size: size, elapsed: elapsed)
            }
        }
    }

    private func drawConfetti(into context: GraphicsContext, size: CGSize, elapsed: Double) {
        // Glassmorphic iridescent palette
        let palette: [Color] = [
            .white.opacity(0.85),
            Color(hex: "E0D7FF").opacity(0.75),
            Color(hex: "FFD6FA").opacity(0.75),
            Color(hex: "D6F0FF").opacity(0.75),
            Color(hex: "FFFBD6").opacity(0.75),
            Color(hex: "A5F3FC").opacity(0.65),
        ]

        for particle in particles {
            let t = elapsed - particle.delay
            guard t > 0 else { continue }

            let x = particle.normalizedX * size.width
                  + particle.velocityX * t
                  + particle.swayAmplitude * sin(t * particle.swayFrequency * 2 * .pi)
            // Light gravity: y = v₀t + ½·40·t²
            let y = -16 + particle.fallSpeed * t + 20 * t * t

            guard y < size.height + 24 else { continue }

            let fadeIn  = min(1.0, t * 3.5)
            let fadeOut = max(0.0, 1.0 - max(0, y - size.height * 0.68) / (size.height * 0.32))
            let opacity = fadeIn * fadeOut
            guard opacity > 0.01 else { continue }

            let w = particle.size
            let h = particle.isCircle ? w : w * 1.65
            let angle = CGFloat(Angle(degrees: particle.rotationSpeed * t).radians)

            // Rotate each particle around its own center
            let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
            var ctx = context
            ctx.opacity = opacity
            ctx.concatenate(transform)

            // Body (circle or rounded rect)
            let bodyRect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let body: Path = particle.isCircle
                ? Path(ellipseIn: bodyRect)
                : Path(roundedRect: bodyRect, cornerRadius: 2.5)

            ctx.fill(body, with: .color(palette[particle.colorIndex % palette.count]))

            // Catch-light: small white specular highlight — simulates glass catching the light
            let hlRect = CGRect(
                x: -w / 2 + w * 0.12, y: -h / 2 + h * 0.08,
                width: w * 0.32, height: h * 0.22
            )
            ctx.fill(Path(ellipseIn: hlRect), with: .color(.white.opacity(0.65)))
        }
    }

    // MARK: - "The End" Title

    private var theEndTitle: some View {
        VStack(spacing: 14) {
            Text("The End")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                // Iridescent base: lavender → white → rose → white
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "C4B5FD"),
                            .white,
                            Color(hex: "F9A8D4"),
                            Color(hex: "E0D7FF"),
                            .white,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(hex: "8B5CF6").opacity(0.4), radius: 24, y: 8)
                // Animated shimmer sweep on top
                .shimmer()

            Text(book.title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.5)
                .textCase(.uppercase)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    // MARK: - Action Buttons (Liquid Glass Union)

    private var actionButtons: some View {
        // GlassEffectContainer lets the two adjacent .glassEffect circles
        // bleed into each other when spaced ≤ container spacing — achieving
        // the liquid union described in iOS 26 Human Interface Guidelines.
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                glassCircleButton(
                    icon: "arrow.clockwise",
                    label: "Read Again",
                    glassID: "readAgain",
                    action: onReadAgain
                )

                glassCircleButton(
                    icon: "checkmark",
                    label: "Finish",
                    glassID: "finish",
                    action: {
                        // Soft cross-dissolve fade before handing off
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onFinish()
                        }
                    }
                )
            }
        }
    }

    private func glassCircleButton(
        icon: String,
        label: String,
        glassID: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
            }
            // iOS 26 Liquid Glass: circle shape
            .glassEffect(.regular.interactive(), in: .circle)
            // Tag this effect so GlassEffectContainer can merge it with its sibling
            .glassEffectID(glassID, in: glassNamespace)
            .buttonStyle(OrbPressStyle())

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Preview

#Preview("Story Finish — Lion & Mouse") {
    StoryFinishView(
        book: Book.samples[0],
        onReadAgain: {},
        onFinish: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Story Finish — Luna's Dream") {
    StoryFinishView(
        book: Book.samples[1],
        onReadAgain: {},
        onFinish: {}
    )
    .preferredColorScheme(.dark)
}
