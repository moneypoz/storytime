import Foundation

// MARK: - Story Script

/// A complete story with prosody-tagged text for expressive TTS playback.
/// `taggedText` is the canonical representation consumed by the voice engine.
/// `segments` are pre-parsed for UI rendering and progressive text highlighting.
struct StoryScript: Hashable {

    let title: String
    let taggedText: String
    let segments: [Segment]

    // MARK: - Hashable

    static func == (lhs: StoryScript, rhs: StoryScript) -> Bool { lhs.title == rhs.title }
    func hash(into hasher: inout Hasher) { hasher.combine(title) }

    // MARK: - Segment

    struct Segment: Identifiable, Hashable {
        let id = UUID()
        let mood: Mood
        let text: String

        static func == (lhs: Segment, rhs: Segment) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        // MARK: - Mood

        /// Voice modulation hint for the TTS engine.
        /// Maps directly to the `mood` attribute in `<voice mood='...'>` prosody tags.
        enum Mood: String {
            case excited
            case normal
            case sleepy

            /// TTS speech rate multiplier
            var rate: Double {
                switch self {
                case .excited: return 1.15
                case .normal:  return 1.0
                case .sleepy:  return 0.85
                }
            }

            /// TTS pitch multiplier
            var pitch: Double {
                switch self {
                case .excited: return 1.1
                case .normal:  return 1.0
                case .sleepy:  return 0.9
                }
            }
        }
    }
}

// MARK: - Preloaded Library

/// Catalog of stories bundled with every install.
/// Featured books are free (`isPremium: false`) and appear first in the library carousel.
enum PreloadedLibrary {

    // MARK: - The Lion and the Mouse (Featured Free · Aesop)

    static let lionAndMouse = StoryScript(
        title: "The Lion and the Mouse",
        taggedText: """
        <voice mood='normal'>A mighty lion lay sleeping in the forest when a little mouse scurried across his paw. The Lion awoke with a terrible roar and pinned the tiny creature under his great claw.</voice>
        <voice mood='excited'>"How dare you wake me!" roared the Lion. "I shall eat you for this!" "Oh please, great Lion!" squeaked the Mouse. "Spare my life, and one day I may repay your kindness!" The Lion laughed, for what could a tiny mouse do for a great king? But he was amused, and set the Mouse free.</voice>
        <voice mood='normal'>Not long after, the Lion fell into a hunter's net. He struggled and roared, but the ropes held fast. The little Mouse heard the Lion's cries and hurried to his side.</voice>
        <voice mood='excited'>"Be still, dear Lion," said the Mouse. "I will help you." With his small sharp teeth, the Mouse gnawed through the ropes — one by one — until the Lion was free.</voice>
        <voice mood='sleepy'>"You laughed when I promised to repay you," said the Mouse with a gentle smile. "Now you see: even the smallest friend can be the greatest help." And so they walked together, into the peaceful forest, as the stars began to appear.</voice>
        """,
        segments: [
            .init(
                mood: .normal,
                text: "A mighty lion lay sleeping in the forest when a little mouse scurried across his paw. The Lion awoke with a terrible roar and pinned the tiny creature under his great claw."
            ),
            .init(
                mood: .excited,
                text: "\"How dare you wake me!\" roared the Lion. \"I shall eat you for this!\" \"Oh please, great Lion!\" squeaked the Mouse. \"Spare my life, and one day I may repay your kindness!\" The Lion laughed, for what could a tiny mouse do for a great king? But he was amused, and set the Mouse free."
            ),
            .init(
                mood: .normal,
                text: "Not long after, the Lion fell into a hunter's net. He struggled and roared, but the ropes held fast. The little Mouse heard the Lion's cries and hurried to his side."
            ),
            .init(
                mood: .excited,
                text: "\"Be still, dear Lion,\" said the Mouse. \"I will help you.\" With his small sharp teeth, the Mouse gnawed through the ropes — one by one — until the Lion was free."
            ),
            .init(
                mood: .sleepy,
                text: "\"You laughed when I promised to repay you,\" said the Mouse with a gentle smile. \"Now you see: even the smallest friend can be the greatest help.\" And so they walked together, into the peaceful forest, as the stars began to appear."
            )
        ]
    )
}
