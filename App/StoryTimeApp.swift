import CoreData
import SwiftUI
import VoiceboxCore

@main
struct StoryTimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var familySync = FamilySyncManager.shared

    init() {
        // Start the Tokio runtime that backs all async Rust calls.
        // Must be called once before any UniFFI async function is awaited.
        setupTokioRuntime()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if appState.hasCompletedOnboarding {
                    HomeView()
                } else {
                    WelcomeView()
                }
            }
            .environmentObject(appState)
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .preferredColorScheme(.dark)
            .fullScreenCover(item: $familySync.pendingArrival) { profile in
                VoiceArrivalSheet(
                    profile: profile,
                    onActivate: {
                        familySync.activateProfile(profile)
                        familySync.pendingArrival = nil
                    },
                    onDismiss: { familySync.pendingArrival = nil }
                )
            }
            .task {
                // If the model is already on disk (returning user), load it
                // immediately so VoiceboxService is ready before the first
                // story is opened.  New users go through download → RecordingView
                // → the load triggered there instead.
                let manager = ModelManager()
                guard manager.isModelReady else { return }
                try? await VoiceboxService.shared.load(modelPath: manager.modelDirectory)

                // Register the voice profile so TTSPlayer uses Voicebox,
                // not the AVSpeechSynthesizer fallback.
                let profilePath = manager.voiceProfilePath()
                if FileManager.default.fileExists(atPath: profilePath) {
                    VoiceboxService.shared.setVoiceProfile(path: profilePath)
                }
            }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("householdID") var householdID: String = ""

    func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.5)) {
            hasCompletedOnboarding = true
        }
    }
}
