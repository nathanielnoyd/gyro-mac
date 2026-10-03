/// Decodes input reports from the SPU's accelerometer and gyroscope.
///
/// Each report is 22 bytes long. Bytes 6..<18 hold the x, y and z axes as
/// little-endian `Int32` values in 16.16 fixed point: g for the accelerometer,
/// degrees per second for the gyroscope.
enum IMUReport {
    static let length = 22
    static let axesOffset = 6
    static let scale = 65_536.0

    static func decode(_ report: UnsafeRawBufferPointer) -> Vector3? {
        guard report.count >= axesOffset + 3 * MemoryLayout<Int32>.size else { return nil }

        func axis(_ index: Int) -> Double {
            let offset = axesOffset + index * MemoryLayout<Int32>.size
            let raw = Int32(littleEndian: report.loadUnaligned(fromByteOffset: offset, as: Int32.self))
            return Double(raw) / scale
        }
        return Vector3(x: axis(0), y: axis(1), z: axis(2))
    }

    static func decode(_ report: [UInt8]) -> Vector3? {
        report.withUnsafeBytes(decode)
    }
}
