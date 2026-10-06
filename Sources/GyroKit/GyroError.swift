import IOKit

/// Errors thrown by GyroKit.
public enum GyroError: Error, Equatable, Sendable {
    /// The sensor does not exist on this Mac.
    case sensorUnavailable(SPUSensor)
    /// The sensor only streams data to processes running as root.
    case requiresRoot(SPUSensor)
    /// The sensor returned a report GyroKit could not decode.
    case malformedReport(SPUSensor)
    /// An IOKit call failed.
    case ioKit(operation: String, code: IOReturn)
    /// A motion recording has a line GyroKit could not read.
    case invalidRecording(line: Int)
}

extension GyroError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .sensorUnavailable(let sensor):
            "This Mac has no \(sensor.displayName.lowercased())."
        case .requiresRoot(let sensor):
            "Reading the \(sensor.displayName.lowercased()) requires root privileges."
        case .malformedReport(let sensor):
            "The \(sensor.displayName.lowercased()) returned an unexpected report."
        case .ioKit(let operation, let code):
            "\(operation) failed: \(String(cString: mach_error_string(code))) (0x\(String(UInt32(bitPattern: code), radix: 16)))"
        case .invalidRecording(let line):
            "Line \(line) of the recording isn't a motion reading."
        }
    }
}

/// Throws ``GyroError/ioKit(operation:code:)`` unless `result` is `kIOReturnSuccess`.
func ioCheck(_ result: IOReturn, _ operation: String) throws(GyroError) {
    guard result == kIOReturnSuccess else {
        throw .ioKit(operation: operation, code: result)
    }
}
