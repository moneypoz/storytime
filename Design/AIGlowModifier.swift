import SwiftUI

// MARK: - AI Glow Vibrancy Levels

enum AIGlowVibrancy {
    case subtle
    case standard
    case vivid

    var blurLayers: [(radius: CGFloat, opacity: Double)] {
        switch self {
        case .subtle:
            return [
                (radius: 8, opacity: 0.3),
                (radius: 16, opacity: 0.2),
                (radius: 24, opacity: 0.1)
            ]
        case .standard:
            return [
                (radius: 10, opacity: 0.4),
                (radius: 20, opacity: 0.3),
                (radius: 35, opacity: 0.15)
            ]
        case .vivid:
            return [
                (radius: 12, opacity: 0.6),
                (radius: 28, opacity: 0.4),
                (radius: 50, opacity: 0.2),
                (radius: 80, opacity: 0.1)
            ]
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .subtle: return 1.5
        case .standard: return 2.0
        case .vivid: return 3.0
        }
    }
}

// MARK: - AI Glow Modifier

struct AIGlowModifier: ViewModifier {
    let vibrancy: AIGlowVibrancy
    let color: Color
    let animated: Bool

    @State private var animationPhase: CGFloat = 0

    func body(content: Content) -> some View {
        ZStack {
            // Layered blurred strokes for glow effect
            ForEach(Array(vibrancy.blurLayers.enumerated()), id: \.offset) { index, layer in
                content
                    .stroke(
                        glowGradient,
                        lineWidth: vibrancy.strokeWidth + CGFloat(index) * 1.5
                    )
                    .blur(radius: layer.radius)
                    .opacity(layer.opacity * (animated ? pulseOpacity(for: index) : 1.0))
            }

            // Core stroke
            content
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.9), color.opacity(0.8), .white.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: vibrancy.strokeWidth
                )
        }
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    animationPhase = 1
                }
            }
        }
    }

    private var glowGradient: LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(0.8),
                color,
                color.opacity(0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func pulseOpacity(for index: Int) -> Double {
        let phase = animationPhase + Double(index) * 0.15
        return 0.7 + sin(phase * .pi) * 0.3
    }
}

// MARK: - Shape Extension

extension Shape {
    func aiGlow(
        vibrancy: AIGlowVibrancy = .standard,
        color: Color = .white,
        animated: Bool = false
    ) -> some View {
        self.modifier(AIGlowModifier(vibrancy: vibrancy, color: color, animated: animated))
    }
}

// MARK: - View Extension for Glow Background

extension View {
    func aiGlowBackground(
        vibrancy: AIGlowVibrancy = .standard,
        color: Color = .white
    ) -> some View {
        self.background(
            ZStack {
                ForEach(Array(vibrancy.blurLayers.enumerated()), id: \.offset) { _, layer in
                    self
                        .blur(radius: layer.radius)
                        .opacity(layer.opacity)
                }
            }
            .foregroundStyle(color)
        )
    }
}

// MARK: - Preview

#Preview("AI Glow - Vivid") {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()

        Circle()
            .aiGlow(vibrancy: .vivid, color: Color(hex: "6366f1"), animated: true)
            .frame(width: 200, height: 200)
    }
}

#Preview("AI Glow - Subtle") {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()

        Circle()
            .aiGlow(vibrancy: .subtle, color: Color(hex: "4ADE80"), animated: false)
            .frame(width: 150, height: 150)
    }
}
