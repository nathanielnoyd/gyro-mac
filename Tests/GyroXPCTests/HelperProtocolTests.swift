import Foundation
import GyroKit
import Testing

@testable import GyroXPC

struct HelperProtocolTests {
    @Test(arguments: [HelperRequest.startMotion, .stopMotion])
    func requestsRoundTrip(request: HelperRequest) throws {
        let decoded = try JSONDecoder().decode(HelperRequest.self, from: JSONEncoder().encode(request))
        #expect(String(describing: decoded) == String(describing: request))
    }

    @Test func motionEventsRoundTrip() throws {
        let samples = [
            MotionSample(kind: .acceleration, value: Vector3(x: 0, y: 0, z: -1), timestamp: 12.5),
            MotionSample(kind: .rotationRate, value: Vector3(x: 0.25, y: -3, z: 0), timestamp: 12.501),
        ]
        let data = try JSONEncoder().encode(HelperEvent.motion(samples))
        guard case .motion(let decoded) = try JSONDecoder().decode(HelperEvent.self, from: data) else {
            Issue.record("Decoded the wrong event")
            return
        }
        #expect(decoded == samples)
    }

    @Test func failureEventsRoundTrip() throws {
        let data = try JSONEncoder().encode(HelperEvent.failure("No IMU"))
        guard case .failure(let message) = try JSONDecoder().decode(HelperEvent.self, from: data) else {
            Issue.record("Decoded the wrong event")
            return
        }
        #expect(message == "No IMU")
    }

    /// The app registers the helper with this plist, so its names must match the ones the code uses.
    @Test func launchDaemonPlistMatchesTheService() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()  // GyroXPCTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()
            .appending(path: "App/LaunchDaemons/\(HelperService.launchDaemonPlistName)")
        let plist = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])

        #expect(plist["Label"] as? String == HelperService.machServiceName)
        let machServices = try #require(plist["MachServices"] as? [String: Bool])
        #expect(machServices == [HelperService.machServiceName: true])
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [HelperService.appBundleIdentifier])
    }
}
