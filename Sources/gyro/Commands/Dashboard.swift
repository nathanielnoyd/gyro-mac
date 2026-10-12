import ArgumentParser
import Foundation
import GyroKit
import Synchronization

struct Dashboard: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show every sensor in a live, full-screen dashboard.",
        discussion: """
            The same instruments as the Gyro app: a trace of each axis, an artificial
            horizon, the lid angle and a seismograph that marks recognized gestures.
            Run with sudo to include the accelerometer and gyroscope.

            Keys: space pauses, z makes the current heading zero yaw, q quits.
            """
    )

    @Flag(help: .hidden)
    var demo = false

    func run() async throws {
        guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else {
            throw CLIError(description: "The dashboard needs a terminal. To save or pipe readings, use gyro stream.")
        }
        let lid = try? LidAngleSensor()
        let feed = demo ? MotionFeed(samples: SimulatedMotion.samples()) : try? MotionFeed()
        let motionTask = feed.map { feed in Task { await feed.run() } }
        defer { motionTask?.cancel() }

        let source: DashboardView.Source =
            if feed == nil {
                .unavailable(Self.motionUnavailableReason)
            } else {
                demo ? .simulated : .live
            }
        var view = DashboardView(source: source)
        let screen = TerminalScreen()
        defer { screen.restore() }

        while true {
            while let key = screen.readKey() {
                switch key {
                case "q", "Q", .controlC: return
                case "z", "Z": feed?.zeroYaw()
                case " ", "p", "P": view.isPaused.toggle()
                default: break
                }
            }

            if let feed {
                let frame = feed.takeFrame()
                if !view.isPaused {
                    view.update(with: frame)
                }
            }
            if !view.isPaused {
                view.lidAngle = try? lid?.angle()
            }
            screen.draw(view.render(size: screen.size))

            try await Task.sleep(for: .milliseconds(33))
        }
    }

    private static var motionUnavailableReason: String {
        MotionSensor.isPresent
            ? "The accelerometer and gyroscope only report to root."
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
        /// Tap groups detected since the previous frame, recognized or not.
        var taps: [MotionEvent]
        /// Built-in gestures recognized since the previous frame.
        var recognitions: [GestureRecognizer.Recognition]
        /// The ongoing gesture, such as typing, if one is happening.
        var activeActivity: String?
    }

    private struct State {
        var tracker = MotionTracker()
        var vibration = VibrationMeter()
        var detector = MotionEventDetector()
        var recognizer = GestureRecognizer(
            candidates: GesturePreset.all.map {
                GestureRecognizer.Candidate(id: $0.id, signature: $0.signature)
            })
        var sampleCount = 0
        var taps: [MotionEvent] = []
        var recognitions: [GestureRecognizer.Recognition] = []
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
                    state.vibration.process(acceleration: sample.value)
                }
                for event in state.detector.process(sample) {
                    if event.kind == .taps {
                        state.taps.append(event)
                    }
                    state.recognitions += state.recognizer.recognize(event)
                }
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer {
                state.sampleCount = 0
                state.taps.removeAll()
                state.recognitions.removeAll()
            }
            return Frame(
                snapshot: state.tracker.snapshot,
                sampleCount: state.sampleCount,
                vibration: state.vibration.takePeak(),
                taps: state.taps,
                recognitions: state.recognitions,
                activeActivity: state.recognizer.activeActivity
            )
        }
    }

    func zeroYaw() {
        state.withLock { $0.tracker.resetAttitude() }
    }
}

// MARK: - View

/// The dashboard's layout: the app's instrument panels, arranged to fit the terminal.
private struct DashboardView {
    enum Source {
        case live, simulated
        case unavailable(String)
    }

    struct Point {
        var time: Double
        var acceleration: Vector3
        var rotationRate: Vector3
        var vibration: Double
    }

    /// A tap or gesture to mark on the vibration trace.
    struct Marker {
        var time: Double
        /// The recognized gesture, or `nil` for unrecognized taps.
        var gesture: String?
    }

    let source: Source
    var lidAngle: Double?
    var isPaused = false

    private var snapshot = MotionSnapshot()
    private var history: [Point] = []
    private var markers: [Marker] = []
    private var sampleRate = SampleRateMeter()
    private var toast: (recognition: GestureRecognizer.Recognition, shown: ContinuousClock.Instant)?
    private var activeActivity: String?

    /// Seconds of history shown in the traces.
    private static let historyDuration = 6.0
    private static let toastDuration = Duration.seconds(2.5)
    private static let maximumWidth = 120
    /// The narrowest width that fits two columns of panels.
    private static let twoColumnWidth = 78

    init(source: Source) {
        self.source = source
    }

    private var showsMotion: Bool {
        if case .unavailable = source { false } else { true }
    }

    mutating func update(with frame: MotionFeed.Frame) {
        snapshot = frame.snapshot
        sampleRate.record(frame.sampleCount, at: snapshot.timestamp)
        activeActivity = frame.activeActivity

        history.append(
            Point(
                time: snapshot.timestamp, acceleration: snapshot.acceleration, rotationRate: snapshot.rotationRate,
                vibration: frame.vibration))
        let cutoff = snapshot.timestamp - Self.historyDuration
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }

        for recognition in frame.recognitions where recognition.phase != .ended {
            markers.append(Marker(time: recognition.event.time, gesture: recognition.id))
            toast = (recognition, .now)
        }
        for tap in frame.taps where !frame.recognitions.contains(where: { $0.event.time == tap.time }) {
            markers.append(Marker(time: tap.time, gesture: nil))
        }
        markers.removeAll { $0.time < cutoff }
    }

    func render(size: (columns: Int, rows: Int)) -> [String] {
        let width = min(size.columns - 2, Self.maximumWidth)
        let margin = String(repeating: " ", count: max((size.columns - width) / 2, 0))

        var panels: [String]
        if width >= Self.twoColumnWidth {
            let columnWidth = (width - 1) / 2
            let left =
                showsMotion
                ? accelerationPanel(width: columnWidth) + rotationPanel(width: columnWidth)
                : setupPanel(width: columnWidth)
            let right = (showsMotion ? orientationPanel(width: columnWidth) : []) + lidPanel(width: columnWidth)
            panels = Self.columns(left, right, width: columnWidth)
        } else {
            panels =
                showsMotion
                ? accelerationPanel(width: width) + rotationPanel(width: width) + orientationPanel(width: width)
                    + lidPanel(width: width)
                : setupPanel(width: width) + lidPanel(width: width)
        }
        let vibration = showsMotion ? vibrationPanel(width: width) : []
        if panels.count + vibration.count + 2 <= size.rows {
            panels += vibration
        }

        let body = [header(width: width)] + panels.prefix(max(size.rows - 2, 0)) + [footer(width: width)]
        return body.map { margin + $0 }
    }

    // MARK: Status lines

    private func header(width: Int) -> String {
        var title = " " + Style.bold("gyro") + "  " + Style.dim(SystemInfo.modelIdentifier)

        var status: String
        var details: [String] = []
        if isPaused {
            status = Style.color(Palette.yellow, "❚❚") + " " + Style.bold("Paused")
        } else {
            switch source {
            case .live, .simulated:
                let isLive = if case .live = source { true } else { false }
                status =
                    Style.color(isLive ? Palette.green : Palette.purple, "●") + " "
                    + Style.bold(isLive ? "Live" : "Simulated")
                details = [
                    sampleRate.hertz.map { String(format: "%.0f Hz", $0) } ?? "starting",
                    snapshot.isStill ? "At rest" : "Moving",
                ]
            case .unavailable:
                status = Style.color(Palette.yellow, "●") + " " + Style.bold("Lid only")
            }
        }

        // In a narrow terminal, drop details from the right, then the model, so the rest stays readable.
        func fits() -> Bool {
            title.visibleWidth + 2 + status.visibleWidth + details.reduce(0) { $0 + 5 + $1.count } + 1 <= width
        }
        while !fits(), !details.isEmpty {
            details.removeLast()
        }
        if !fits() {
            title = " " + Style.bold("gyro")
        }
        status += details.map { Style.dim("  ·  " + $0) }.joined()
        return title.padded(to: width - status.visibleWidth - 1) + status + " "
    }

    private func footer(width: Int) -> String {
        var keys = ["q quit"]
        if showsMotion {
            keys = ["space " + (isPaused ? "resume" : "pause"), "z zero yaw"] + keys
        }
        let hints = Style.dim(keys.joined(separator: "   ")) + " "

        var message = ""
        if let toast, ContinuousClock.now - toast.shown < Self.toastDuration,
            let preset = GesturePreset.named(toast.recognition.id)
        {
            let strength = toast.recognition.event[.strength].map(MotionFeature.strength.format)
            let detail = toast.recognition.phase == .began ? "started" : strength ?? ""
            message =
                Style.color(Palette.cyan, String(preset.glyph)) + " " + Style.bold(preset.name) + "  "
                + Style.dim(detail)
        } else if let activeActivity, let preset = GesturePreset.named(activeActivity) {
            message =
                Style.color(Palette.cyan, String(preset.glyph)) + " " + Style.bold(preset.name) + "  "
                + Style.dim("ongoing")
        } else if showsMotion {
            message = Style.dim("Tap or type to try a gesture")
        }

        // When both don't fit, a gesture beats the key hints, and the key hints beat the tip.
        guard message.visibleWidth + hints.visibleWidth + 3 > width else {
            return (" " + message).padded(to: width - hints.visibleWidth) + hints
        }
        let isTip = toast == nil && activeActivity == nil
        return isTip ? hints.leftPadded(to: width) : " " + message
    }

    // MARK: Panels

    private func accelerationPanel(width: Int) -> [String] {
        Panel(
            title: "Acceleration",
            accessory: Style.dim(String(format: "%.3f g", snapshot.acceleration.magnitude)),
            width: width,
            lines: axisTraces(\.acceleration, width: width, minimumSpan: 0.02) { Self.signed($0, digits: 3) + " g" }
        ).render()
    }

    private func rotationPanel(width: Int) -> [String] {
        Panel(
            title: "Rotation",
            accessory: Style.dim(snapshot.isStill ? "◦ At rest" : "∿ Moving"),
            width: width,
            lines: axisTraces(\.rotationRate, width: width, minimumSpan: 1.5) { Self.signed($0, digits: 1) + " °/s" }
        ).render()
    }

    /// Two rows per axis: its name, a trace of the last few seconds, and the current value.
    private func axisTraces(
        _ value: KeyPath<Point, Vector3>, width: Int, minimumSpan: Double, format: (Double) -> String
    ) -> [String] {
        let valueWidth = 11
        let traceColumns = Panel.contentWidth(for: width) - valueWidth - 4
        let current = history.last?[keyPath: value] ?? .zero

        return [\Vector3.x, \Vector3.y, \Vector3.z].enumerated().flatMap { index, axis in
            let color = Palette.axes[index]
            let trace = Self.trace(
                history.map { ($0.time, $0[keyPath: value][keyPath: axis]) }, window: window, minimumSpan: minimumSpan,
                columns: traceColumns, rows: 2, color: color)
            let name = Style.bold(Style.color(color, ["x", "y", "z"][index]))
            let reading = Style.bold(format(current[keyPath: axis]).leftPadded(to: valueWidth))
            return [name + "  " + trace[0] + " " + reading, "   " + trace[1]]
        }
    }

    private func orientationPanel(width: Int) -> [String] {
        let attitude = snapshot.attitude
        let horizon = Self.horizon(attitude, diameter: 14)
        let readings = [("Pitch", attitude.pitch), ("Roll", attitude.roll), ("Yaw", attitude.yaw)].map {
            name, degrees in
            Style.color(Palette.secondary, name.padded(to: 7))
                + Style.bold((Self.signed(degrees, digits: 1) + "°").leftPadded(to: 8))
        }
        let rows = horizon.indices.map { row in
            let reading = row % 2 == 1 && row / 2 < readings.count ? readings[row / 2] : ""
            return horizon[row] + "     " + reading
        }
        return Panel(
            title: "Orientation", accessory: Style.dim("z zeroes yaw"), width: width,
            lines: Self.centered(rows, in: Panel.contentWidth(for: width))
        ).render()
    }

    private func lidPanel(width: Int) -> [String] {
        guard let lidAngle else {
            return Panel(
                title: "Lid", width: width,
                lines: ["", Style.dim("This Mac doesn't report its lid angle."), "", "", ""]
            ).render()
        }
        let dial = Self.lidDial(angle: lidAngle, columns: 18, rows: 5)
        // Sized for the widest angle, so the dial doesn't shift as digits come and go.
        let numerals = LargeNumerals.render(String(format: "%.0f°", lidAngle)).map { Style.bold($0.leftPadded(to: 13)) }
        let rows = dial.indices.map { row in
            dial[row] + "   " + ((1...3).contains(row) ? numerals[row - 1] : "")
        }
        return Panel(
            title: "Lid", accessory: Style.dim(Self.describe(lidAngle: lidAngle)), width: width,
            lines: Self.centered(rows, in: Panel.contentWidth(for: width))
        ).render()
    }

    private func vibrationPanel(width: Int) -> [String] {
        let peak = history.map(\.vibration).max() ?? 0
        let latest = history.last?.vibration ?? 0
        let valueWidth = 8
        let columns = Panel.contentWidth(for: width) - valueWidth - 1
        let chart = Self.seismograph(history, markers: markers, window: window, columns: columns, rows: 3)
        let reading = Style.bold(Style.color(Palette.gold, Self.milliG(latest).leftPadded(to: valueWidth)))
        let rows = chart.enumerated().map { row, line in line + " " + (row == 1 ? reading : "") }
        return Panel(title: "Vibration", accessory: Style.dim("peak " + Self.milliG(peak)), width: width, lines: rows)
            .render()
    }

    private func setupPanel(width: Int) -> [String] {
        guard case .unavailable(let reason) = source else { return [] }
        let inner = Panel.contentWidth(for: width)
        let hint =
            MotionSensor.isPresent
            ? [Style.dim("Run ") + Style.bold("sudo gyro") + Style.dim(" to see them.")]
            : Self.wrap("The lid angle still works.", width: inner).map(Style.dim)
        let lines = [""] + Self.wrap(reason, width: inner) + [""] + hint + [""]
        return Panel(title: "Motion", accessory: Style.color(Palette.yellow, "needs sudo"), width: width, lines: lines)
            .render()
    }

    // MARK: Instruments

    /// The time span the traces cover, ending at the newest reading.
    private var window: ClosedRange<Double> {
        let end = history.last?.time ?? Self.historyDuration
        return (end - Self.historyDuration)...end
    }

    /// A strip chart of one value over `window`.
    ///
    /// The y range follows the data with a floor of `minimumSpan`, so at rest the
    /// sensor's real noise shows as a fine trace, like a seismograph, instead of a flat line.
    private static func trace(
        _ points: [(time: Double, value: Double)], window: ClosedRange<Double>, minimumSpan: Double, columns: Int,
        rows: Int, color: TerminalColor
    ) -> [String] {
        var canvas = BrailleCanvas(columns: columns, rows: rows)
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return canvas.render() }
        let center = (low + high) / 2
        let half = max((high - low) / 2 * 1.3, minimumSpan / 2)

        func position(_ point: (time: Double, value: Double)) -> (x: Double, y: Double) {
            let x =
                (point.time - window.lowerBound) / (window.upperBound - window.lowerBound) * Double(canvas.width - 1)
            let y = (1 - (point.value - (center - half)) / (2 * half)) * Double(canvas.height - 1)
            return (x, y)
        }
        for (previous, next) in zip(points, points.dropFirst()) {
            canvas.line(from: position(previous), to: position(next), color)
        }
        return canvas.render()
    }

    /// An aircraft-style artificial horizon, as in the app.
    ///
    /// Lifting the front edge moves the horizon down, and lifting one side tilts it the other way.
    private static func horizon(_ attitude: Attitude, diameter: Int, pitchRange: Double = 60) -> [String] {
        var canvas = PixelCanvas(columns: diameter, rows: diameter / 2)
        let radius = Double(diameter) / 2
        // Half a pixel down, so a level horizon runs along a row of pixels, under the reticle, not between two.
        let horizon = -attitude.pitch / pitchRange * radius + 0.5
        let roll = attitude.roll * .pi / 180
        // Without color, only the ground and horizon are drawn, so their outline shows the tilt.
        let showsSky = Style.isEnabled

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                let (dx, dy) = (Double(x) + 0.5 - radius, Double(y) + 0.5 - radius)
                guard dx * dx + dy * dy <= radius * radius else { continue }

                // The pixel's position in the world, which is tilted opposite to the Mac.
                let worldX = cos(roll) * dx - sin(roll) * dy
                let worldY = sin(roll) * dx + cos(roll) * dy
                let height = horizon - worldY

                if abs(height) < 0.5 {
                    canvas[x, y] = Palette.white
                } else if showsSky,
                    [-20.0, 20].contains(where: { abs(worldY - (horizon + $0 / pitchRange * radius)) < 0.5 }),
                    abs(worldX) < 2
                {
                    canvas[x, y] = Palette.white.mixed(with: Palette.secondary, by: 0.5)
                } else if height > 0 {
                    canvas[x, y] =
                        showsSky ? Palette.skyLow.mixed(with: Palette.skyHigh, by: height / (radius * 1.5)) : nil
                } else {
                    canvas[x, y] = Palette.groundHigh.mixed(with: Palette.groundLow, by: -height / (radius * 1.5))
                }
            }
        }

        // The fixed reticle: wings either side of a center dot.
        let middle = canvas.height / 2
        let center = canvas.width / 2
        for x in [2, 3, center - 1, center, canvas.width - 4, canvas.width - 3] {
            canvas[x, middle] = Palette.yellow
        }
        return canvas.render()
    }

    /// A side view of a laptop: the base lies flat and the lid swings up from the hinge,
    /// under an arc filled as far as the lid is open.
    private static func lidDial(angle: Double, columns: Int, rows: Int) -> [String] {
        var canvas = BrailleCanvas(columns: columns, rows: rows)
        let hinge = (x: Double(canvas.width) / 2, y: Double(canvas.height - 1))
        let radius = min(hinge.x - 2, hinge.y - 1)
        let length = radius * 0.8

        func point(at degrees: Double, distance: Double, from origin: (x: Double, y: Double) = hinge) -> (
            x: Double, y: Double
        ) {
            let radians = degrees * .pi / 180
            return (origin.x + cos(radians) * distance, origin.y - sin(radians) * distance)
        }

        for degrees in stride(from: 0.0, through: 180, by: 7.5) {
            let dot = point(at: degrees, distance: radius)
            canvas.plot(Int(dot.x.rounded()), Int(dot.y.rounded()), Palette.border)
        }
        for degrees in stride(from: 0.0, through: min(max(angle, 0), 180), by: 1.5) {
            let dot = point(at: degrees, distance: radius)
            canvas.plot(Int(dot.x.rounded()), Int(dot.y.rounded()), Palette.accent)
        }
        canvas.line(from: hinge, to: point(at: 0, distance: length), Palette.secondary)
        let lidHinge = (x: hinge.x, y: hinge.y - 1)
        canvas.line(from: lidHinge, to: point(at: angle, distance: length, from: lidHinge), Palette.white)
        return canvas.render()
    }

    /// A seismograph of vibration over `window`, with taps and gestures marked along the top.
    private static func seismograph(
        _ points: [Point], markers: [Marker], window: ClosedRange<Double>, columns: Int, rows: Int
    ) -> [String] {
        var canvas = BrailleCanvas(columns: columns, rows: rows)
        guard canvas.width > 1 else { return canvas.render() }
        let peak = points.map(\.vibration).max() ?? 0
        let scale = max(0.008, peak * 1.15)
        let span = window.upperBound - window.lowerBound

        func x(_ time: Double) -> Int {
            Int(((time - window.lowerBound) / span * Double(canvas.width - 1)).rounded())
        }

        // The strongest vibration landing in each column of dots.
        var levels = [Double?](repeating: nil, count: canvas.width)
        for point in points {
            let column = x(point.time)
            guard levels.indices.contains(column) else { continue }
            levels[column] = max(levels[column] ?? 0, point.vibration)
        }

        let bottom = canvas.height - 1
        var previousTop: Int?
        for (column, level) in levels.enumerated() {
            guard let level else { continue }
            let top = bottom - Int((min(level / scale, 1) * Double(bottom)).rounded())
            if top < bottom {
                for y in (top + 1)...bottom {
                    canvas.plot(column, y, Palette.dimGold)
                }
            }
            // Join to the previous column so steep rises read as one stroke.
            for y in min(top, previousTop ?? top)...max(top, previousTop ?? top) {
                canvas.plot(column, y, Palette.gold)
            }
            previousTop = top
        }

        for marker in markers where window.contains(marker.time) {
            let column = x(marker.time) / 2
            if let gesture = marker.gesture.flatMap(GesturePreset.named) {
                canvas.put(gesture.glyph, column: column, row: 0, Palette.white)
            } else {
                canvas.put("╎", column: column, row: 0, Palette.secondary)
            }
        }
        return canvas.render()
    }

    // MARK: Formatting

    private static func describe(lidAngle: Double) -> String {
        switch lidAngle {
        case ..<1: "Closed"
        case ..<60: "Barely open"
        case ..<135: "Open"
        default: "Wide open"
        }
    }

    /// A value with a sign and fixed precision, so digits don't jump around, and no sign on zero.
    private static func signed(_ value: Double, digits: Int) -> String {
        let text = String(format: "%+.\(digits)f", value)
        return text.dropFirst().allSatisfy { $0 == "0" || $0 == "." } ? " " + text.dropFirst() : text
    }

    private static func milliG(_ g: Double) -> String {
        String(format: "%.0f mg", g * 1_000)
    }

    /// Breaks unstyled text into lines of at most `width` characters, between words.
    private static func wrap(_ text: String, width: Int) -> [String] {
        text.split(separator: " ").reduce(into: [""]) { lines, word in
            if lines[lines.count - 1].isEmpty {
                lines[lines.count - 1] = String(word)
            } else if lines[lines.count - 1].count + 1 + word.count <= width {
                lines[lines.count - 1] += " " + word
            } else {
                lines.append(String(word))
            }
        }
    }

    /// Moves a block of lines right, as one, to the middle of `width`.
    private static func centered(_ lines: [String], in width: Int) -> [String] {
        let blockWidth = lines.map(\.visibleWidth).max() ?? 0
        let indent = String(repeating: " ", count: max((width - blockWidth) / 2, 0))
        return lines.map { indent + $0 }
    }

    /// Places two stacks of panels side by side, padding the shorter one.
    private static func columns(_ left: [String], _ right: [String], width: Int) -> [String] {
        (0..<max(left.count, right.count)).map { row in
            let leftCell = row < left.count ? left[row] : ""
            let rightCell = row < right.count ? right[row] : ""
            return leftCell.padded(to: width) + " " + rightCell
        }
    }
}
