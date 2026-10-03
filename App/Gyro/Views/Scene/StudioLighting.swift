import CoreGraphics
import RealityKit

/// Soft, product-shot lighting generated in code, so the app ships no image assets.
enum StudioLighting {
    /// An equirectangular environment: a dim room with one large softbox up front,
    /// which gives flat aluminum surfaces a gradient instead of a uniform tone.
    static func environment() async throws -> EnvironmentResource {
        try await EnvironmentResource(equirectangular: makeImage(), withName: "studio")
    }

    /// Lights `entity` and its descendants with the studio environment.
    static func apply(_ environment: EnvironmentResource, to entity: Entity) {
        entity.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.4))
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: entity))
    }

    private static func makeImage() -> CGImage {
        let width = 512, height = 256
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!

        // In an equirectangular image, the top row is straight up and the bottom row straight down.
        let stops: [(location: CGFloat, white: CGFloat)] = [
            (0.0, 0.55), (0.45, 0.35), (0.5, 0.28), (0.62, 0.15), (1.0, 0.08),
        ]
        let gradient = CGGradient(
            colorsSpace: space,
            colors: stops.map { CGColor(gray: $0.white, alpha: 1) } as CFArray,
            locations: stops.map(\.location)
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: height),
            end: CGPoint(x: 0, y: 0),
            options: []
        )

        // The softbox: a soft-edged bright panel above and in front of the model.
        let softbox = CGRect(x: width / 2 - 70, y: height - 95, width: 140, height: 60)
        context.setShadow(offset: .zero, blur: 30, color: CGColor(gray: 1, alpha: 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(softbox)
        return context.makeImage()!
    }
}
