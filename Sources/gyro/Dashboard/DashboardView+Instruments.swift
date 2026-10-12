import Foundation
import GyroKit

/// The dashboard's instruments, each drawn to a given size, apart from the layout.
extension DashboardView {
    /// A strip chart of one value over `window`.
    ///
    /// The y range follows the data with a floor of `minimumSpan`, so at rest the
    /// sensor's real noise shows as a fine trace, like a seismograph, instead of a flat line.
    static func trace(
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
    static func horizon(_ attitude: Attitude, diameter: Int, pitchRange: Double = 60) -> [String] {
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
    static func lidDial(angle: Double, columns: Int, rows: Int) -> [String] {
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
    static func seismograph(
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
}
