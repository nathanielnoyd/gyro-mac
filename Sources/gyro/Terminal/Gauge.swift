/// Text-mode gauges. Every gauge is exactly `width` visible characters wide.
enum Gauge {
    /// A bar growing left or right from a center mark, for signed values.
    static func centered(_ value: Double, range: Double, width: Int, color: (String) -> String) -> String {
        let half = width / 2
        let filled = cells(abs(value) / range, of: half)
        let empty = half - filled

        let left = value < 0
            ? Style.dim(track(empty)) + color(bar(filled))
            : Style.dim(track(half))
        let right = value > 0
            ? color(bar(filled)) + Style.dim(track(empty))
            : Style.dim(track(half))
        return left + Style.dim("┼") + right
    }

    /// A bar filling from the left, for values between 0 and `range`.
    static func linear(_ value: Double, range: Double, width: Int, color: (String) -> String) -> String {
        let filled = cells(value / range, of: width)
        return color(bar(filled)) + Style.dim(track(width - filled))
    }

    /// A sparkline of recent values between 0 and `range`, oldest first.
    static func sparkline(_ values: [Double], range: Double, width: Int) -> String {
        let blocks = Array("▁▂▃▄▅▆▇█")
        let recent = values.suffix(width)
        let line = recent.map { blocks[cells($0 / range, of: blocks.count - 1)] }
        return String(repeating: " ", count: width - recent.count) + String(line)
    }

    private static func cells(_ fraction: Double, of total: Int) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(max(fraction, 0), 1) * Double(total)).rounded())
    }

    private static func bar(_ count: Int) -> String { String(repeating: "━", count: count) }
    private static func track(_ count: Int) -> String { String(repeating: "─", count: count) }
}
