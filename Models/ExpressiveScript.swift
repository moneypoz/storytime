import SwiftUI

/// The 30-second expressive script for voice onboarding
/// Divided into three mood sections: Excited, Normal, Sleepy
struct ExpressiveScript {

    // MARK: - Mood Types

    enum Mood: String, CaseIterable, Identifiable {
        case excited = "Excited"
        case normal = "Normal"
        case sleepy = "Sleepy"

        var id: String { rawValue }

        /// Orb color for each mood
        var orbColor: Color {
            switch self {
            case .excited:
                return Color(hex: "FF6B35") // Warm Orange
            case .normal:
                return Color(hex: "4ADE80") // Fresh Green
            case .sleepy:
                return Color(hex: "7DD3FC") // Soft Blue
            }
        }

        /// Secondary glow color
        var glowColor: Color {
            switch self {
            case .excited:
                return Color(hex: "F97316") // Orange glow
            case .normal:
                return Color(hex: "22C55E") // Green glow
            case .sleepy:
                return Color(hex: "38BDF8") // Blue glow
            }
        }

        /// Emoji indicator
        var emoji: String {
            switch self {
            case .excited: return "🎉"
            case .normal: return "😊"
            case .sleepy: return "😴"
            }
        }

        /// Voice direction for the parent
        var direction: String {
            switch self {
            case .excited:
                return "Read with excitement and energy!"
            case .normal:
                return "Read in your natural, calm voice."
            case .sleepy:
                return "Read slowly and softly, like a lullaby."
            }
        }

        /// Duration in seconds
        var duration: Double {
            switch self {
            case .excited: return 10.0
            case .normal: return 10.0
            case .sleepy: return 10.0
            }
        }
    }

    // MARK: - Script Section

    struct Section: Identifiable {
        let id = UUID()
        let mood: Mood
        let text: String
        let keyPhrases: [String] // Used for speech matching

        /// Text with prosody markers per voice engine spec
        /// Replaces "." with ".." and "?" with "???"
        var formattedText: String {
            text
                .replacingOccurrences(of: ".", with: "..")
                .replacingOccurrences(of: "?", with: "???")
        }
    }

    // MARK: - Script Content

    static let sections: [Section] = [
        // EXCITED (10 seconds) - High energy, adventure
        Section(
            mood: .excited,
            text: "Wow! Guess what? Tonight we're going on the most amazing adventure! Are you ready? Let's go explore the magical forest together!",
            keyPhrases: [
                "wow",
                "guess what",
                "amazing adventure",
                "are you ready",
                "magical forest"
            ]
        ),

        // NORMAL (10 seconds) - Calm narration
        Section(
            mood: .normal,
            text: "The little bear walked along the quiet path. The trees whispered gentle secrets. Birds sang their evening songs as the sun began to set.",
            keyPhrases: [
                "little bear",
                "quiet path",
                "trees whispered",
                "birds sang",
                "sun began to set"
            ]
        ),

        // SLEEPY (10 seconds) - Soft, drowsy lullaby
        Section(
            mood: .sleepy,
            text: "Now close your eyes. The stars are twinkling just for you. Sleep tight, little one. Sweet dreams until morning comes.",
            keyPhrases: [
                "close your eyes",
                "stars are twinkling",
                "sleep tight",
                "sweet dreams",
                "morning comes"
            ]
        )
    ]

    // MARK: - Helpers

    static var totalDuration: Double {
        sections.reduce(0) { $0 + $1.mood.duration }
    }

    static func section(for mood: Mood) -> Section? {
        sections.first { $0.mood == mood }
    }

    static var allKeyPhrases: [String] {
        sections.flatMap { $0.keyPhrases }
    }
}

