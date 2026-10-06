import SwiftUI

@main
struct GyroApp: App {
    @State private var sensors: SensorModel
    @State private var gestures: GestureModel
    @State private var helper = HelperInstaller()
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    init() {
        let sensors = SensorModel()
        let gestures = GestureModel(sensors: sensors)
        sensors.eventHandler = { [weak gestures] events in gestures?.handle(events) }
        _sensors = State(initialValue: sensors)
        _gestures = State(initialValue: gestures)
    }

    var body: some Scene {
        Window("Gyro", id: "main") {
            ContentView()
                .environment(sensors)
                .environment(gestures)
                .environment(helper)
                .task { sensors.start() }
                .task(id: MotionTrigger(source: motionSource, helper: helper.state)) {
                    updateMotion()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 700)
        .commands {
            CommandMenu("Motion") {
                Button("Zero Yaw", systemImage: "scope") { sensors.resetAttitude() }
                    .keyboardShortcut("0", modifiers: .command)
                Picker("Source", selection: $motionSource) {
                    ForEach(MotionSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                Divider()
                OpenGesturesButton(gestures: gestures)
                Toggle("Run Gesture Actions", isOn: $gestures.runsActions)
            }
        }

        Window("Gestures", id: "gestures") {
            GesturesView()
                .environment(sensors)
                .environment(gestures)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 640)

        MenuBarExtra {
            MenuBarView()
                .environment(sensors)
                .environment(gestures)
        } label: {
            Image(systemName: "gyroscope")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(helper)
        }
    }

    /// Starts reading motion once there is a source that can deliver it.
    private func updateMotion() {
        switch motionSource {
        case .simulated:
            sensors.startMotion(from: .simulated)
        case .sensors where helper.state == .installed:
            sensors.startMotion(from: .sensors)
        case .sensors:
            sensors.stopMotion()
        }
    }
}

/// Opens the Gestures window from the Motion menu, optionally to calibrate.
private struct OpenGesturesButton: View {
    let gestures: GestureModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Gestures…", systemImage: "hand.tap") { openWindow(id: "gestures") }
            .keyboardShortcut("g", modifiers: .command)
        Button("Calibrate Gestures…", systemImage: "dot.scope") {
            openWindow(id: "gestures")
            gestures.startCalibration()
        }
    }
}

/// Everything that decides whether, and from where, motion should stream.
private struct MotionTrigger: Equatable {
    var source: MotionSource
    var helper: HelperInstaller.State
}
