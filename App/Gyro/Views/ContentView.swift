import SwiftUI

struct ContentView: View {
    @Environment(HelperInstaller.self) private var helper
    @Environment(GestureModel.self) private var gestures

    var body: some View {
        DashboardView()
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // The user may have just approved the helper in System Settings,
                // or calibrated gestures with `gyro calibrate`.
                helper.refresh()
                gestures.importCalibrations()
            }
    }
}
