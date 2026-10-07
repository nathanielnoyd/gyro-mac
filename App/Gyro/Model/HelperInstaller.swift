import Foundation
import GyroXPC
import Observation
import os
import ServiceManagement

private let log = Logger(subsystem: HelperService.appBundleIdentifier, category: "helper")

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
        case repairing
        case failed(String)
    }

    /// How far repairing a helper that's installed but won't start has gone.
    enum Repair: Comparable {
        /// Nothing tried yet.
        case none
        /// Registered again, which needs no password.
        case reregistered
        /// Unloaded as root and registered again: everything the app can do.
        case unloaded
    }

    /// What to do when macOS keeps refusing to register the helper.
    ///
    /// macOS can lose track of which app a helper belongs to, after the app is moved or
    /// rebuilt somewhere else. Then it neither starts the helper nor lets the app register it
    /// again, and only resetting its list of background items clears the stale record.
    static let refusedMessage = "macOS wouldn't register Gyro's helper. Try installing it again. If it keeps failing, macOS may have lost track of it: run “sudo sfltool resetbtm” in Terminal, restart your Mac and install the helper again. That also asks you to approve other apps' background items again."

    private(set) var state: State = .notInstalled
    private(set) var repair = Repair.none
    private let service = SMAppService.daemon(plistName: HelperService.launchDaemonPlistName)

    init() {
        refresh()
    }

    func refresh() {
        // Unregistering mid-repair would read as "not installed" and stop motion for good.
        guard state != .repairing else { return }
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
        } catch let error as NSError {
            log.error("Couldn't register the helper: \(error.domain, privacy: .public) \(error.code)")
            refresh()
            if state != .awaitingApproval {
                // A bare "Operation not permitted" says nothing about what to do next.
                state = .failed(error.code == EPERM ? Self.refusedMessage : error.localizedDescription)
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

    /// Registers the helper again, after the app couldn't reach it. Needs no password.
    ///
    /// This picks up a helper rebuilt or moved since it was approved. Each repair runs once
    /// per launch, so a helper that still won't start isn't re-registered in a loop.
    func reregister() async {
        guard repair < .reregistered else { return }
        repair = .reregistered
        log.notice("Couldn't reach the helper; registering it again")
        await reinstall()
    }

    /// Unloads the helper's launchd job as root, then registers it again.
    ///
    /// launchd keeps an ad hoc signed helper pinned to the exact binary it first approved,
    /// and only root can unload it. macOS asks for an administrator password.
    func repairWithAdministratorPrivileges() async {
        state = .repairing
        do {
            try await Self.runAsAdministrator("/bin/launchctl bootout system/\(HelperService.machServiceName) || true")
        } catch {
            log.notice("Didn't unload the helper: \(error.localizedDescription, privacy: .public)")
            state = .installed
            refresh()
            return
        }
        log.notice("Unloaded the helper as root; registering it again")
        repair = .unloaded
        await reinstall()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func reinstall() async {
        state = .repairing
        try? await service.unregister()
        // Registering straight after unregistering can be refused while macOS catches up.
        for attempt in 1...3 {
            state = .notInstalled
            install()
            guard case .failed = state, attempt < 3 else { break }
            try? await Task.sleep(for: .seconds(1))
        }
        log.notice("Helper registered again: \(String(describing: self.state), privacy: .public)")
    }

    /// Runs a shell command as root after macOS asks the user for an administrator password.
    /// Throws if they cancel or the command fails.
    private static func runAsAdministrator(_ command: String) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw CocoaError(.userCancelled) }
    }
}
