import GyroKit
import RealityKit
import simd

/// A simple procedural MacBook whose orientation and lid follow the real sensors.
///
/// RealityKit's frame is y up with the viewer on +z. The sensor's frame is z up
/// with +y toward the hinge, so sensor (x, y, z) maps to RealityKit (x, z, -y).
final class MacBookEntity: Entity {
    private enum Size {
        static let width: Float = 0.31
        static let depth: Float = 0.215
        static let baseHeight: Float = 0.011
        static let lidHeight: Float = 0.005
    }

    /// Rotates around the lid's hinge.
    private let hinge = Entity()

    required init() {
        super.init()
        buildBase()
        buildLid()
    }

    /// Applies the estimated orientation and the lid angle in degrees (0 is closed).
    func apply(orientation: Quaternion, lidAngle: Double) {
        self.orientation = simd_quatf(
            ix: Float(orientation.x),
            iy: Float(orientation.z),
            iz: Float(-orientation.y),
            r: Float(orientation.w)
        )
        hinge.orientation = simd_quatf(angle: Float(-lidAngle * .pi / 180), axis: [1, 0, 0])
    }

    // MARK: Geometry

    private func buildBase() {
        let base = ModelEntity(
            mesh: .generateBox(width: Size.width, height: Size.baseHeight, depth: Size.depth, cornerRadius: 0.006),
            materials: [Materials.aluminum]
        )
        addChild(base)

        let top = Size.baseHeight / 2
        let keyboard = ModelEntity(
            mesh: .generateBox(width: Size.width * 0.86, height: 0.0008, depth: Size.depth * 0.42, cornerRadius: 0.0004),
            materials: [Materials.keyboard]
        )
        keyboard.position = [0, top, -Size.depth * 0.17]
        base.addChild(keyboard)

        let trackpad = ModelEntity(
            mesh: .generateBox(width: Size.width * 0.42, height: 0.0006, depth: Size.depth * 0.33, cornerRadius: 0.002),
            materials: [Materials.trackpad]
        )
        trackpad.position = [0, top, Size.depth * 0.27]
        base.addChild(trackpad)
    }

    private func buildLid() {
        hinge.position = [0, Size.baseHeight / 2, -Size.depth / 2]
        addChild(hinge)

        // Closed, the lid lies on the base and extends forward from the hinge.
        let lid = ModelEntity(
            mesh: .generateBox(width: Size.width, height: Size.lidHeight, depth: Size.depth, cornerRadius: 0.005),
            materials: [Materials.aluminum]
        )
        lid.position = [0, Size.lidHeight / 2, Size.depth / 2]
        hinge.addChild(lid)

        let display = ModelEntity(
            mesh: .generateBox(width: Size.width - 0.01, height: 0.0006, depth: Size.depth - 0.012, cornerRadius: 0.004),
            materials: [Materials.display]
        )
        display.position = [0, -Size.lidHeight / 2, 0]
        lid.addChild(display)
    }
}

private enum Materials {
    static let aluminum = SimpleMaterial(color: .init(white: 0.86, alpha: 1), roughness: 0.32, isMetallic: true)
    static let keyboard = SimpleMaterial(color: .init(white: 0.12, alpha: 1), roughness: 0.6, isMetallic: false)
    static let trackpad = SimpleMaterial(color: .init(white: 0.8, alpha: 1), roughness: 0.2, isMetallic: true)
    static let display = SimpleMaterial(color: .init(white: 0.04, alpha: 1), roughness: 0.15, isMetallic: false)
}
