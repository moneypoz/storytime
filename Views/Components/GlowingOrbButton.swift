import SwiftUI

/// A glowing orb button that pulses in response to audio input
/// Changes color based on current mood: Orange (Excited), Green (Normal), Blue (Sleepy)
struct GlowingOrbButton: View {

    // MARK: - Properties

    let audioLevel: Float
    let isRecording: Bool
    var moodColor: Color = DesignSystem.primaryPurple
    var glowColor: Color = DesignSystem.softPink
    let action: () -> Void

    // MARK: - State

    @State private var isPulsing = false
    @State private var glowIntensity: CGFloat = 0.5
    @State private var colorTransition: CGFloat = 0

    // MARK: - Constants

    private let baseSize: CGFloat = 160
    private let maxGlowRadius: CGFloat = 40

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow rings (responsive to audio)
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(outerGlowGradient)
                        .frame(width: orbSize(for: index), height: orbSize(for: index))
                        .opacity(ringOpacity(for: index))
                        .blur(radius: CGFloat(index + 1) * 8)
                }

                // Main orb
                Circle()
                    .fill(orbGradient)
                    .frame(width: baseSize, height: baseSize)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: moodColor.opacity(0.8), radius: currentGlowRadius)

                // Inner highlight
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.4), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: baseSize / 2
                        )
                    )
                    .frame(width: baseSize * 0.8, height: baseSize * 0.8)
                    .offset(x: -20, y: -20)

                // Center icon
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: isRecording)
            }
        }
        .buttonStyle(OrbButtonStyle())
        .onChange(of: audioLevel) { _, newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                glowIntensity = CGFloat(0.5 + newLevel * 0.5)
            }
        }
        .onChange(of: isRecording) { _, recording in
            withAnimation(DesignSystem.pulseAnimation) {
                isPulsing = recording
            }
        }
        .animation(.easeInOut(duration: 0.5), value: moodColor)
        .animation(.easeInOut(duration: 0.5), value: glowColor)
    }

    // MARK: - Computed Properties

    private var orbGradient: RadialGradient {
        RadialGradient(
            colors: [
                moodColor.opacity(0.85),
                moodColor,
                moodColor.saturated(by: 0.2)
            ],
            center: .center,
            startRadius: 0,
            endRadius: baseSize / 2
        )
    }

    private var outerGlowGradient: RadialGradient {
        RadialGradient(
            colors: [
                glowColor.opacity(0.6),
                moodColor.opacity(0.4),
                .clear
            ],
            center: .center,
            startRadius: baseSize / 4,
            endRadius: baseSize
        )
    }

    private var currentGlowRadius: CGFloat {
        isRecording ? maxGlowRadius * glowIntensity : maxGlowRadius * 0.3
    }

    private func orbSize(for index: Int) -> CGFloat {
        let audioBoost = isRecording ? CGFloat(audioLevel) * 30 : 0
        return baseSize + CGFloat(index + 1) * 30 + audioBoost
    }

    private func ringOpacity(for index: Int) -> Double {
        let baseOpacity = 0.3 - Double(index) * 0.08
        let audioBoost = isRecording ? Double(audioLevel) * 0.3 : 0
        return baseOpacity + audioBoost
    }
}

// MARK: - Color Extension for Saturation

extension Color {
    func saturated(by amount: Double) -> Color {
        // Darken the color slightly for depth
        return self.opacity(1.0 - amount)
    }
}

// MARK: - Button Style

struct OrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Default Purple") {
    ZStack {
        DesignSystem.backgroundGradient
            .ignoresSafeArea()

        GlowingOrbButton(
            audioLevel: 0.5,
            isRecording: true
        ) {}
    }
}

#Preview("Excited - Orange") {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()

        GlowingOrbButton(
            audioLevel: 0.6,
            isRecording: true,
            moodColor: ExpressiveScript.Mood.excited.orbColor,
            glowColor: ExpressiveScript.Mood.excited.glowColor
        ) {}
    }
}

#Preview("Normal - Green") {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()

        GlowingOrbButton(
            audioLevel: 0.4,
            isRecording: true,
            moodColor: ExpressiveScript.Mood.normal.orbColor,
            glowColor: ExpressiveScript.Mood.normal.glowColor
        ) {}
    }
}

#Preview("Sleepy - Blue") {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()

        GlowingOrbButton(
            audioLevel: 0.3,
            isRecording: true,
            moodColor: ExpressiveScript.Mood.sleepy.orbColor,
            glowColor: ExpressiveScript.Mood.sleepy.glowColor
        ) {}
    }
}
