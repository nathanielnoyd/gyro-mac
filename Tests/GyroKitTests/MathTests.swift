import Foundation
import Testing

@testable import GyroKit

struct Vector3Tests {
    @Test func arithmetic() {
        let a = Vector3(x: 1, y: 2, z: 3)
        let b = Vector3(x: -4, y: 0.5, z: 2)
        #expect(a + b == Vector3(x: -3, y: 2.5, z: 5))
        #expect(a - b == Vector3(x: 5, y: 1.5, z: 1))
        #expect(-a == Vector3(x: -1, y: -2, z: -3))
        #expect(a * 2 == Vector3(x: 2, y: 4, z: 6))
        #expect(a / 2 == Vector3(x: 0.5, y: 1, z: 1.5))

        var sum = a
        sum += b
        #expect(sum == a + b)
    }

    @Test func magnitudeAndNormalization() {
        let v = Vector3(x: 3, y: 4, z: 12)
        #expect(v.magnitude == 13)
        #expect(abs(v.normalized.magnitude - 1) < 1e-12)
        #expect(Vector3.zero.normalized == .zero)
    }

    @Test func crossProductIsRightHanded() {
        let x = Vector3(x: 1, y: 0, z: 0)
        let y = Vector3(x: 0, y: 1, z: 0)
        let z = Vector3(x: 0, y: 0, z: 1)
        #expect(x.cross(y) == z)
        #expect(y.cross(z) == x)
        #expect(z.cross(x) == y)
        #expect(y.cross(x) == -z)
    }
}

struct QuaternionTests {
    @Test func identityKeepsUpAlongZ() {
        #expect(Quaternion.identity.up == Vector3(x: 0, y: 0, z: 1))
    }

    @Test func normalizedHasUnitLength() {
        let q = Quaternion(w: 2, x: -1, y: 0.5, z: 3).normalized
        #expect(abs((q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z) - 1) < 1e-12)
        #expect(Quaternion(w: 0, x: 0, y: 0, z: 0).normalized == .identity)
    }

    @Test func angleAxisIgnoresAxisLength() {
        let short = Quaternion(angle: 1, axis: Vector3(x: 0, y: 0, z: 1))
        let long = Quaternion(angle: 1, axis: Vector3(x: 0, y: 0, z: 7))
        #expect(abs(short.w - long.w) < 1e-12 && abs(short.z - long.z) < 1e-12)
    }

    @Test(arguments: [Vector3(x: 1, y: 0, z: 0), Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: 0, z: 1)])
    func integratingAConstantRateMatchesAngleAxis(axis: Vector3) {
        // 45°/s for one second, in 1 ms steps.
        var q = Quaternion.identity
        for _ in 0..<1_000 {
            q = q.integrated(rate: axis * 45.radians, dt: 0.001)
        }
        let expected = Quaternion(angle: 45.radians, axis: axis)
        #expect(abs(q.w - expected.w) < 1e-6)
        #expect(abs(q.x - expected.x) < 1e-6)
        #expect(abs(q.y - expected.y) < 1e-6)
        #expect(abs(q.z - expected.z) < 1e-6)
    }

    @Test func roundTripsThroughJSON() throws {
        let q = Quaternion(angle: 0.3, axis: Vector3(x: 1, y: 2, z: 3))
        let decoded = try JSONDecoder().decode(Quaternion.self, from: JSONEncoder().encode(q))
        #expect(decoded == q)
    }
}
