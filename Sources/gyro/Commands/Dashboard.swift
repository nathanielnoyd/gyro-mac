import ArgumentParser
import Foundation
import GyroKit

struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show every sensor in a live, full-screen dashboard.",
        discussion: """
            The same instruments as the Gyro app: a trace of each axis, an artificial
            horizon, the lid angle and a seismograph that marks recognized gestures.
            Run with sudo to include the accelerometer and gyroscope.

            Keys: space pauses, z makes the current heading zero yaw, q quits.
            """
    )

    @Flag(help: .hidden)
    var demo = false

    func run() async throws {
        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            throw CLIError(description: "The dashboard needs a terminal. To save or pipe readings, use gyro stream.")
        }
        let lid = try? LidAngleSensor()
        let feed = demo ? MotionFeed(samples: SimulatedMotion.samples()) : try? MotionFeed()
        let motionTask = feed.map { feed in Task { await feed.run() } }
        defer { motionTask?.cancel() }

        let source: DashboardView.Source =
            if feed == nil {
                .unavailable(Self.motionUnavailableReason)
            } else {
                demo ? .simulated : .live
            }
        var view = DashboardView(source: source)
        let screen = TerminalScreen()
        defer { screen.restore() }

        while true {
            while let key = screen.readKey() {
                switch key {
                case "q", "Q", .controlC: return
                case "z", "Z": feed?.zeroYaw()
                case " ", "p", "P": view.isPaused.toggle()
                default: break
                }
            }

            if let feed {
                let frame = feed.takeFrame()
                if !view.isPaused {
                    view.update(with: frame)
                }
            }
            if !view.isPaused {
                view.lidAngle = try? lid?.angle()
            }
            screen.draw(view.render(size: screen.size))

            try await Task.sleep(for: .milliseconds(33))
        }
    }

    private static var motionUnavailableReason: String {
        MotionSensor.isPresent
            ? "The accelerometer and gyroscope only report to root."
            : "This Mac has no accelerometer or gyroscope."
    }
}
