import SwiftUI

/// Main home screen - displays the library
/// Following minimalism rule: One primary action per screen
struct HomeView: View {
    var body: some View {
        LibraryView()
    }
}

#Preview {
    HomeView()
}
