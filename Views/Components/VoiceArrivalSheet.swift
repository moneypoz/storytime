import SwiftUI

/// Shown automatically when a new shared voice profile finishes downloading.
///
/// Triggered by FamilySyncManager.shared.syncedProfiles gaining a new entry —
/// not by a tap, because iOS handles the accept/decline decision at the system
/// level before the app receives userDidAcceptCloudKitShareWith.
struct VoiceArrivalSheet: View {

    let profile: SharedVoiceProfile
    var onActivate: () -> Void
    var onDismiss:  () -> Void

    private enum Phase { case arrival, success }

    @State private var phase:      Phase   = .arrival
    @State private var orbScale:   CGFloat = 0.6
    @State private var orbOpacity: Double  = 0.0
    @State private var textVisible: Bool   = false

    var body: some View {
        ZStack {
            background

            switch phase {
            case .arrival:
                VStack(spacing: 0) {
                    Spacer()

                    orbSection
                        .padding(.bottom, 40)

                    textSection
                        .padding(.bottom, 52)
                        .padding(.horizontal, 40)

                    actionButtons
                        .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 48)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            case .success:
                SyncSuccessView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .onAppear { animateEntrance() }
    }

    // MARK: - Background

    private var background: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                .init(0.0, 0.5), .init(0.5, 0.5), .init(1.0, 0.5),
                .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
            ],
            colors: [
                Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b"),
                Color(hex: "0f172a"), Color(hex: "2d1b69"), Color(hex: "312e81"),
                Color(hex: "020617"), Color(hex: "0f172a"), Color(hex: "1e1b4b")
            ]
        )
        .ignoresSafeArea()
    }

    // MARK: - Orb

    private var orbSection: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color(hex: "6366f1").opacity(0.12 - Double(i) * 0.03), lineWidth: 1)
                    .frame(width: CGFloat(140 + i * 36), height: CGFloat(140 + i * 36))
            }

            // Glass orb
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 116, height: 116)
                    .glassEffect(.regular, in: Circle())

                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.pulse, isActive: true)
            }
        }
        .scaleEffect(orbScale)
        .opacity(orbOpacity)
    }

    // MARK: - Text

    private var textSection: some View {
        VStack(spacing: 14) {
            Text("New Voice Arrived")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("\(profile.ownerName) shared **\(profile.voiceName)** with you.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Privacy badge
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "4ADE80"))

                Text("End-to-end encrypted via iCloud")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(hex: "4ADE80").opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 4)
        }
        .opacity(textVisible ? 1 : 0)
        .offset(y: textVisible ? 0 : 12)
        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.25), value: textVisible)
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: 14) {
            // Primary: activate this voice now
            Button {
                onActivate()
                withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                    phase = .success
                }
                // Auto-dismiss after the checkmark animation finishes (~1.5 s total)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onDismiss()
                }
            } label: {
                Text("Use This Voice")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)

            // Secondary: save for later
            Button("Later", action: onDismiss)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .opacity(textVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.4).delay(0.4), value: textVisible)
    }

    // MARK: - Entrance animation

    private func animateEntrance() {
        withAnimation(.spring(duration: 0.7, bounce: 0.35)) {
            orbScale   = 1.0
            orbOpacity = 1.0
        }
        // Slight delay so orb lands before text fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            textVisible = true
        }
    }
}

// MARK: - Preview

#Preview {
    VoiceArrivalSheet(
        profile: SharedVoiceProfile(
            id: "preview",
            voiceName: "Sarah Expressive",
            ownerName: "Mike",
            filePath: "/tmp/preview.wav",
            receivedAt: .now
        ),
        onActivate: {},
        onDismiss:  {}
    )
    .preferredColorScheme(.dark)
}
