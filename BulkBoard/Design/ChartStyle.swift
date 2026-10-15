import Charts
import SwiftUI

/// Chart series colors, one per entity, stepped separately for light and dark surfaces.
/// Steps come from a palette validated for CVD separation and contrast (see the dataviz notes in CONTRIBUTING).
/// Every chart plots a single entity color; reference marks use neutral text tokens.
enum ChartPalette {
    static let calories = Color(light: 0xEDA100, dark: 0xC98500)
    static let protein = Color(light: 0xEB6834, dark: 0xD95926)
    static let weight = Color(light: 0xEB6834, dark: 0xD95926)
    static let strength = Color(light: 0xEB6834, dark: 0xD95926)
    static let volume = Color(light: 0x2A78D6, dark: 0x3987E5)
    static let court = Color(light: 0x1BAF7A, dark: 0x199E70)
    static let neutral = Theme.textSecondary
}

extension View {
    /// Recessive grid and axes in text tokens.
    func bulkChartAxes(yLabel: String? = nil) -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textSecondary).font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textSecondary).font(.system(size: 10))
                }
            }
            .chartPlotStyle { plot in plot.background(Color.clear) }
    }
}

/// Tooltip bubble for chart hover readouts. Text uses text tokens; the swatch carries identity.
struct ChartTooltip: View {
    var title: String
    var rows: [(color: Color?, label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textPrimary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    if let color = row.color {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                    }
                    Text(row.label).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(row.value).foregroundStyle(Theme.textPrimary).monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(8)
        .frame(minWidth: 130)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

/// Legend row for charts with more than one mark type.
struct ChartLegend: View {
    var items: [(color: Color, label: String, dashed: Bool, dot: Bool)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    if item.dot {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                    } else {
                        Capsule()
                            .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: item.dashed ? [4, 3] : []))
                            .frame(width: 18, height: 2)
                    }
                    Text(item.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
