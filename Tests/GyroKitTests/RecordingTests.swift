import Foundation
import Testing
@testable import GyroKit

/// Replays real sensor recordings through the fusion pipeline.
struct RecordingTests {
    /// An M5 Pro MacBook Pro, recorded with `gyro stream -f csv -r 200`: still for 3 s,
    /// rolled about 20° to one side and back, then pitched about 13° by lifting the front edge.
    @Test func filterAgreesWithGravityThroughoutTilt() throws {
        let rows = try Recording.load("tilt-roll-then-pitch")
        var tracker = MotionTracker()
        var largestError = 0.0

        for (index, row) in rows.enumerated() {
            tracker.process(MotionSample(kind: .acceleration, value: row.acceleration, timestamp: row.time))
            tracker.process(MotionSample(kind: .rotationRate, value: row.rotationRate, timestamp: row.time))

            // During slow tilts gravity dominates the accelerometer, so averaged over ±50 ms
            // (to remove hand jitter) it gives a reference angle.
            let window = rows[max(0, index - 10)...min(rows.count - 1, index + 10)]
            let up = -window.reduce(Vector3.zero) { $0 + $1.acceleration } / Double(window.count)
            let roll = atan2(up.y, up.z).degrees
            let pitch = atan2(-up.x, (up.y * up.y + up.z * up.z).squareRoot()).degrees
            largestError = max(
                largestError,
                abs(tracker.snapshot.attitude.roll - roll),
                abs(tracker.snapshot.attitude.pitch - pitch)
            )
        }

        #expect(largestError < 2)
        #expect(abs(tracker.snapshot.attitude.pitch - -13) < 1.5)
    }
}

/// A CSV file written by `gyro stream -f csv`.
private enum Recording {
    struct Row {
        var time: Double
        var acceleration: Vector3
        var rotationRate: Vector3
    }

    static func load(_ name: String) throws -> [Row] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        return lines.dropFirst().map { line in
            let v = line.split(separator: ",").map { Double($0)! }
            return Row(
                time: v[0],
                acceleration: Vector3(x: v[1], y: v[2], z: v[3]),
                rotationRate: Vector3(x: v[4], y: v[5], z: v[6])
            )
        }
    }
}
