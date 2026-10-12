import Foundation

/// Raw IMU readings saved as CSV, so they can be replayed through the detector later.
///
/// Each row is one reading: `time,sensor,x,y,z`, where sensor is `a` for acceleration
/// (g) or `g` for rotation rate (°/s). Time is on the sensor clock, in seconds.
public struct MotionRecording: Hashable, Sendable {
    public var samples: [MotionSample]

    public init(samples: [MotionSample]) {
        self.samples = samples
    }

    public static let csvHeader = "time,sensor,x,y,z"

    /// One reading as a CSV row, without a line break.
    public static func csvRow(_ sample: MotionSample) -> String {
        let sensor = sample.kind == .acceleration ? "a" : "g"
        let v = sample.value
        return String(format: "%.6f,%@,%.5f,%.5f,%.5f", sample.timestamp, sensor, v.x, v.y, v.z)
    }

    public var csv: String {
        var text = Self.csvHeader + "\n"
        text.reserveCapacity(samples.count * 48)
        for sample in samples {
            text += Self.csvRow(sample) + "\n"
        }
        return text
    }

    public init(csv: String) throws(GyroError) {
        var samples: [MotionSample] = []
        for (index, line) in csv.split(whereSeparator: \.isNewline).enumerated() {
            if index == 0, line == Self.csvHeader { continue }
            let fields = line.split(separator: ",")
            guard fields.count == 5,
                let time = Double(fields[0]),
                let x = Double(fields[2]), let y = Double(fields[3]), let z = Double(fields[4])
            else { throw .invalidRecording(line: index + 1) }
            let kind: MotionSample.Kind
            switch fields[1] {
            case "a": kind = .acceleration
            case "g": kind = .rotationRate
            default: throw .invalidRecording(line: index + 1)
            }
            samples.append(MotionSample(kind: kind, value: Vector3(x: x, y: y, z: z), timestamp: time))
        }
        self.init(samples: samples)
    }

    public init(contentsOf url: URL) throws {
        try self.init(csv: String(contentsOf: url, encoding: .utf8))
    }

    public func write(to url: URL) throws {
        try Data(csv.utf8).write(to: url, options: .atomic)
    }

    /// Plays the recording through a fresh detector and returns everything it found.
    public func events(configuration: MotionEventDetector.Configuration = .init()) -> [MotionEvent] {
        var detector = MotionEventDetector(configuration: configuration)
        return samples.flatMap { detector.process($0) }
    }
}
