import SwiftUI
import UIKit
import VoiceboxCore

/// Horizontal paging library with Liquid Glass cards
/// Background: MeshGradient with Midnight (#020617) and Deep Indigo (#1e1b4b)
/// Cards: Refractive glass material with 1.1x scale when centered
struct LibraryView: View {

    // MARK: - Namespace

    @Namespace private var playerTransition

    // MARK: - State

    @State private var selectedBook: Book?
    @State private var scrolledBookID: Book.ID?
    @State private var isPlayerPresented = false
    @State private var showingDashboard = false
    @State private var showingPaywall = false
    @State private var paywallBook: Book?

    // MARK: - Services

    @StateObject private var storeKit   = StoreKitService.shared
    @StateObject private var familySync = FamilySyncManager.shared

    // MARK: - Haptics

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let longPressHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Properties

    private let books = Book.samples

    // MARK: - Colors

    private let midnight = Color(hex: "020617")
    private let deepIndigo = Color(hex: "1e1b4b")
    private let accentPurple = Color(hex: "6366f1")

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: MeshGradient background
            meshGradientBackground
                .ignoresSafeArea()

            // Layer 2: Ambient glow orbs
            ambientGlowLayer
                .ignoresSafeArea()

            // Layer 3: Library content
            if !isPlayerPresented {
                libraryContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            // Layer 4: Full-screen player modal
            if isPlayerPresented, let book = selectedBook {
                PlayerView(
                    book: book,
                    namespace: playerTransition,
                    onDismiss: dismissPlayer
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingDashboard) {
            ParentDashboardView()
        }
        .sheet(isPresented: $showingPaywall, onDismiss: { paywallBook = nil }) {
            PaywallBottomSheet(selectedBook: paywallBook)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .onAppear {
            hapticGenerator.prepare()
            longPressHaptic.prepare()
            if scrolledBookID == nil {
                scrolledBookID = books.first?.id
            }
        }
        .onChange(of: scrolledBookID) { oldValue, newValue in
            guard oldValue != nil, newValue != nil else { return }
            hapticGenerator.impactOccurred()
            prefetchFirstSegment(for: newValue)
        }
    }

    // MARK: - MeshGradient Background

    private var meshGradientBackground: some View {
        MeshGradient(
            width: 3,
            height: 4,
            points: [
                // Row 0 (top)
                SIMD2<Float>(0.0, 0.0),
                SIMD2<Float>(0.5, 0.0),
                SIMD2<Float>(1.0, 0.0),

                // Row 1
                SIMD2<Float>(0.0, 0.33),
                SIMD2<Float>(0.5, 0.30),
                SIMD2<Float>(1.0, 0.33),

                // Row 2
                SIMD2<Float>(0.0, 0.66),
                SIMD2<Float>(0.5, 0.70),
                SIMD2<Float>(1.0, 0.66),

                // Row 3 (bottom)
                SIMD2<Float>(0.0, 1.0),
                SIMD2<Float>(0.5, 1.0),
                SIMD2<Float>(1.0, 1.0)
            ],
            colors: [
                // Row 0: Midnight across top
                midnight, midnight, midnight,

                // Row 1: Midnight with indigo center bloom
                midnight, deepIndigo.opacity(0.8), midnight,

                // Row 2: Indigo band
                deepIndigo.opacity(0.6), deepIndigo, deepIndigo.opacity(0.6),

                // Row 3: Fade back to midnight
                midnight, deepIndigo.opacity(0.4), midnight
            ]
        )
    }

    // MARK: - Ambient Glow Layer

    private var ambientGlowLayer: some View {
        ZStack {
            // Top-left soft glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentPurple.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -150, y: -100)
                .blur(radius: 60)

            // Bottom-right soft glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [deepIndigo.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 120, y: 300)
                .blur(radius: 50)
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.top, 60)
                .padding(.bottom, 32)

            // Horizontal paging carousel
            bookCarousel

            // Play button
            playButton
                .padding(.top, 48)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack {
            // Centered title
            VStack(spacing: 10) {
                Text("Stories")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                Text("Choose a bedtime adventure..")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Gear floats top-right
            HStack {
                Spacer()
                settingsGearButton
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Settings Gear Button

    private var settingsGearButton: some View {
        VStack(spacing: 4) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())

            Text("Hold for settings")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            longPressHaptic.impactOccurred()
            showingDashboard = true
        }
    }

    // MARK: - Book Carousel

    private var bookCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(books) { book in
                    LiquidGlassCard(
                        book: book,
                        isActive: book.id == scrolledBookID,
                        voiceName: familySync.activeVoiceName
                    )
                    .scrollTransition(.animated(.spring(duration: 0.4, bounce: 0.15))) { content, phase in
                        let scale: CGFloat = phase.isIdentity ? 1.1 : 0.85
                        let opacity: Double = phase.isIdentity ? 1.0 : 0.55
                        return content
                            .scaleEffect(scale)
                            .opacity(opacity)
                    }
                    .matchedGeometryEffect(
                        id: book.id,
                        in: playerTransition,
                        isSource: !isPlayerPresented
                    )
                    .onTapGesture {
                        if storeKit.canPlay(book: book) {
                            presentPlayer(for: book)
                        } else {
                            paywallBook = book
                            showingPaywall = true
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledBookID)
        .safeAreaPadding(.horizontal, 40)
        .scrollClipDisabled()
        .frame(height: cardFrameHeight)
    }

    // MARK: - Play Button

    @ViewBuilder
    private var playButton: some View {
        if let book = books.first(where: { $0.id == scrolledBookID }) {
            Button(action: {
                if storeKit.canPlay(book: book) {
                    presentPlayer(for: book)
                } else {
                    paywallBook = book
                    showingPaywall = true
                }
            }) {
                HStack(spacing: 14) {
                    Image(systemName: book.script != nil ? "book.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))

                    Text(book.script != nil ? "Read Now" : "Play Story")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: book.coverGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: book.coverGradient[0].opacity(0.5), radius: 20, y: 8)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.spring(duration: 0.4), value: scrolledBookID)
        }
    }

    // MARK: - Actions

    private func presentPlayer(for book: Book) {
        selectedBook = book
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            isPlayerPresented = true
        }
    }

    private func dismissPlayer() {
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            isPlayerPresented = false
            selectedBook = nil
        }
    }

    // MARK: - Prefetch

    /// Pre-synthesizes the first segment of the newly centered book so the Voicebox
    /// inference context is warm by the time the user taps Play.
    /// Uses detached utility-priority task — result is intentionally discarded here;
    /// the warm model benefits TTSPlayer's subsequent synthesis calls.
    private func prefetchFirstSegment(for bookID: Book.ID?) {
        guard
            let id = bookID,
            let book = books.first(where: { $0.id == id }),
            let firstSegment = book.script?.segments.first,
            VoiceboxService.shared.isLoaded,
            VoiceboxService.shared.hasVoiceProfile
        else { return }

        Task.detached(priority: .utility) {
            _ = try? await VoiceboxService.shared.synthesize(firstSegment.text)
        }
    }

    // MARK: - Layout Constants

    private var cardFrameHeight: CGFloat {
        LiquidGlassCard.cardHeight * 1.15 // Account for 1.1x scale + shadow
    }
}

// MARK: - Preview

#Preview("Library View") {
    LibraryView()
        .preferredColorScheme(.dark)
}

#Preview("Library - Landscape") {
    LibraryView()
        .preferredColorScheme(.dark)
        .previewInterfaceOrientation(.landscapeLeft)
}
