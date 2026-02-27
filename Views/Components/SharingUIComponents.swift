import CloudKit
import SwiftUI
import UIKit
import VoiceboxCore

// MARK: - Share Voice Profile Button

/// Reads the current voice profile WAV from disk, uploads it to CloudKit,
/// and presents the native UICloudSharingController (iMessage, AirDrop, etc.).
///
/// Placement: any view where a parent wants to share their recorded voice,
/// e.g. the "Family Vault" card in ParentDashboardView.
struct ShareVoiceProfileButton: View {

    // MARK: - State

    @State private var isPreparing   = false
    @State private var showingShare  = false
    @State private var sharePayload: SharePayload?
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        Button {
            Task { await prepareShare() }
        } label: {
            HStack(spacing: 8) {
                if isPreparing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isPreparing ? "Preparing…" : "Share My Voice")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .sheet(isPresented: $showingShare) {
            if let payload = sharePayload {
                CloudSharingView(
                    share:     payload.share,
                    container: payload.container,
                    isPresented: $showingShare
                )
                .ignoresSafeArea()
            }
        }
        .alert("Sharing Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Prepare

    private func prepareShare() async {
        isPreparing = true
        defer { isPreparing = false }

        do {
            let service = CloudSharingService.shared

            // Ensure zone exists (idempotent)
            if !service.isReady {
                try await service.setupZone()
            }

            // Read the local default voice profile
            let manager = ModelManager()
            let path    = manager.voiceProfilePath()
            guard FileManager.default.fileExists(atPath: path) else {
                errorMessage = "No voice profile found. Record your voice first."
                return
            }

            let wavData = try Data(contentsOf: URL(fileURLWithPath: path))
            let owner   = UIDevice.current.name

            let (_, share) = try await service.createVoiceProfileShare(
                wavData:   wavData,
                voiceName: "My Voice",
                ownerName: owner
            )

            sharePayload = SharePayload(share: share, container: service.container)
            showingShare = true

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Cloud Sharing View (UICloudSharingController wrapper)

/// SwiftUI-compatible wrapper around UICloudSharingController.
///
/// Presents the native iOS sharing surface (iMessage, AirDrop, Mail, …)
/// with the CKShare URL embedded. The share is already saved to CloudKit
/// before this view appears; the controller just distributes the link.
struct CloudSharingView: UIViewControllerRepresentable {

    let share:     CKShare
    let container: CKContainer
    @Binding var isPresented: Bool

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // Only show "Only invited people" — no public link option
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    // MARK: - Coordinator / Delegate

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {

        var parent: CloudSharingView

        init(_ parent: CloudSharingView) { self.parent = parent }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("[CloudSharingView] Failed to save share: \(error.localizedDescription)")
            parent.isPresented = false
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.isPresented = false
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.isPresented = false
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.share[CKShare.SystemFieldKey.title] as? String ?? "Voice Profile"
        }
    }
}

// MARK: - Synced Profiles View

/// Shows all voice profiles received from family members via iCloud share links.
/// Lets the user tap "Use" to activate one as the current narration voice.
struct SyncedProfilesView: View {

    @StateObject private var syncManager = FamilySyncManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if syncManager.syncedProfiles.isEmpty {
                emptyState
            } else {
                ForEach(syncManager.syncedProfiles) { profile in
                    profileRow(for: profile)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: syncManager.syncedProfiles.count)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
            Text("No shared voices yet")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profile row

    private func profileRow(for profile: SharedVoiceProfile) -> some View {
        let isActive = syncManager.activeProfileID == profile.id

        return HStack(spacing: 14) {

            // Avatar
            ZStack {
                Circle()
                    .fill(Color(hex: "6366f1").opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(String(profile.ownerName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "6366f1"))
            }

            // Name / source
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.voiceName)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text("from \(profile.ownerName)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            // Activate button
            Button {
                syncManager.activateProfile(profile)
            } label: {
                Text(isActive ? "Active" : "Use")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(isActive ? Color(hex: "4ADE80") : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        isActive
                            ? AnyShapeStyle(Color(hex: "4ADE80").opacity(0.15))
                            : AnyShapeStyle(Color.white.opacity(0.08)),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .padding(14)
        .background(
            .white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

// MARK: - Private helpers

private struct SharePayload: Identifiable {
    let id    = UUID()
    let share: CKShare
    let container: CKContainer
}
