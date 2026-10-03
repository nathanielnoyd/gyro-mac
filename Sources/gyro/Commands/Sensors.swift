import ArgumentParser
import GyroKit

struct Sensors: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the sensors this Mac has.")

    func run() {
        print(Style.dim("  " + "SENSOR".padded(to: 24) + "PRESENT".padded(to: 10) + "NEEDS ROOT"))
        for sensor in SPUSensor.allCases {
            let present = sensor.isPresent ? Style.green("yes") : Style.dim("no ")
            let root = sensor.requiresRoot ? "yes" : "no"
            print("  " + sensor.displayName.padded(to: 24) + present + String(repeating: " ", count: 7) + root)
        }
    }
}
