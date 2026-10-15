import Foundation
import GyroKit

/// The dashboard's layout: the app's instrument panels, arranged to fit the terminal.
struct DashboardView {
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
            title: "Lid", accessory: Style.dim(LidPosition(angle: lidAngle).description), width: width,
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

    /// The time span the traces cover, ending at the newest reading.
    private var window: ClosedRange<Double> {
        let end = history.last?.time ?? Self.historyDuration
        return (end - Self.historyDuration)...end
    }

    // MARK: Formatting

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
