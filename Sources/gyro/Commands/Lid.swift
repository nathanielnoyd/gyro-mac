import ArgumentParser
import GyroKit

struct Lid: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the lid angle in degrees.")

    @Flag(name: .shortAndLong, help: "Keep printing the angle whenever it changes.")
    var watch = false

    func run() async throws {
        let sensor = try LidAngleSensor()
        var lastAngle = try sensor.angle()
        print(format(lastAngle))
        guard watch else { return }

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(33))
            let angle = try sensor.angle()
            if angle != lastAngle {
                print(format(angle))
                lastAngle = angle
            }
        }
    }

    private func format(_ angle: Double) -> String {
        "\(Int(angle))°"
    }
}
