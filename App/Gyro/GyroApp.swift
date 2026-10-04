import SwiftUI

@main
struct GyroApp: App {
    @State private var sensors = SensorModel()
    @State private var helper = HelperInstaller()
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    var body: some Scene {
        Window("Gyro", id: "main") {
            ContentView()
                .environment(sensors)
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
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(sensors)
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

/// Everything that decides whether, and from where, motion should stream.
private struct MotionTrigger: Equatable {
    var source: MotionSource
    var helper: HelperInstaller.State
}
