import ArgumentParser
import Foundation
import GyroKit

struct Lid: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the lid angle in degrees.")

    @Flag(name: .shortAndLong, help: "Keep printing the angle whenever it changes.")
    var watch = false

    func run() async throws {
        let sensor = try LidAngleSensor()
        var lastAngle = try sensor.angle()
        guard watch else {
            print(format(lastAngle))
            return
        }

        // In a terminal, redraw one line in place; in a pipe, print a line per change.
        if Style.isTerminal {
            print(meter(lastAngle), terminator: "")
            // End the line on Ctrl-C, so the shell prompt doesn't land on the meter.
            signal(SIGINT) { _ in
                write(STDOUT_FILENO, "\n", 1)
                _exit(0)
            }
        } else {
            print(format(lastAngle))
        }
        fflush(stdout)

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(33))
            let angle = try sensor.angle()
            guard angle != lastAngle else { continue }
            lastAngle = angle
            if Style.isTerminal {
                print("\r\u{1B}[K" + meter(angle), terminator: "")
            } else {
                print(format(angle))
            }
            fflush(stdout)
        }
    }

    private func format(_ angle: Double) -> String {
        guard Style.isTerminal else { return "\(Int(angle))°" }
        return Style.bold("\(Int(angle))°") + "  " + Style.dim(LidPosition(angle: angle).description.lowercased())
    }

    /// A bar across the range from closed to flat open, with the angle and what it means.
    private func meter(_ angle: Double) -> String {
        let width = 36
        let filled = Int((min(max(angle, 0), 180) / 180 * Double(width)).rounded())
        let bar =
            Style.color(Palette.accent, String(repeating: "━", count: filled))
            + Style.color(Palette.border, String(repeating: "─", count: width - filled))
        return "  " + bar + "  " + Style.bold(String(format: "%3.0f°", angle)) + "  "
            + Style.dim(LidPosition(angle: angle).description.lowercased())
    }
}
