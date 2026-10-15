import SwiftUI

/// Faint half-court line art used behind onboarding and hero cards.
struct CourtBackdrop: View {
    var opacity: Double = 0.08

    var body: some View {
        Canvas { context, size in
            let lineColor = Theme.hardwood.opacity(opacity)
            let style = StrokeStyle(lineWidth: 2)
            let width = size.width
            let height = size.height
            let baseline = height * 0.98
            let centerX = width / 2

            // Key (paint) and free-throw circle
            let keyWidth = min(width * 0.28, 300)
            let keyHeight = min(height * 0.42, 340)
            let key = CGRect(x: centerX - keyWidth / 2, y: baseline - keyHeight, width: keyWidth, height: keyHeight)
            context.stroke(Path(key), with: .color(lineColor), style: style)
            let ftRadius = keyWidth / 2
            context.stroke(Path(ellipseIn: CGRect(x: centerX - ftRadius, y: key.minY - ftRadius, width: ftRadius * 2, height: ftRadius * 2)),
                           with: .color(lineColor), style: style)

            // Three-point arc
            var arc = Path()
            let arcRadius = min(width * 0.46, 620)
            arc.addArc(center: CGPoint(x: centerX, y: baseline), radius: arcRadius,
                       startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            context.stroke(arc, with: .color(lineColor), style: style)

            // Rim
            context.stroke(Path(ellipseIn: CGRect(x: centerX - 14, y: baseline - 58, width: 28, height: 28)),
                           with: .color(Theme.hardwood.opacity(opacity * 2)), style: StrokeStyle(lineWidth: 3))

            // Half-court circle at the top
            context.stroke(Path(ellipseIn: CGRect(x: centerX - 90, y: -90, width: 180, height: 180)),
                           with: .color(lineColor), style: style)
            var halfLine = Path()
            halfLine.move(to: CGPoint(x: 0, y: 0))
            halfLine.addLine(to: CGPoint(x: width, y: 0))
            context.stroke(halfLine, with: .color(lineColor), style: style)
        }
        .allowsHitTesting(false)
    }
}
