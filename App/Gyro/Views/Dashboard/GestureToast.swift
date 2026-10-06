import GyroKit
import SwiftUI

/// Pops up over the stage for a moment whenever a gesture is recognized.
struct GestureToast: View {
    @Environment(GestureModel.self) private var gestures
    @State private var shown: GestureModel.LogEntry?

    private static let duration = Duration.seconds(2.5)

    var body: some View {
        ZStack {
            if let shown, let gesture = gestures.gesture(shown.gestureID) {
                HStack(spacing: 12) {
                    Image(systemName: gesture.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gesture.name)
                            .font(.headline)
                        Text(detail(shown, gesture: gesture))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 22)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .transition(.scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: 12)))
                .id(shown.id)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: shown?.id)
        .task(id: latest?.id) {
            guard let latest, latest.date.timeIntervalSinceNow > -1 else { return }
            shown = latest
            try? await Task.sleep(for: Self.duration)
            if shown?.id == latest.id {
                shown = nil
            }
        }
    }

    /// The newest recognition worth announcing.
    private var latest: GestureModel.LogEntry? {
        gestures.log.first { $0.gestureID != nil && $0.phase != .ended }
    }

    private func detail(_ entry: GestureModel.LogEntry, gesture: Gesture) -> String {
        let actions = gesture.actions.isEmpty || !gestures.actionsAreLive ? "" : " · ran \(gesture.actions.count == 1 ? "1 action" : "\(gesture.actions.count) actions")"
        switch entry.event.kind {
        case .taps:
            let strength = entry.event[.strength].map(MotionFeature.strength.format) ?? ""
            return strength + actions
        case .activity:
            return "Started" + actions
        }
    }
}

/// Opens the Gestures window. Lights up while an ongoing gesture is happening.
struct GesturesButton: View {
    @Environment(GestureModel.self) private var gestures
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "gestures")
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "hand.tap")
                if let active = gestures.gesture(gestures.activeActivity) {
                    Text(active.name)
                        .foregroundStyle(.primary)
                        .transition(.opacity)
                } else {
                    Text("Gestures")
                }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut, value: gestures.activeActivity)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Gestures (⌘G)")
    }
}
