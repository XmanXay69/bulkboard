import Charts
import SwiftUI

/// Charts use the accent for data and neutral text tokens for everything else.
/// Each chart plots a single measure, so one color is enough.
enum ChartPalette {
    static let series = Theme.accent
    static let neutral = Theme.textSecondary
}

extension View {
    /// Recessive grid and axes in text tokens.
    func bulkChartAxes() -> some View {
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

/// Tooltip bubble for chart hover readouts.
struct ChartTooltip: View {
    var title: String
    var rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(row.value).foregroundStyle(Theme.textPrimary).monospacedDigit()
                }
                .font(.system(size: 11))
            }
        }
        .padding(8)
        .frame(minWidth: 130)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Legend row for charts with more than one mark type.
struct ChartLegend: View {
    var items: [(label: String, dashed: Bool, dot: Bool)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    if item.dot {
                        Circle().fill(ChartPalette.neutral).frame(width: 7, height: 7)
                    } else {
                        Capsule()
                            .stroke(item.dashed && item.label == "Goal" ? ChartPalette.neutral : ChartPalette.series,
                                    style: StrokeStyle(lineWidth: 2, dash: item.dashed ? [4, 3] : []))
                            .frame(width: 18, height: 2)
                    }
                    Text(item.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
