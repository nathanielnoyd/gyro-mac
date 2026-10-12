import SwiftUI

/// A side view of a laptop: the base lies flat and the lid swings up from the hinge,
/// over a track showing the full range from closed to flat open.
struct LidDial: View {
    let angle: Double

    var body: some View {
        Canvas { context, size in
            let hinge = CGPoint(x: size.width / 2, y: size.height - 16)
            let radius = min(size.width / 2 - 24, size.height - 40)
            let length = radius * 0.82

            func point(at degrees: Double, distance: Double) -> CGPoint {
                let radians = degrees * .pi / 180
                return CGPoint(x: hinge.x + cos(radians) * distance, y: hinge.y - sin(radians) * distance)
            }

            var track = Path()
            track.addArc(center: hinge, radius: radius, startAngle: .zero, endAngle: .degrees(-180), clockwise: true)
            context.stroke(
                track, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            if angle > 0 {
                var progress = Path()
                progress.addArc(
                    center: hinge, radius: radius, startAngle: .zero, endAngle: .degrees(-angle), clockwise: true)
                context.stroke(progress, with: .color(.accentColor), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }

            for degrees in [0.0, 90, 180] {
                var tick = Path()
                tick.move(to: point(at: degrees, distance: radius + 10))
                tick.addLine(to: point(at: degrees, distance: radius + 18))
                context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
            }

            // The base, then the lid drawn just above it so it stays visible when closed.
            var base = Path()
            base.move(to: hinge)
            base.addLine(to: point(at: 0, distance: length))
            context.stroke(
                base, with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 9, lineCap: .round))

            var lid = Path()
            let lidHinge = CGPoint(x: hinge.x, y: hinge.y - 8)
            let radians = angle * .pi / 180
            lid.move(to: lidHinge)
            lid.addLine(to: CGPoint(x: lidHinge.x + cos(radians) * length, y: lidHinge.y - sin(radians) * length))
            context.stroke(lid, with: .color(.primary), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Lid angles", traits: .fixedLayout(width: 1100, height: 260)) {
    HStack {
        ForEach([0.0, 35, 105, 160], id: \.self) { angle in
            LidDial(angle: angle)
                .frame(width: 260, height: 160)
        }
    }
    .padding()
}
