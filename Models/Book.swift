import SwiftUI

struct Book: Identifiable, Hashable {
    let id: UUID
    let title: String
    let coverGradient: [Color]
    let icon: String
    let isPremium: Bool

    static let samples: [Book] = [
        Book(
            id: UUID(),
            title: "Luna's Dream",
            coverGradient: [Color(hex: "667eea"), Color(hex: "764ba2")],
            icon: "moon.stars.fill",
            isPremium: false
        ),
        Book(
            id: UUID(),
            title: "The Brave Little Star",
            coverGradient: [Color(hex: "f093fb"), Color(hex: "f5576c")],
            icon: "star.fill",
            isPremium: true
        ),
        Book(
            id: UUID(),
            title: "Whispers of the Forest",
            coverGradient: [Color(hex: "4facfe"), Color(hex: "00f2fe")],
            icon: "leaf.fill",
            isPremium: true
        ),
        Book(
            id: UUID(),
            title: "The Sleepy Cloud",
            coverGradient: [Color(hex: "a8edea"), Color(hex: "fed6e3")],
            icon: "cloud.moon.fill",
            isPremium: true
        ),
        Book(
            id: UUID(),
            title: "Ocean Lullaby",
            coverGradient: [Color(hex: "5ee7df"), Color(hex: "b490ca")],
            icon: "water.waves",
            isPremium: true
        )
    ]
}
