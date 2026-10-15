import GyroKit
import SwiftUI

/// One of the sensor's three axes, with the color used for it everywhere in the app.
enum SensorAxis: String, CaseIterable, Identifiable {
    case x, y, z

    var id: Self { self }

    var color: Color {
        switch self {
        case .x: .red
        case .y: .green
        case .z: .blue
        }
    }
}

extension Vector3 {
    subscript(axis: SensorAxis) -> Double {
        switch axis {
        case .x: x
        case .y: y
        case .z: z
        }
    }
}

extension Double {
    /// A signed value with fixed precision, so digits don't jump around as it changes.
    func signedFormatted(fractionDigits: Int) -> String {
        formatted(.number.precision(.fractionLength(fractionDigits)).sign(strategy: .always(includingZero: false)))
    }
}
