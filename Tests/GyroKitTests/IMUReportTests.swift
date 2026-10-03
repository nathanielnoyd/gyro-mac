import Testing
@testable import GyroKit

struct IMUReportTests {
    /// Builds a report with the given axes encoded as 16.16 fixed point.
    private func report(x: Double, y: Double, z: Double) -> [UInt8] {
        var bytes = [UInt8](repeating: 0xAA, count: IMUReport.axesOffset)
        for axis in [x, y, z] {
            withUnsafeBytes(of: Int32(axis * IMUReport.scale).littleEndian) { bytes += $0 }
        }
        bytes += [0, 0, 0, 0]
        return bytes
    }

    @Test func decodesFixedPointAxes() throws {
        let value = try #require(IMUReport.decode(report(x: 0.5, y: -0.25, z: 1)))
        #expect(value == Vector3(x: 0.5, y: -0.25, z: 1))
    }

    @Test func decodesLargeGyroRates() throws {
        let value = try #require(IMUReport.decode(report(x: 2_000, y: -2_000, z: 0)))
        #expect(value == Vector3(x: 2_000, y: -2_000, z: 0))
    }

    @Test func reportHasExpectedLength() {
        #expect(report(x: 0, y: 0, z: 0).count == IMUReport.length)
    }

    @Test func rejectsTruncatedReports() {
        #expect(IMUReport.decode([UInt8](repeating: 0, count: 17)) == nil)
    }
}
