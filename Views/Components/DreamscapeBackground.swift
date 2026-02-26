import SwiftUI

/// Animated background with slowly moving, color-shifting blurred blobs
/// Creates a dreamy, ethereal atmosphere for the player
struct DreamscapeBackground: View {

    // MARK: - State

    @State private var blobs: [DreamBlob] = DreamBlob.generate(count: 6)
    @State private var animationPhase: CGFloat = 0

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: [
                        Color(hex: "0A0A14"),
                        Color(hex: "12122A"),
                        Color(hex: "0D0D1A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Animated blobs
                ForEach(blobs) { blob in
                    BlobView(
                        blob: blob,
                        phase: animationPhase,
                        bounds: geometry.size
                    )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Animation

    private func startAnimation() {
        withAnimation(
            .linear(duration: 60)
            .repeatForever(autoreverses: false)
        ) {
            animationPhase = 1.0
        }
    }
}

// MARK: - Dream Blob Model

struct DreamBlob: Identifiable {
    let id = UUID()
    let basePosition: CGPoint
    let size: CGFloat
    let color: Color
    let movementRadius: CGFloat
    let speed: CGFloat
    let phaseOffset: CGFloat

    static func generate(count: Int) -> [DreamBlob] {
        let colors: [Color] = [
            Color(hex: "4A3ABA").opacity(0.4),
            Color(hex: "6B5CE7").opacity(0.35),
            Color(hex: "8B7BD8").opacity(0.3),
            Color(hex: "F8B4D9").opacity(0.25),
            Color(hex: "5D4E8C").opacity(0.35),
            Color(hex: "3D2B6B").opacity(0.4)
        ]

        return (0..<count).map { index in
            DreamBlob(
                basePosition: CGPoint(
                    x: CGFloat.random(in: 0.1...0.9),
                    y: CGFloat.random(in: 0.1...0.9)
                ),
                size: CGFloat.random(in: 200...400),
                color: colors[index % colors.count],
                movementRadius: CGFloat.random(in: 50...150),
                speed: CGFloat.random(in: 0.3...0.8),
                phaseOffset: CGFloat.random(in: 0...(.pi * 2))
            )
        }
    }
}

// MARK: - Individual Blob View

struct BlobView: View {
    let blob: DreamBlob
    let phase: CGFloat
    let bounds: CGSize

    var body: some View {
        Ellipse()
            .fill(blob.color)
            .frame(width: blob.size, height: blob.size * 0.8)
            .blur(radius: blob.size * 0.4)
            .position(currentPosition)
            .blendMode(.plusLighter)
    }

    private var currentPosition: CGPoint {
        let angle = (phase * blob.speed * .pi * 2) + blob.phaseOffset
        let offsetX = cos(angle) * blob.movementRadius
        let offsetY = sin(angle * 0.7) * blob.movementRadius

        return CGPoint(
            x: blob.basePosition.x * bounds.width + offsetX,
            y: blob.basePosition.y * bounds.height + offsetY
        )
    }
}

// MARK: - Preview

#Preview {
    DreamscapeBackground()
}
