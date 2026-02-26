import SwiftUI
import StoreKit

/// Premium paywall bottom sheet with soft-sell UX
/// Art section → headline → SubscriptionStoreView → Forever Unlock → Restore
struct PaywallBottomSheet: View {

    // MARK: - Properties

    let selectedBook: Book?

    // MARK: - State

    @StateObject private var storeKit = StoreKitService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPulsing = false

    // MARK: - Colors

    private let midnight = Color(hex: "020617")
    private let deepIndigo = Color(hex: "1e1b4b")

    // MARK: - Body

    var body: some View {
        ZStack {
            // MeshGradient background (identical 3×4 pattern to LibraryView)
            meshGradientBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    artSection
                        .padding(.top, 40)

                    headlineSection

                    subscriptionSection

                    if let forever = storeKit.foreverProduct {
                        foreverUnlockButton(product: forever)
                    }

                    restoreButton

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: storeKit.hasAllAccess) { _, newValue in
            if newValue {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    dismiss()
                }
            }
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

    // MARK: - Art Section

    private var artSection: some View {
        ZStack {
            // Blurred gradient from selected book's cover (or default purple)
            let gradientColors: [Color] = selectedBook?.coverGradient
                ?? [Color(hex: "6366f1"), Color(hex: "8B5CF6")]

            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 220, height: 220)
            .blur(radius: 60)
            .opacity(0.6)

            // Frosted glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)

            // Lock icon with AI glow background + pulse
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .aiGlowBackground(vibrancy: .standard, color: Color(hex: "8B5CF6"))
                .scaleEffect(isPulsing ? 1.06 : 1.0)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
        .onAppear { isPulsing = true }
    }

    // MARK: - Headline

    private var headlineSection: some View {
        VStack(spacing: 4) {
            Text("Unlock Every Story")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("in Your Voice")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        SubscriptionStoreView(groupID: StoreKitService.subscriptionGroupID)
            .subscriptionStoreControlStyle(.prominentPicker)
            .tint(Color(hex: "6366f1"))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: - Forever Unlock Button

    private func foreverUnlockButton(product: Product) -> some View {
        Button {
            Task { try? await storeKit.purchase(product: product) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "infinity")
                    .font(.system(size: 16, weight: .semibold))

                Text("Forever Unlock — \(product.displayPrice)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "6366f1"), Color(hex: "8B5CF6")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color(hex: "6366f1").opacity(0.4), radius: 16, y: 8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(storeKit.isLoading)
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button {
            Task { await storeKit.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Preview

#Preview("Paywall — Premium Book") {
    PaywallBottomSheet(selectedBook: Book.samples[1])
        .presentationDetents([.large])
        .presentationCornerRadius(32)
        .preferredColorScheme(.dark)
}

#Preview("Paywall — No Book") {
    PaywallBottomSheet(selectedBook: nil)
        .presentationDetents([.large])
        .presentationCornerRadius(32)
        .preferredColorScheme(.dark)
}
