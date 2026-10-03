import GyroXPC
import Observation
import ServiceManagement

/// Installs and tracks the privileged helper that reads the IMU.
///
/// The helper is a launchd daemon bundled inside the app. Registering it asks
/// the user to approve it once in System Settings › General › Login Items.
@Observable
final class HelperInstaller {
    enum State: Equatable {
        case notInstalled
        case awaitingApproval
        case installed
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    private let service = SMAppService.daemon(plistName: HelperService.launchDaemonPlistName)

    init() {
        refresh()
    }

    func refresh() {
        state = switch service.status {
        case .enabled: .installed
        case .requiresApproval: .awaitingApproval
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .notInstalled
        }
    }

    func install() {
        do {
            try service.register()
            refresh()
        } catch let error as NSError where error.code == kSMErrorLaunchDeniedByUser {
            state = .awaitingApproval
        } catch {
            refresh()
            if state != .awaitingApproval {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func uninstall() async {
        do {
            try await service.unregister()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
