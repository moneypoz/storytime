import SwiftUI

/// StoryTime Design System
/// Apple Minimalist with Glassmorphism
enum DesignSystem {

    // MARK: - Typography (SF Pro Rounded)

    static let titleFont = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let headlineFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .rounded).weight(.regular)
    static let captionFont = Font.system(.caption, design: .rounded).weight(.medium)

    // MARK: - Colors

    static let primaryPurple = Color(hex: "6B5CE7")
    static let softPink = Color(hex: "F8B4D9")
    static let deepNavy = Color(hex: "1A1B3D")
    static let moonGlow = Color(hex: "FFF9E6")

    // MARK: - Background Gradient

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [deepNavy, Color(hex: "2D2B55")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Animation Timing (Sleepy Mood)

    static let slowTransition: Animation = .easeInOut(duration: 0.5)
    static let pulseAnimation: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)

    // MARK: - Glassmorphism

    static func glassBackground(opacity: Double = 0.15) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Glassmorphism View Modifier

struct GlassMorphism: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}

extension View {
    func glassMorphism(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassMorphism(cornerRadius: cornerRadius))
    }
}
