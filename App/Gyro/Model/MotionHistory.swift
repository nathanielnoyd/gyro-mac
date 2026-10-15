import GyroKit

/// A rolling window of recent readings for the charts.
struct MotionHistory {
    struct Point: Identifiable {
        var time: Double
        var acceleration: Vector3
        var rotationRate: Vector3
        /// The strongest vibration, in g, since the previous point.
        var vibration: Double

        var id: Double { time }
    }

    /// How many seconds of readings to keep.
    var duration: Double = 6

    private(set) var points: [Point] = []

    mutating func append(_ snapshot: MotionSnapshot, vibration: Double) {
        points.append(
            Point(
                time: snapshot.timestamp, acceleration: snapshot.acceleration, rotationRate: snapshot.rotationRate,
                vibration: vibration))
        let cutoff = snapshot.timestamp - duration
        if let firstKept = points.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            points.removeFirst(firstKept)
        }
    }

    mutating func removeAll() {
        points.removeAll()
    }

    /// The time span covered by the chart's x axis, ending at the newest reading.
    var window: ClosedRange<Double> {
        let end = points.last?.time ?? duration
        return (end - duration)...end
    }
}
