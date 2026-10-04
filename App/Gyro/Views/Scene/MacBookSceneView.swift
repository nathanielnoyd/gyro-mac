import GyroKit
import RealityKit
import SwiftUI

/// A 3D MacBook mirroring the real one's orientation and lid angle.
struct MacBookSceneView: View {
    let orientation: Quaternion
    let lidAngle: Double

    @State private var macBook = MacBookEntity()

    var body: some View {
        RealityView { content in
            content.add(macBook)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            // A three-quarter view from the front left, like a product shot.
            camera.look(at: [0, 0.0, 0], from: [-0.56, 0.7, 1.0], relativeTo: nil)
            content.add(camera)

            if let environment = try? await StudioLighting.environment() {
                StudioLighting.apply(environment, to: macBook)
            }

            // A gentle key light adds definition to the edges.
            let key = DirectionalLight()
            key.light.intensity = 400
            key.look(at: .zero, from: [0.4, 0.8, 0.6], relativeTo: nil)
            content.add(key)
        } update: { _ in
            macBook.apply(orientation: orientation, lidAngle: lidAngle)
        }
        .accessibilityLabel("3D model of the MacBook")
    }
}
