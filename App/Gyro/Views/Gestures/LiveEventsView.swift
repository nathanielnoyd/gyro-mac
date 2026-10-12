import GyroKit
import SwiftUI

/// Everything the detector notices as it happens: ongoing motion at the top, a log of taps and gestures below.
struct LiveEventsView: View {
    @Environment(GestureModel.self) private var gestures
    @Environment(SensorModel.self) private var sensors

    var body: some View {
        VStack(spacing: 0) {
            current
                .padding(20)
            Divider()
            if gestures.log.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Yet", systemImage: "hand.tap")
                } description: {
                    Text(
                        sensors.isMotionLive
                            ? "Tap the palm rest or start typing."
                            : "Turn on the motion sensors in the main window to see taps and gestures here.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(gestures.log) { entry in
                    LogRow(entry: entry, gesture: gestures.gesture(entry.gestureID))
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Live")
        .toolbar {
            Button("Clear", systemImage: "trash") { gestures.clearLog() }
                .disabled(gestures.log.isEmpty)
        }
    }

    private var current: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Right now")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                let active = gestures.gesture(gestures.activeActivity)
                Label(active?.name ?? "Nothing ongoing", systemImage: active?.symbol ?? "moon.zzz")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(active == nil ? .secondary : .primary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: active?.id)
            }
            Spacer()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                ForEach(MotionFeature.allCases.filter { $0.kind == .activity }, id: \.self) { feature in
                    GridRow {
                        Text(feature.title)
                            .foregroundStyle(.secondary)
                            .help(feature.explanation)
                        Text(gestures.latestActivity?[feature].map(feature.format) ?? "–")
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)
        }
    }
}

private struct LogRow: View {
    let entry: GestureModel.LogEntry
    let gesture: Gesture?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Image(systemName: gesture?.symbol ?? "questionmark.circle")
                .foregroundStyle(gesture == nil ? Color.secondary : .accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(gesture == nil ? .regular : .semibold)
                    .foregroundStyle(entry.phase == .ended ? .secondary : .primary)
                if entry.event.kind == .taps || entry.phase == .began {
                    Text(entry.event.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let taps = entry.event.count == 1 ? "1 tap" : "\(entry.event.count) taps"
        guard let gesture else { return "Unrecognized · \(taps)" }
        switch entry.phase {
        case .began: return "\(gesture.name) began"
        case .ended: return "\(gesture.name) ended"
        case .tapped, nil: return gesture.name
        }
    }
}
