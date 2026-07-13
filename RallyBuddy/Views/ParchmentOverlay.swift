import SwiftUI

/// Old-map dressing layered over the map in Explorer theme: an aged
/// vignette, a double-line frame, and a compass rose. Purely decorative —
/// never intercepts touches.
struct ParchmentOverlay: View {
    private let sepia = Color(red: 0.35, green: 0.25, blue: 0.13)

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [.clear, .clear, sepia.opacity(0.30)],
                center: .center,
                startRadius: 120,
                endRadius: 620
            )

            Rectangle()
                .strokeBorder(sepia.opacity(0.55), lineWidth: 2.5)
                .padding(6)
            Rectangle()
                .strokeBorder(sepia.opacity(0.4), lineWidth: 1)
                .padding(12)

            CompassRose()
                .frame(width: 64, height: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 18)
                .padding(.leading, 20)
                .opacity(0.85)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A classic eight-point compass rose drawn in ink.
struct CompassRose: View {
    private let ink = Color(red: 0.31, green: 0.23, blue: 0.13)
    private let parchment = Color(red: 0.95, green: 0.91, blue: 0.80)

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(parchment.opacity(0.8))
            )

            func star(points: Int, long: CGFloat, short: CGFloat, rotation: CGFloat) -> Path {
                var path = Path()
                for i in 0..<points {
                    let angle = rotation + CGFloat(i) * 2 * .pi / CGFloat(points)
                    let half = .pi / CGFloat(points)
                    let tip = CGPoint(
                        x: center.x + long * sin(angle),
                        y: center.y - long * cos(angle)
                    )
                    let left = CGPoint(
                        x: center.x + short * sin(angle - half),
                        y: center.y - short * cos(angle - half)
                    )
                    let right = CGPoint(
                        x: center.x + short * sin(angle + half),
                        y: center.y - short * cos(angle + half)
                    )
                    path.move(to: left)
                    path.addLine(to: tip)
                    path.addLine(to: right)
                    path.closeSubpath()
                }
                return path
            }

            // Diagonal (short) points under the cardinal (long) points.
            context.fill(
                star(points: 4, long: radius * 0.62, short: radius * 0.16, rotation: .pi / 4),
                with: .color(ink.opacity(0.55))
            )
            context.fill(
                star(points: 4, long: radius * 0.86, short: radius * 0.20, rotation: 0),
                with: .color(ink)
            )

            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius * 0.94, y: center.y - radius * 0.94,
                    width: radius * 1.88, height: radius * 1.88
                )),
                with: .color(ink.opacity(0.8)),
                lineWidth: 1.2
            )

            context.draw(
                Text("N")
                    .font(.system(size: radius * 0.34, weight: .bold, design: .serif))
                    .foregroundStyle(ink),
                at: CGPoint(x: center.x, y: center.y - radius * 0.6)
            )
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.93, green: 0.89, blue: 0.77)
        ParchmentOverlay()
    }
}
