import ArgumentParser
import Foundation
import GyroKit

struct Sensors: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the sensors this Mac has.")

    func run() {
        guard Style.isTerminal else {
            print("SENSOR".padded(to: 24) + "PRESENT".padded(to: 10) + "NEEDS ROOT")
            for sensor in SPUSensor.allCases {
                print(
                    sensor.displayName.padded(to: 24) + (sensor.isPresent ? "yes" : "no").padded(to: 10)
                        + (sensor.requiresRoot ? "yes" : "no"))
            }
            return
        }

        let lines = SPUSensor.allCases.map { sensor in
            let mark = sensor.isPresent ? Style.color(Palette.green, "●") : Style.color(Palette.border, "○")
            let name = sensor.isPresent ? Style.bold(sensor.displayName) : Style.dim(sensor.displayName)
            return mark + " " + name.padded(to: 24) + status(of: sensor)
        }
        print(
            Panel(title: "Sensors", accessory: Style.dim(SystemInfo.modelIdentifier), width: 50, lines: lines).render()
                .joined(separator: "\n"))
    }

    private func status(of sensor: SPUSensor) -> String {
        guard sensor.isPresent else { return Style.dim("not present") }
        if sensor == .lidAngle, let angle = try? LidAngleSensor().angle() {
            return Style.color(Palette.cyan, String(format: "%.0f°", angle))
        }
        if sensor.requiresRoot, geteuid() != 0 {
            return Style.color(Palette.yellow, "needs sudo")
        }
        return Style.dim("available")
    }
}
