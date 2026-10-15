import SwiftUI

/// The BulkBoard mark: a basketball on a court-navy tile with an upward "gain" chevron.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B2A4A), Color(hex: 0x0A1020)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .strokeBorder(Theme.hardwood.opacity(0.35), lineWidth: max(1, size * 0.02))
            Basketball()
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.06)
            Image(systemName: "chevron.up")
                .font(.system(size: size * 0.2, weight: .black))
                .foregroundStyle(Theme.scoreboard)
                .offset(y: -size * 0.34)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.hardwood.opacity(0.3), radius: size * 0.12, y: size * 0.04)
    }
}

struct Basketball: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let line = max(1.2, s * 0.045)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xFF9A4D), Theme.hardwood, Theme.hardwoodDeep],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.7))
                Path { path in
                    path.move(to: CGPoint(x: s / 2, y: 0))
                    path.addLine(to: CGPoint(x: s / 2, y: s))
                    path.move(to: CGPoint(x: 0, y: s / 2))
                    path.addLine(to: CGPoint(x: s, y: s / 2))
                    path.addArc(center: CGPoint(x: -s * 0.12, y: s / 2), radius: s * 0.48,
                                startAngle: .degrees(-62), endAngle: .degrees(62), clockwise: false)
                    path.move(to: CGPoint(x: s * 1.12 + s * 0.48 * cos(.pi * 118 / 180), y: s / 2 + s * 0.48 * sin(.pi * 118 / 180)))
                    path.addArc(center: CGPoint(x: s * 1.12, y: s / 2), radius: s * 0.48,
                                startAngle: .degrees(118), endAngle: .degrees(242), clockwise: false)
                }
                .stroke(Color(hex: 0x1A0E06).opacity(0.85), lineWidth: line)
                .clipShape(Circle())
            }
            .frame(width: s, height: s)
        }
    }
}
