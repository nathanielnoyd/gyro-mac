import SwiftUI

struct ContentView: View {
    @Environment(HelperInstaller.self) private var helper

    var body: some View {
        DashboardView()
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // The user may have just approved the helper in System Settings.
                helper.refresh()
            }
    }
}
