import GyroKit
import SwiftUI

/// The Gestures window: what the sensors are noticing, and the gestures Gyro watches for.
struct GesturesView: View {
    enum Item: Hashable {
        case live
        case gesture(String)
    }

    @Environment(GestureModel.self) private var gestures
    @State private var selection: Item? = .live

    var body: some View {
        @Bindable var gestures = gestures

        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Live", systemImage: "waveform.badge.magnifyingglass")
                        .tag(Item.live)
                }
                section("Taps", kind: .taps)
                section("Ongoing", kind: .activity)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let date = gestures.lastCalibrated {
                        Text("Calibrated \(date, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Calibrate Gestures…") { gestures.startCalibration() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    Toggle("Run actions", isOn: $gestures.runsActions)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if gestures.runsActions, !gestures.actionsAreLive {
                        Text("Actions run only with the built-in sensors, not simulated motion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
            }
            .toolbar {
                Button("Calibrate…", systemImage: "dot.scope") { gestures.startCalibration() }
                    .help("Record every gesture in turn, so Gyro learns how they look on your Mac")
                Menu("New Gesture", systemImage: "plus") {
                    Button("New Tap Gesture…", systemImage: "hand.tap") {
                        gestures.startRecordingNewGesture(of: .taps)
                    }
                    Button("New Ongoing Gesture…", systemImage: "waveform.path") {
                        gestures.startRecordingNewGesture(of: .activity)
                    }
                }
            }
        } detail: {
            switch selection {
            case .live, nil:
                LiveEventsView()
            case .gesture(let id):
                if gestures.gesture(id) != nil {
                    GestureDetailView(id: id)
                        .id(id)
                } else {
                    ContentUnavailableView("No Gesture Selected", systemImage: "hand.tap")
                }
            }
        }
        .sheet(isPresented: isCalibrating) {
            if let calibration = gestures.calibration {
                CalibrationSheet(session: calibration)
            }
        }
        .sheet(isPresented: isRecording) {
            RecordingSheet { newID in
                if let newID {
                    selection = .gesture(newID)
                }
            }
        }
    }

    private func section(_ title: String, kind: MotionEvent.Kind) -> some View {
        Section(title) {
            ForEach(gestures.gestures.filter { $0.kind == kind }) { gesture in
                GestureRow(gesture: gesture)
                    .tag(Item.gesture(gesture.id))
                    .contextMenu {
                        Button("Record Examples…") { gestures.startRecording(for: gesture.id) }
                        if gesture.isCustom {
                            Button("Delete", role: .destructive) { gestures.delete(gesture.id) }
                        }
                    }
            }
        }
    }

    private var isCalibrating: Binding<Bool> {
        Binding(
            get: { gestures.calibration != nil },
            set: { if !$0 { gestures.finishCalibration(save: false) } }
        )
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { gestures.session != nil },
            set: { if !$0 { gestures.cancelRecording() } }
        )
    }
}

/// A gesture in the sidebar, which lights up whenever the gesture is recognized.
private struct GestureRow: View {
    @Environment(GestureModel.self) private var gestures
    let gesture: Gesture

    var body: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(gesture.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: gesture.symbol)
                    .foregroundStyle(gesture.isEnabled ? Color.accentColor : .secondary)
            }
            Spacer(minLength: 4)
            RecognitionPulse(
                date: gestures.lastRecognized[gesture.id],
                isOngoing: gestures.activeActivity == gesture.id
            )
        }
        .opacity(gesture.isEnabled ? 1 : 0.5)
    }

    private var subtitle: String {
        if !gesture.isEnabled { return "Off" }
        if gesture.isTrained { return "\(gesture.examples.count) examples" }
        return gesture.isCustom ? "Untrained" : "Built-in guess"
    }
}

/// A dot that flashes when a gesture is recognized, and stays lit while an activity goes on.
struct RecognitionPulse: View {
    let date: Date?
    var isOngoing = false
    @State private var isLit = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .shadow(color: .green.opacity(0.9), radius: 4)
            .opacity(isLit || isOngoing ? 1 : 0)
            .scaleEffect(isLit ? 1.4 : 1)
            .animation(.easeOut(duration: 0.6), value: isLit)
            .animation(.easeInOut, value: isOngoing)
            .task(id: date) {
                guard let date, date.timeIntervalSinceNow > -1 else { return }
                isLit = true
                try? await Task.sleep(for: .seconds(1.2))
                isLit = false
            }
            .accessibilityHidden(true)
    }
}
