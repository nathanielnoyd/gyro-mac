import SwiftUI

/// The backdrop behind the 3D MacBook: a deep navy, like the app icon, fading to
/// black at the edges, with a contact shadow where the model rests.
///
/// The dashboard is always dark, like an instrument panel, whatever the system appearance.
struct StageBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: Palette.stage,
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.75
                )

                Ellipse()
                    .fill(.black.opacity(0.6))
                    .frame(width: proxy.size.width * 0.34, height: proxy.size.height * 0.07)
                    .blur(radius: 28)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.62)
            }
        }
        .ignoresSafeArea()
    }

    private enum Palette {
        static let stage = [
            Color(red: 0.12, green: 0.19, blue: 0.40),
            Color(red: 0.05, green: 0.07, blue: 0.16),
            Color(red: 0.02, green: 0.02, blue: 0.05),
        ]
    }
}
