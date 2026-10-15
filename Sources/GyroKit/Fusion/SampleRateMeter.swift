/// Measures how many readings arrive per second, averaged over windows of about one second.
public struct SampleRateMeter: Sendable {
    /// The most recent measurement, or `nil` until the first window completes.
    public private(set) var hertz: Double?

    private var windowStart: Double?
    private var count = 0

    /// Creates a meter with no measurement yet.
    public init() {}

    /// Records `count` readings received by `time`, in seconds.
    public mutating func record(_ count: Int, at time: Double) {
        guard let start = windowStart else {
            windowStart = time
            return
        }
        self.count += count
        if time - start >= 1 {
            hertz = Double(self.count) / (time - start)
            windowStart = time
            self.count = 0
        }
    }

    /// Discards the measurement and the window in progress.
    public mutating func reset() {
        self = SampleRateMeter()
    }
}
