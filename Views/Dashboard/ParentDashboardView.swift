import SwiftUI
import UIKit

/// Parent dashboard for managing family access, story credits, and privacy settings
/// Features Liquid Glass cards (iOS 26+) with iridescent accents
struct ParentDashboardView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Services

    @StateObject private var storeKit = StoreKitService.shared

    // MARK: - State

    @State private var storiesRemaining: Int = 8
    @State private var storiesTotal: Int = 10
    @State private var onDeviceOnly: Bool = true
    @State private var showingSpouseInvite = false
    @State private var liveParticipants: [FamilyParticipant] = []
    @State private var showingPaywall = false

    // MARK: - Haptics

    private let impactHaptic = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Body

    var body: some View {
        ZStack {
            // Deep blur background
            backgroundLayer
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Header
                    headerSection
                        .padding(.top, 20)

                    // Family Vault
                    familyVaultSection

                    // Story Credits
                    storyCreditsSection

                    // Privacy Shield
                    privacyShieldSection

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .spouseInviteSheet(isPresented: $showingSpouseInvite)
        .task { await loadLiveParticipants() }
        .sheet(isPresented: $showingPaywall) {
            PaywallBottomSheet(selectedBook: nil)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            // Base dark gradient
            LinearGradient(
                colors: [
                    Color(hex: "020617"),
                    Color(hex: "0f172a"),
                    Color(hex: "020617")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle ambient glow
            RadialGradient(
                colors: [
                    Color(hex: "6366f1").opacity(0.08),
                    .clear
                ],
                center: .top,
                startRadius: 100,
                endRadius: 400
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Parent Dashboard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Manage your family's StoryTime")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Family Vault Section

    private var familyVaultSection: some View {
        DashboardCard(title: "Family Vault", icon: "person.2.fill") {
            VStack(spacing: 20) {
                // User Orbs row
                HStack(spacing: 24) {
                    ForEach(displayedFamilyMembers) { member in
                        UserOrb(member: member)
                    }

                    // Add family member button
                    AddUserOrb {
                        impactHaptic.impactOccurred()
                        showingSpouseInvite = true
                    }
                }

                // Shared access info
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "6366f1"))

                    Text("Shared via iCloud Family")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Story Credits Section

    private var storyCreditsSection: some View {
        DashboardCard(title: "Story Credits", icon: "book.fill") {
            VStack(spacing: 16) {
                // Progress Ring
                StoryProgressRing(
                    remaining: storeKit.hasAllAccess ? storiesTotal : storiesRemaining,
                    total: storiesTotal
                )

                // Credits text
                Text("\(storeKit.hasAllAccess ? storiesTotal : storiesRemaining) of \(storiesTotal) stories remaining")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(silverGradient)

                // Get More Stories button
                Button {
                    showingPaywall = true
                } label: {
                    Text("Get More Stories")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(iridescentButtonBackground)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Privacy Shield Section

    private var privacyShieldSection: some View {
        DashboardCard(title: "Privacy Shield", icon: "shield.fill") {
            VStack(spacing: 16) {
                // Privacy toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On-Device Processing Only")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Voice data never leaves this device")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    Toggle("", isOn: $onDeviceOnly)
                        .tint(Color(hex: "4ADE80"))
                        .labelsHidden()
                        .onChange(of: onDeviceOnly) { _, _ in
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                }

                // Privacy indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(onDeviceOnly ? Color(hex: "4ADE80") : Color(hex: "F87171"))
                        .frame(width: 8, height: 8)

                    Text(onDeviceOnly ? "Maximum Privacy Active" : "Cloud Processing Enabled")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white.opacity(0.05), in: Capsule())
            }
        }
    }

    // MARK: - Computed Family Members

    private var displayedFamilyMembers: [FamilyMember] {
        if liveParticipants.isEmpty {
            return FamilyMember.sampleFamily
        } else {
            return liveParticipants.map {
                FamilyMember(
                    name: $0.isOwner ? "Mom" : $0.name,
                    initial: String($0.name.prefix(1)).uppercased(),
                    accentColor: $0.isOwner ? Color(hex: "F472B6") : Color(hex: "60A5FA"),
                    isOwner: $0.isOwner
                )
            }
        }
    }

    // MARK: - Data Loading

    private func loadLiveParticipants() async {
        liveParticipants = (try? await SpouseInviteService.shared.getFamilyMembers()) ?? []
    }

    // MARK: - Gradients

    private var silverGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "A8A8A8"),
                Color(hex: "D4D4D4"),
                Color(hex: "A8A8A8")
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var iridescentButtonBackground: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(hex: "6366f1"),
                    Color(hex: "8B5CF6"),
                    Color(hex: "6366f1")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Pearl-white iridescent overlay
            LinearGradient(
                colors: [
                    .white.opacity(0.3),
                    .clear,
                    .white.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Dashboard Card Container

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "6366f1"))

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.08), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - User Orb

struct UserOrb: View {
    let member: FamilyMember

    @State private var isPressed = false

    var body: some View {
        Button {
            // Handle user selection
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Glow ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    member.accentColor.opacity(0.6),
                                    member.accentColor.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 64, height: 64)
                        .blur(radius: 4)

                    // Main orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    member.accentColor.opacity(0.8),
                                    member.accentColor
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: member.accentColor.opacity(0.5), radius: 10)

                    // Initial or icon
                    Text(member.initial)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text(member.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(OrbPressStyle())
    }
}

// MARK: - Add User Orb

struct AddUserOrb: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Dashed border
                    Circle()
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 56, height: 56)

                    // Plus icon
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text("Invite")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(OrbPressStyle())
    }
}

// MARK: - Story Progress Ring

struct StoryProgressRing: View {
    let remaining: Int
    let total: Int

    private var progress: Double {
        Double(remaining) / Double(total)
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 12)
                .frame(width: 120, height: 120)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "A8A8A8"),
                            Color(hex: "E8E8E8"),
                            Color(hex: "F5F5F5"),
                            Color(hex: "D4D4D4"),
                            Color(hex: "A8A8A8")
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: "D4D4D4").opacity(0.5), radius: 8)

            // Center content
            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Orb Press Button Style

struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Family Member Model

struct FamilyMember: Identifiable {
    let id = UUID()
    let name: String
    let initial: String
    let accentColor: Color
    let isOwner: Bool

    static let sampleFamily: [FamilyMember] = [
        FamilyMember(
            name: "Mom",
            initial: "M",
            accentColor: Color(hex: "F472B6"),
            isOwner: true
        ),
        FamilyMember(
            name: "Dad",
            initial: "D",
            accentColor: Color(hex: "60A5FA"),
            isOwner: false
        )
    ]
}

// MARK: - Preview

#Preview {
    ParentDashboardView()
}
