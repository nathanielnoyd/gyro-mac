import SwiftUI

/// A compact indicator of where motion data is coming from, shown at the bottom of the sidebar.
struct StatusBadge: View {
    @Environment(SensorModel.self) private var sensors
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch sensors.motionStatus {
        case .stopped: "Motion off"
        case .connecting: "Connecting…"
        case .streaming: motionSource == .simulated ? "Simulated" : "Live"
        case .failed: "Motion unavailable"
        }
    }

    private var detail: String? {
        guard sensors.motionStatus == .streaming, let rate = sensors.sampleRate else { return nil }
        return "\(rate.formatted(.number.precision(.fractionLength(0)))) samples/s"
    }

    private var color: Color {
        switch sensors.motionStatus {
        case .stopped: .secondary
        case .connecting: .yellow
        case .streaming: motionSource == .simulated ? .purple : .green
        case .failed: .red
        }
    }
}
