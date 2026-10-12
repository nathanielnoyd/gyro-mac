import Darwin
import IOKit

/// A sensor connected to the Sensor Processing Unit (SPU).
///
/// The SPU is the always-on coprocessor in Apple Silicon Macs that handles
/// motion, lid-angle and ambient-light sensing. Each sensor appears in the
/// I/O Registry as an `AppleSPUHIDDevice` with a distinct HID usage.
/// None of this is public API, so names and report formats come from
/// reverse engineering and may change between macOS releases.
public enum SPUSensor: String, CaseIterable, Sendable {
    case accelerometer
    case gyroscope
    case lidAngle = "lid-angle"
    case ambientLight = "ambient-light"

    /// The sensor's name in sentence case, such as “Lid angle sensor”.
    public var displayName: String {
        switch self {
        case .accelerometer: "Accelerometer"
        case .gyroscope: "Gyroscope"
        case .lidAngle: "Lid angle sensor"
        case .ambientLight: "Ambient light sensor"
        }
    }

    /// Whether the sensor only reports data to processes running as root.
    public var requiresRoot: Bool {
        switch self {
        case .accelerometer, .gyroscope: true
        case .lidAngle, .ambientLight: false
        }
    }

    /// Whether this Mac has the sensor.
    public var isPresent: Bool {
        var found = false
        Self.forEachRegistryEntry(ofClass: Self.deviceClass, matching: self) { _ in
            found = true
            return false
        }
        return found
    }

    var usage: (page: Int, id: Int) {
        switch self {
        case .accelerometer: (0xFF00, 0x03)
        case .gyroscope: (0xFF00, 0x09)
        case .lidAngle: (0x0020, 0x8A)
        case .ambientLight: (0xFF00, 0x04)
        }
    }
}

// MARK: - Device access

extension SPUSensor {
    private static let deviceClass = "AppleSPUHIDDevice"
    private static let driverClass = "AppleSPUHIDDriver"

    static var isRunningAsRoot: Bool { geteuid() == 0 }

    /// Creates a HID device for the sensor.
    func makeDevice() throws(GyroError) -> HIDDevice {
        var device: HIDDevice?
        Self.forEachRegistryEntry(ofClass: Self.deviceClass, matching: self) { service in
            device = HIDDevice(service: service, label: rawValue)
            return device == nil
        }
        guard let device else { throw .sensorUnavailable(self) }
        return device
    }

    /// Asks the SPU driver to power the sensor and send reports every `interval`.
    ///
    /// The driver accepts these properties from any process but only applies them
    /// for root, so this throws ``GyroError/requiresRoot(_:)`` for everyone else.
    func enableReporting(interval: Duration) throws(GyroError) {
        guard Self.isRunningAsRoot else { throw .requiresRoot(self) }

        let microseconds = Int(interval / .microseconds(1))
        var result: Result<Void, GyroError> = .failure(.sensorUnavailable(self))
        Self.forEachRegistryEntry(ofClass: Self.driverClass, matching: self) { driver in
            result = Result { () throws(GyroError) in
                try IORegistry.setProperty(1, forKey: "SensorPropertyReportingState", of: driver)
                try IORegistry.setProperty(1, forKey: "SensorPropertyPowerState", of: driver)
                try IORegistry.setProperty(microseconds, forKey: "ReportInterval", of: driver)
            }
            return false
        }
        try result.get()
    }

    private static func forEachRegistryEntry(
        ofClass className: String,
        matching sensor: SPUSensor,
        _ body: (io_service_t) -> Bool
    ) {
        IORegistry.forEachService(ofClass: className) { service in
            let page = IORegistry.property("PrimaryUsagePage", of: service, as: Int.self)
            let usage = IORegistry.property("PrimaryUsage", of: service, as: Int.self)
            guard page == sensor.usage.page, usage == sensor.usage.id else { return true }
            return body(service)
        }
    }
}
