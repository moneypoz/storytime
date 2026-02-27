import SwiftUI

/// Animated circle + checkmark shown briefly after a voice profile is activated.
/// Designed to sit on the app's dark MeshGradient background — transparent background.
struct SyncSuccessView: View {

    private let accent = Color(hex: "6366f1")

    @State private var circleStroke:   CGFloat = 0.0
    @State private var checkmarkStroke: CGFloat = 0.0
    @State private var labelVisible:   Bool    = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Soft glow behind the ring
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 148, height: 148)
                    .blur(radius: 20)

                // Completion ring
                Circle()
                    .trim(from: 0, to: circleStroke)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                // Checkmark
                CheckmarkShape()
                    .trim(from: 0, to: checkmarkStroke)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 52, height: 52)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.65)) {
                    circleStroke = 1.0
                }
                withAnimation(.easeOut(duration: 0.35).delay(0.65)) {
                    checkmarkStroke = 1.0
                }
                withAnimation(.easeIn(duration: 0.3).delay(0.9)) {
                    labelVisible = true
                }
            }

            Text("Voice Synced!")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(labelVisible ? 1 : 0)
        }
    }
}

// MARK: - CheckmarkShape

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.74))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.28))
        return path
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "020617").ignoresSafeArea()
        SyncSuccessView()
    }
    .preferredColorScheme(.dark)
}
