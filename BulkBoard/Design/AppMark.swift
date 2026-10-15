import SwiftUI

/// The BulkBoard mark: three rising bars on a graphite tile.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A3A40), Color(hex: 0x18181B)], startPoint: .top, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: size * 0.07) {
                bar(height: 0.26, color: .white.opacity(0.55))
                bar(height: 0.38, color: .white.opacity(0.8))
                bar(height: 0.52, color: Color(hex: 0x4C8DFF))
            }
            .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
    }

    private func bar(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
            .fill(color)
            .frame(width: size * 0.14, height: size * height)
    }
}
