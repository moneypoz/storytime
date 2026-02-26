import SwiftUI

/// A glass-effect book card for the library carousel
struct BookCard: View {

    // MARK: - Properties

    let book: Book
    let isActive: Bool

    // MARK: - Constants

    private let cardWidth: CGFloat = 260
    private let cardHeight: CGFloat = 380

    // MARK: - Body

    var body: some View {
        ZStack {
            // Cover gradient background
            RoundedRectangle(cornerRadius: 32)
                .fill(
                    LinearGradient(
                        colors: book.coverGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Glass overlay with content
            VStack(spacing: 0) {
                Spacer()

                // Book icon
                Image(systemName: book.icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.2), radius: 10)

                Spacer()

                // Title area - only visible when active
                titleArea
            }
            .frame(width: cardWidth, height: cardHeight)

            // Premium badge
            if book.isPremium {
                premiumBadge
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 32))
    }

    // MARK: - Title Area

    private var titleArea: some View {
        VStack(spacing: 8) {
            if isActive {
                Text(book.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(isActive ? 0.4 : 0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0
            )
        )
        .animation(DesignSystem.slowTransition, value: isActive)
    }

    // MARK: - Premium Badge

    private var premiumBadge: some View {
        VStack {
            HStack {
                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.moonGlow)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(16)
            }
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        HStack(spacing: 20) {
            BookCard(book: Book.samples[0], isActive: false)
            BookCard(book: Book.samples[1], isActive: true)
        }
    }
}
