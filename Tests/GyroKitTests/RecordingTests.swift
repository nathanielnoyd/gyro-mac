import Foundation
import Testing

@testable import GyroKit

/// Replays real sensor recordings through the fusion pipeline.
struct RecordingTests {
    /// An M5 Pro MacBook Pro, recorded with `gyro stream -f csv -r 200`: still for 3 s,
    /// front edge lifted to a pitch of about −20° and back, then right side lifted to a roll of about −13°.
    @Test func filterAgreesWithGravityThroughoutTilt() throws {
        let rows = try Recording.load("tilt-front-then-right")
        var tracker = MotionTracker()
        var largestError = 0.0

        for (index, row) in rows.enumerated() {
            tracker.process(MotionSample(kind: .acceleration, value: row.acceleration, timestamp: row.time))
            tracker.process(MotionSample(kind: .rotationRate, value: row.rotationRate, timestamp: row.time))

            // During slow tilts gravity dominates the accelerometer, so averaged over ±50 ms
            // (to remove hand jitter) it gives a reference angle.
            let window = rows[max(0, index - 10)...min(rows.count - 1, index + 10)]
            let up = -window.reduce(Vector3.zero) { $0 + $1.acceleration } / Double(window.count)
            let pitch = atan2(up.y, up.z).degrees
            let roll = atan2(-up.x, (up.y * up.y + up.z * up.z).squareRoot()).degrees
            largestError = max(
                largestError,
                abs(tracker.snapshot.attitude.pitch - pitch),
                abs(tracker.snapshot.attitude.roll - roll)
            )
        }

        #expect(largestError < 2)
        #expect(abs(tracker.snapshot.attitude.roll - -13) < 1.5)

        // The hand holding the Mac also twisted it slightly. Yaw should follow that real
        // rotation, which integrating the gyroscope's z axis measures independently.
        let resting = rows.prefix { $0.time < 3 }
        let zBias = resting.reduce(0) { $0 + $1.rotationRate.z } / Double(resting.count)
        let twist = zip(rows, rows.dropFirst()).reduce(0) { total, pair in
            total + (pair.1.rotationRate.z - zBias) * (pair.1.time - pair.0.time)
        }
        #expect(abs(tracker.snapshot.attitude.yaw - twist) < 0.5)
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

struct MotionRecordingCSVTests {
    @Test(arguments: [
        ("time,sensor,x,y,z\n0.1,q,1,2,3", 2),
        ("time,sensor,x,y,z\n0.1,a,1,2,3\n0.2,g,1,2", 3),
        ("0.1,a,one,2,3", 1),
        ("0.1,a,1,2,3,4", 1),
    ])
    func rejectsMalformedRows(csv: String, line: Int) {
        #expect(throws: GyroError.invalidRecording(line: line)) {
            try MotionRecording(csv: csv)
        }
    }

    @Test func readsRowsWithOrWithoutTheHeader() throws {
        let rows = "0.1,a,0,0,-1\n0.2,g,1.5,0,0"
        let withHeader = try MotionRecording(csv: MotionRecording.csvHeader + "\n" + rows)
        let withoutHeader = try MotionRecording(csv: rows)
        #expect(withHeader.samples == withoutHeader.samples)
        #expect(
            withHeader.samples == [
                MotionSample(kind: .acceleration, value: Vector3(x: 0, y: 0, z: -1), timestamp: 0.1),
                MotionSample(kind: .rotationRate, value: Vector3(x: 1.5, y: 0, z: 0), timestamp: 0.2),
            ])
    }
}
