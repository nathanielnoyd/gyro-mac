import ArgumentParser
import GyroKit
import Synchronization

struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show every sensor in a live, full-screen dashboard.",
        discussion: "Run with sudo to include the accelerometer and gyroscope."
    )

    @Flag(help: .hidden)
    var demo = false

    func run() async throws {
        let lid = try? LidAngleSensor()
        let feed = demo ? MotionFeed(samples: SimulatedMotion.samples()) : try? MotionFeed()
        let motionTask = feed.map { feed in Task { await feed.run() } }
        defer { motionTask?.cancel() }

        var view = DashboardView(motionUnavailableReason: feed == nil ? Self.motionUnavailableReason : nil)
        let screen = TerminalScreen()
        defer { screen.restore() }

        while true {
            while let key = screen.readKey() {
                switch key {
                case "q", .controlC: return
                case "z": feed?.zeroYaw()
                default: break
                }
            }

            if let feed {
                view.update(with: feed.takeFrame())
            }
            view.lidAngle = try? lid?.angle()
            screen.draw(view.render())

            try await Task.sleep(for: .milliseconds(33))
        }
    }

    private static var motionUnavailableReason: String {
        MotionSensor.isPresent
            ? "Motion sensors need root. Run " + Style.bold("sudo gyro") + " to see them."
            : "This Mac has no accelerometer or gyroscope."
    }
}

// MARK: - Motion feed

/// Collects IMU readings in the background and hands the render loop one frame at a time.
private final class MotionFeed: Sendable {
    struct Frame {
        var snapshot: MotionSnapshot
        /// Gyroscope readings received since the previous frame.
        var sampleCount: Int
        /// Largest change in total acceleration, relative to its recent average, since the previous frame.
        var vibration: Double
    }

    private struct State {
        var tracker = MotionTracker()
        var sampleCount = 0
        var vibration = 0.0
        /// Slow moving average of total acceleration, so vibration ignores gravity and sensor offset.
        var restingMagnitude: Double?
    }

    private let samples: AsyncStream<MotionSample>
    private let state = Mutex(State())

    init(samples: AsyncStream<MotionSample>) {
        self.samples = samples
    }

    convenience init() throws {
        self.init(samples: try MotionSensor().samples())
    }

    func run() async {
        for await sample in samples {
            state.withLock { state in
                state.tracker.process(sample)
                switch sample.kind {
                case .rotationRate:
                    state.sampleCount += 1
                case .acceleration:
                    let magnitude = sample.value.magnitude
                    let resting = state.restingMagnitude.map { $0 + (magnitude - $0) * 0.002 } ?? magnitude
                    state.restingMagnitude = resting
                    state.vibration = max(state.vibration, abs(magnitude - resting))
                }
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer {
                state.sampleCount = 0
                state.vibration = 0
            }
            return Frame(snapshot: state.tracker.snapshot, sampleCount: state.sampleCount, vibration: state.vibration)
        }
    }

    func zeroYaw() {
        state.withLock { $0.tracker.resetAttitude() }
    }
}

// MARK: - View

private struct DashboardView {
    let motionUnavailableReason: String?
    var lidAngle: Double?

    private var snapshot = MotionSnapshot()
    private var vibrationHistory: [Double] = []
    private var sampleRate = SampleRateMeter()

    private static let columnWidth = 38
    private static let gaugeWidth = 19

    init(motionUnavailableReason: String?) {
        self.motionUnavailableReason = motionUnavailableReason
    }

    mutating func update(with frame: MotionFeed.Frame) {
        snapshot = frame.snapshot
        sampleRate.record(frame.sampleCount, at: snapshot.timestamp)
        vibrationHistory.append(frame.vibration)
        if vibrationHistory.count > 64 {
            vibrationHistory.removeFirst(vibrationHistory.count - 64)
        }
    }

    func render() -> [String] {
        var lines = ["", header, ""]

        if let motionUnavailableReason {
            lines += lidSection.map { "  " + $0 }
            lines += ["", "  " + Style.yellow("●") + " " + motionUnavailableReason]
        } else {
            lines += columns(
                section("ACCELERATION", unit: "g", rows: axisRows(snapshot.acceleration, range: 2, format: "%+7.3f")),
                section("ROTATION", unit: "°/s", rows: axisRows(snapshot.rotationRate, range: 250, format: "%+7.1f"))
            )
            lines.append("")
            lines += columns(
                section("ORIENTATION", unit: "°", rows: attitudeRows),
                lidSection
            )
            lines.append("")
            lines += columns(vibrationSection, [])
        }

        lines += ["", "  " + Style.dim("q quit" + (motionUnavailableReason == nil ? "   z zero yaw" : ""))]
        return lines
    }

    // MARK: Sections

    private var header: String {
        let title = "  " + Style.bold("gyro") + "  " + Style.dim(SystemInfo.modelIdentifier)
        guard motionUnavailableReason == nil else { return title }
        let rate = sampleRate.hertz.map { String(format: "%.0f Hz", $0) } ?? "starting"
        return title + "   " + Style.green("●") + " " + Style.dim(rate)
    }

    private func axisRows(_ vector: Vector3, range: Double, format: String) -> [String] {
        zip(["x", "y", "z"], [vector.x, vector.y, vector.z]).enumerated().map { index, axis in
            let color = { Style.axis(index, $0) }
            return color(axis.0) + "  "
                + Gauge.centered(axis.1, range: range, width: Self.gaugeWidth, color: color)
                + " " + String(format: format, axis.1)
        }
    }

    private var attitudeRows: [String] {
        let attitude = snapshot.attitude
        return [("pitch", attitude.pitch), ("roll ", attitude.roll), ("yaw  ", attitude.yaw)].map { name, degrees in
            Style.dim(name) + " "
                + Gauge.centered(degrees, range: 180, width: Self.gaugeWidth - 4, color: Style.cyan)
                + " " + String(format: "%+7.1f", degrees)
        }
    }

    private var lidSection: [String] {
        guard let lidAngle else {
            return section("LID", unit: "°", rows: [Style.dim("not available")])
        }
        let gauge = Gauge.linear(lidAngle, range: 180, width: Self.gaugeWidth, color: Style.cyan)
        return section("LID", unit: "°", rows: [gauge + " " + String(format: "%5.0f°", lidAngle)])
    }

    private var vibrationSection: [String] {
        let latest = vibrationHistory.last ?? 0
        return section("VIBRATION", unit: "g", rows: [
            Gauge.sparkline(vibrationHistory, range: 0.05, width: 60) + " " + String(format: "%6.3f", latest),
        ])
    }

    // MARK: Layout

    private func section(_ title: String, unit: String, rows: [String]) -> [String] {
        [Style.bold(title) + " " + Style.dim(unit)] + rows
    }

    private func columns(_ left: [String], _ right: [String]) -> [String] {
        (0..<max(left.count, right.count)).map { row in
            let leftCell = row < left.count ? left[row] : ""
            let rightCell = row < right.count ? right[row] : ""
            return "  " + leftCell.padded(to: Self.columnWidth) + rightCell
        }
    }
}
