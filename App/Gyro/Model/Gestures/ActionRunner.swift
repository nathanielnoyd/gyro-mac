import AppKit
import GyroKit
import UserNotifications
import os

/// Carries out a gesture's actions.
enum ActionRunner {
    /// The sounds in /System/Library/Sounds.
    static let sounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
        "Submarine", "Tink",
    ]

    /// Posted to every app on the Mac whenever a gesture is recognized, with the gesture's
    /// `id` and `name` in its user info. Scripts and other apps can listen for it.
    static let distributedNotification = Notification.Name("io.github.nathanielnoyd.gyro.gesture")

    static func run(_ gesture: Gesture, event: MotionEvent) {
        DistributedNotificationCenter.default().postNotificationName(
            distributedNotification,
            object: nil,
            userInfo: ["id": gesture.id, "name": gesture.name],
            deliverImmediately: true
        )
        for action in gesture.actions {
            run(action, for: gesture, event: event)
        }
    }

    static func run(_ action: GestureAction, for gesture: Gesture, event: MotionEvent) {
        switch action.kind {
        case .sound:
            play(action.value)
        case .notification:
            Task { await notify(gesture, event: event) }
        case .shortcut:
            guard !action.value.isEmpty else { return }
            launch("/usr/bin/shortcuts", ["run", action.value], for: gesture, event: event)
        case .openURL:
            guard let url = URL(string: action.value), url.scheme != nil else { return }
            NSWorkspace.shared.open(url)
        case .script:
            launch("/bin/zsh", ["-c", action.value], for: gesture, event: event)
        }
    }

    static func play(_ sound: String) {
        // Copies play independently, so a quick double tap isn't cut short.
        (NSSound(named: sound)?.copy() as? NSSound)?.play()
    }

    /// The names of the user's shortcuts.
    static func shortcuts() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self)
                .split(separator: "\n")
                .map(String.init)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }.value
    }

    private static func notify(_ gesture: Gesture, event: MotionEvent) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = gesture.name
        content.body =
            event.kind == .taps ? "Detected \(event.count == 1 ? "a tap" : "\(event.count) taps")." : "Started."
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Starts a process with details of the gesture in its environment:
    /// `GYRO_GESTURE` (the name), `GYRO_GESTURE_ID`, `GYRO_TAPS` and `GYRO_STRENGTH_MG`.
    private static func launch(_ executable: String, _ arguments: [String], for gesture: Gesture, event: MotionEvent) {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GYRO_GESTURE"] = gesture.name
        environment["GYRO_GESTURE_ID"] = gesture.id
        environment["GYRO_TAPS"] = String(event.count)
        if let strength = event[.strength] ?? event[.impactStrength] {
            environment["GYRO_STRENGTH_MG"] = String(Int((pow(10, strength) * 1_000).rounded()))
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            if process.terminationStatus != 0 {
                log.error(
                    "\(executable, privacy: .public) exited with status \(process.terminationStatus) for \(gesture.name, privacy: .public)"
                )
            }
        }
        do {
            try process.run()
        } catch {
            log.error("Couldn't run \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

nonisolated private let log = Logger(subsystem: "io.github.nathanielnoyd.gyro", category: "actions")
