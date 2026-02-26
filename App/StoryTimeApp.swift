import SwiftUI

@main
struct StoryTimeApp: App {
    @StateObject private var appState = AppState()

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
            .preferredColorScheme(.dark)
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
