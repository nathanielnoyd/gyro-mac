import ArgumentParser
import Foundation
import GyroKit

struct Stream: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stream acceleration, rotation rate and orientation. Requires sudo.",
        discussion: """
            Each row holds the latest reading from every sensor: acceleration in g,
            rotation rate in °/s and orientation in degrees. Time is in seconds
            since the stream started.

            Example: sudo gyro stream --format csv --duration 10 > motion.csv
            """
    )

    enum Format: String, ExpressibleByArgument, CaseIterable {
        case table, csv, json
    }

    @Option(name: .shortAndLong, help: "Output format: \(Format.allCases.map(\.rawValue).joined(separator: ", ")).")
    var format: Format = .table

    @Option(name: .shortAndLong, help: "Rows per second, from 1 to 1000.")
    var rate: Double = 50

    @Option(name: .shortAndLong, help: "Stop after this many seconds.")
    var duration: Double?

    func validate() throws {
        guard (1...1_000).contains(rate) else {
            throw ValidationError("--rate must be between 1 and 1000.")
        }
    }

    func run() async throws {
        let samples = try MotionSensor().samples(orExplain: "stream")
        let writer = RowWriter(format: format)
        var tracker = MotionTracker()
        var startTime: Double?
        var nextRowTime = 0.0

        writer.writeHeader()
        for await sample in samples {
            tracker.process(sample)
            let start = startTime ?? sample.timestamp
            startTime = start

            let elapsed = sample.timestamp - start
            if let duration, elapsed > duration { break }
            guard elapsed >= nextRowTime else { continue }

            nextRowTime = elapsed + 1 / rate
            writer.write(tracker.snapshot, elapsed: elapsed)
        }
    }
}

/// Formats ``MotionSnapshot`` rows for `gyro stream`.
private struct RowWriter {
    let format: Stream.Format
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let columns = ["time", "ax", "ay", "az", "gx", "gy", "gz", "roll", "pitch", "yaw"]

    init(format: Stream.Format) {
        self.format = format
    }

    func writeHeader() {
        switch format {
        case .table:
            emit(Style.dim(Self.columns.map { $0.leftPadded(to: 9) }.joined()))
        case .csv:
            emit(Self.columns.joined(separator: ","))
        case .json:
            break
        }
    }

    func write(_ snapshot: MotionSnapshot, elapsed: Double) {
        switch format {
        case .table:
            emit(values(snapshot, elapsed).map { String(format: "%9.3f", $0) }.joined())
        case .csv:
            emit(values(snapshot, elapsed).map { String(format: "%.4f", $0) }.joined(separator: ","))
        case .json:
            var row = snapshot
            row.timestamp = elapsed
            if let data = try? encoder.encode(row) {
                emit(String(decoding: data, as: UTF8.self))
            }
        }
    }

    private func values(_ s: MotionSnapshot, _ elapsed: Double) -> [Double] {
        [
            elapsed,
            s.acceleration.x, s.acceleration.y, s.acceleration.z,
            s.rotationRate.x, s.rotationRate.y, s.rotationRate.z,
            s.attitude.roll, s.attitude.pitch, s.attitude.yaw,
        ]
    }

    /// Writes one line and flushes, so rows reach pipes immediately.
    private func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
