import SwiftUI

/// A Liquid Glass book card with refractive material effect
/// Designed for the library carousel with iOS 18+ glass effects
struct LiquidGlassCard: View {

    // MARK: - Properties

    let book: Book
    let isActive: Bool

    // MARK: - Constants

    static let cardWidth: CGFloat = 280
    static let cardHeight: CGFloat = 400
    private let cornerRadius: CGFloat = 40

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: Base gradient (visible through glass)
            baseGradient

            // Layer 2: Liquid Glass container
            liquidGlassContainer

            // Layer 3: Content overlay
            contentOverlay

            // Layer 4: Premium badge
            if book.isPremium {
                premiumBadge
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Base Gradient

    private var baseGradient: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: book.coverGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Liquid Glass Container

    private var liquidGlassContainer: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                // Refractive edge highlight
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(isActive ? 0.5 : 0.2),
                                .white.opacity(0.1),
                                .white.opacity(isActive ? 0.3 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .overlay(
                // Inner light refraction simulation
                LinearGradient(
                    colors: [
                        .white.opacity(isActive ? 0.15 : 0.08),
                        .clear,
                        .clear,
                        .white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
    }

    // MARK: - Content Overlay

    private var contentOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            // Book icon with glow
            ZStack {
                // Icon glow (active state)
                if isActive {
                    Image(systemName: book.icon)
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                        .blur(radius: 20)
                }

                Image(systemName: book.icon)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
            }

            Spacer()

            // Title area with gradient fade
            titleArea
        }
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
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.horizontal, 24)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        )
                    )
            }
        }
        .frame(height: 90)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(isActive ? 0.5 : 0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .animation(.spring(duration: 0.5, bounce: 0.2), value: isActive)
    }

    // MARK: - Premium Badge

    private var premiumBadge: some View {
        VStack {
            HStack {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .padding(16)
            }
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Liquid Glass Cards") {
    ZStack {
        // Dark background
        Color(hex: "020617").ignoresSafeArea()

        HStack(spacing: 20) {
            LiquidGlassCard(book: Book.samples[0], isActive: false)
                .scaleEffect(0.9)
                .opacity(0.6)

            LiquidGlassCard(book: Book.samples[1], isActive: true)
                .scaleEffect(1.1)
                .shadow(color: .white.opacity(0.25), radius: 30)

            LiquidGlassCard(book: Book.samples[2], isActive: false)
                .scaleEffect(0.9)
                .opacity(0.6)
        }
    }
}
