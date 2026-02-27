import SwiftUI

struct Book: Identifiable, Hashable {
    /// Stable across launches — used as the Core Data / CloudKit key for progress.
    let id: String
    let title: String
    let coverGradient: [Color]
    let icon: String
    let isPremium: Bool
    /// Bundled story text with prosody tags. `nil` for books without preloaded content.
    let script: StoryScript?

    init(
        id: String,
        title: String,
        coverGradient: [Color],
        icon: String,
        isPremium: Bool,
        script: StoryScript? = nil
    ) {
        self.id = id
        self.title = title
        self.coverGradient = coverGradient
        self.icon = icon
        self.isPremium = isPremium
        self.script = script
    }

    static let samples: [Book] = [
        Book(
            id: "lion-and-mouse",
            title: "The Lion and the Mouse",
            coverGradient: [Color(hex: "F59E0B"), Color(hex: "D97706"), Color(hex: "92400E")],
            icon: "pawprint.fill",
            isPremium: false,
            script: PreloadedLibrary.lionAndMouse
        ),
        Book(
            id: "lunas-dream",
            title: "Luna's Dream",
            coverGradient: [Color(hex: "667eea"), Color(hex: "764ba2")],
            icon: "moon.stars.fill",
            isPremium: false
        ),
        Book(
            id: "brave-little-star",
            title: "The Brave Little Star",
            coverGradient: [Color(hex: "f093fb"), Color(hex: "f5576c")],
            icon: "star.fill",
            isPremium: true
        ),
        Book(
            id: "whispers-of-the-forest",
            title: "Whispers of the Forest",
            coverGradient: [Color(hex: "4facfe"), Color(hex: "00f2fe")],
            icon: "leaf.fill",
            isPremium: true
        ),
        Book(
            id: "sleepy-cloud",
            title: "The Sleepy Cloud",
            coverGradient: [Color(hex: "a8edea"), Color(hex: "fed6e3")],
            icon: "cloud.moon.fill",
            isPremium: true
        ),
        Book(
            id: "ocean-lullaby",
            title: "Ocean Lullaby",
            coverGradient: [Color(hex: "5ee7df"), Color(hex: "b490ca")],
            icon: "water.waves",
            isPremium: true
        )
    ]
}
