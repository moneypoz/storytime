import CoreData
import SwiftUI

/// A Liquid Glass book card with refractive material effect
/// Designed for the library carousel with iOS 18+ glass effects
struct LiquidGlassCard: View {

    // MARK: - Properties

    let book: Book
    let isActive: Bool

    // MARK: - Progress

    @FetchRequest private var progressRecords: FetchedResults<PlaybackProgress>

    let voiceName: String?

    init(book: Book, isActive: Bool, voiceName: String? = nil) {
        self.book      = book
        self.isActive  = isActive
        self.voiceName = voiceName
        // Scoped fetch — only the record for this specific book
        _progressRecords = FetchRequest(
            entity: PlaybackProgress.entity(),
            sortDescriptors: [],
            predicate: NSPredicate(format: "bookID == %@", book.id)
        )
    }

    private var savedProgress: Double? {
        guard let record = progressRecords.first,
              !record.isFinished,
              record.segmentIndex > 0
        else { return nil }

        // Use the actual segment count when the book has a bundled script;
        // fall back to a fixed denominator for future non-preloaded books.
        let total = book.script.map { Double($0.segments.count) } ?? 20.0
        guard total > 0 else { return nil }
        return min(Double(record.segmentIndex) / total, 0.95)
    }

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

            // Layer 5: Resume arc — shown only when in-progress
            if let p = savedProgress {
                resumeArc(progress: p)
            }

            // Layer 6: Voice badge — shown when a shared family voice is active
            if let name = voiceName {
                voiceBadge(name: name)
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

    // MARK: - Resume Arc

    /// Thin circular arc in the top-right corner indicating partially-listened progress.
    private func resumeArc(progress: Double) -> some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    // Track
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 28, height: 28)

                    // Fill arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(14)
                // Offset below premium badge if both are present; badge sits at the same corner
                .padding(.top, book.isPremium ? 40 : 0)
            }
            Spacer()
        }
    }

    // MARK: - Voice Badge

    private func voiceBadge(name: String) -> some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "6366f1"))

                    Text(name)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
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
    .environment(
        \.managedObjectContext,
        PersistenceController.preview.container.viewContext
    )
}
