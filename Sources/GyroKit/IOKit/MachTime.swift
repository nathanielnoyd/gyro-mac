import Darwin

/// Converts `mach_absolute_time` ticks, the clock IOKit uses for HID timestamps, to seconds.
enum MachTime {
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    static func seconds(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * secondsPerTick
    }

    static var now: Double {
        seconds(fromTicks: mach_absolute_time())
    }
}
