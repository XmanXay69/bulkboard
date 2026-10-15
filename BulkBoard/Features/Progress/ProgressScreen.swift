import BulkCore
import Charts
import SwiftData
import SwiftUI

struct ProgressScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord
    @Query(sort: \WeightRecord.date) private var weights: [WeightRecord]
    @Query private var intake: [IntakeRecord]
    @Query(sort: \WorkoutSessionRecord.date) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \CourtSessionRecord.date) private var court: [CourtSessionRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]
    @Query(sort: \ExerciseRecord.name) private var exercises: [ExerciseRecord]

    @State private var range: ChartRange = .twelveWeeks
    @State private var showWeighInTable = false

    enum ChartRange: String, CaseIterable {
        case fourWeeks = "4W", twelveWeeks = "12W", all = "All"

        func start(from today: Date) -> Date {
            switch self {
            case .fourWeeks: today.adding(days: -28)
            case .twelveWeeks: today.adding(days: -84)
            case .all: .distantPast
            }
        }
    }

    private var units: UnitFormatter { UnitFormatter(system: profile.unitSystem) }

    var body: some View {
        let stats = ProgressService.stats(profile: profile, weights: weights, intake: intake, sessions: sessions,
                                          court: court, plan: plans.first)
        let start = range.start(from: .now.dayStart)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                PageHeader(title: "Progress", subtitle: "Weight, strength, volume and consistency") {
                    HStack(spacing: 10) {
                        Picker("Range", selection: $range) {
                            ForEach(ChartRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                        Button { appModel.activeSheet = .weighIn } label: { Label("Log weigh-in", systemImage: "scalemass.fill") }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }

                StatTilesRow(stats: stats, profile: profile, units: units)

                WeightChartCard(stats: stats, profile: profile, units: units, start: start)
                DisclosureGroup(isExpanded: $showWeighInTable) {
                    WeighInTable(weights: weights.reversed().filter { $0.date >= start }, units: units)
                } label: {
                    Text("Weigh-in data (\(weights.filter { $0.date >= start }.count))")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }

                HStack(alignment: .top, spacing: Theme.spacing) {
                    LiftChartCard(sessions: sessions.filter(\.isCompleted), exercises: exercises, units: units, start: start)
                    WeeklyBarsCard(title: "Lifting volume", subtitle: "Working-set tonnage per week",
                                   bars: stats.weeklyVolume.filter { $0.weekStart >= start.weekStart }
                                       .map { ($0.weekStart, Units.display(kg: $0.kg, in: profile.unitSystem)) },
                                   color: ChartPalette.series, valueText: { "\(Fmt.int($0)) \(units.massUnit)" })
                }
                HStack(alignment: .top, spacing: Theme.spacing) {
                    WeeklyBarsCard(title: "Court load", subtitle: "Minutes × RPE per week",
                                   bars: stats.weeklyCourtLoad.filter { $0.weekStart >= start.weekStart }.map { ($0.weekStart, Double($0.load)) },
                                   color: ChartPalette.series, valueText: { "\(Fmt.int($0)) load" })
                    WeeklySummaryCard(this: stats.thisWeek, last: stats.lastWeek, units: units)
                }
                HStack(alignment: .top, spacing: Theme.spacing) {
                    AdherenceChartCard(title: "Calories vs target", days: stats.adherence.filter { $0.day >= max(start, .now.adding(days: -42)) },
                                       value: \.kcalPercent, color: ChartPalette.series)
                    AdherenceChartCard(title: "Protein vs target", days: stats.adherence.filter { $0.day >= max(start, .now.adding(days: -42)) },
                                       value: \.proteinPercent, color: ChartPalette.series)
                }
            }
            .padding(24)
            .background(Theme.background)
        }
    }
}

// MARK: - Tiles

struct StatTilesRow: View {
    var stats: ProgressStats
    var profile: ProfileRecord
    var units: UnitFormatter

    var body: some View {
        HStack(spacing: 14) {
            tile {
                StatView(value: stats.latestTrendKg.map { units.weightValue($0) } ?? "–", label: "Trend weight", unit: units.massUnit, size: 26)
                if let perWeek = stats.projection?.kgPerWeek {
                    Text("\(units.signedWeight(perWeek, decimals: 2)) / week").font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            tile {
                StatView(value: stats.projection?.projectedGoalDate.map { $0.monthDay } ?? "–", label: "Projected goal date", size: 26)
                Text("Goal \(units.weight(profile.goalWeightKg)) by \(profile.targetDate.monthDay)")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            tile {
                StatView(value: "\(stats.currentStreak) days", label: "Macro streak", size: 26)
                Text("Best \(stats.longestStreak) days").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            tile {
                StatView(value: "\(stats.thisWeek.workoutsCompleted)/\(stats.thisWeek.workoutsPlanned)", label: "Workouts this week", size: 26)
                Text("\(stats.totalPRs) PRs all-time").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content).card(padding: 16)
    }
}

// MARK: - Weight

struct WeightChartCard: View {
    var stats: ProgressStats
    var profile: ProfileRecord
    var units: UnitFormatter
    var start: Date
    @State private var selected: Date?

    var body: some View {
        let system = profile.unitSystem
        let points = stats.weights.filter { $0.date >= start }
        let trend = stats.trend.filter { $0.date >= start }
        let projection = stats.projection?.line ?? []
        let goal = Units.display(kg: profile.goalWeightKg, in: system)
        let values = points.map { Units.display(kg: $0.kg, in: system) } + projection.map { Units.display(kg: $0.kg, in: system) } + [goal]
        let low = (values.min() ?? goal) - 2
        let high = (values.max() ?? goal) + 2

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bodyweight").font(.system(size: 15, weight: .bold))
                    Text("7-day average with a trend projection toward your goal").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                ChartLegend(items: [("Weigh-ins", false, true), ("7-day avg", false, false),
                                    ("Projection", true, false), ("Goal", true, false)])
            }
            if points.count < 2 {
                EmptyStateView(symbol: "scalemass", title: "Log a few weigh-ins", message: "Two or more weigh-ins draw the trend; three over five days unlock the projection.")
            } else {
                Chart {
                    ForEach(points, id: \.date) { point in
                        PointMark(x: .value("Date", point.date), y: .value("Weight", Units.display(kg: point.kg, in: system)))
                            .symbolSize(28)
                            .foregroundStyle(ChartPalette.neutral.opacity(0.55))
                    }
                    ForEach(trend, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", Units.display(kg: point.kg, in: system)),
                                 series: .value("Series", "Trend"))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(ChartPalette.series)
                    }
                    ForEach(projection, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", Units.display(kg: point.kg, in: system)),
                                 series: .value("Series", "Projection"))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                            .foregroundStyle(ChartPalette.series.opacity(0.8))
                    }
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(ChartPalette.neutral)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Goal \(units.weight(profile.goalWeightKg))").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                    if let selected, let nearest = nearest(to: selected, in: points) {
                        RuleMark(x: .value("Selected", nearest.date))
                            .foregroundStyle(Theme.textSecondary.opacity(0.4))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                let average = stats.trend.last { $0.date <= nearest.date }
                                ChartTooltip(title: nearest.date.shortDay, rows: [
                                    ("Weigh-in", units.weight(nearest.kg)),
                                    ("7-day avg", average.map { units.weight($0.kg) } ?? "–"),
                                ])
                            }
                    }
                }
                .chartYScale(domain: low...high)
                .chartXSelection(value: ScreenshotDirector.isCapturing ? .constant(nil) : $selected)
                .bulkChartAxes()
                .frame(height: 260)
            }
        }
        .card()
    }

    private func nearest(to date: Date, in points: [WeightPoint]) -> WeightPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

struct WeighInTable: View {
    @Environment(\.modelContext) private var context
    var weights: [WeightRecord]
    var units: UnitFormatter

    var body: some View {
        VStack(spacing: 0) {
            ForEach(weights.prefix(60)) { record in
                HStack {
                    Text(record.date.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if record.isDemo { DemoBadge() }
                    Text(units.weight(record.weightKg)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Button {
                        context.delete(record)
                        try? context.save()
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        .help("Delete weigh-in")
                }
                .font(.system(size: 12))
                .padding(.vertical, 5)
                Divider().opacity(0.4)
            }
        }
        .padding(.top, 6)
    }
}

struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var units: UnitSystem
    var last: Double?
    @State private var date = Date.now
    @State private var value = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "scalemass.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                Text("Log weigh-in").font(.system(size: 22, weight: .semibold))
            }
            Form {
                DatePicker("When", selection: $date)
                NumberField(label: "Weight", value: $value, unit: units.massLabel)
            }
            .formStyle(.grouped)
            Text("Same time each morning, after the bathroom, before food gives the cleanest trend.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    let record = WeightRecord(date: date, weightKg: Units.kg(fromDisplay: value, in: units))
                    context.insert(record)
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(value < 50)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { value = ((last.map { Units.display(kg: $0, in: units) } ?? 0) * 10).rounded() / 10 }
    }
}

// MARK: - Strength and volume

struct LiftChartCard: View {
    var sessions: [WorkoutSessionRecord]
    var exercises: [ExerciseRecord]
    var units: UnitFormatter
    var start: Date
    @State private var exerciseID: UUID?
    @State private var selected: Date?

    private var logged: [LoggedSet] { sessions.flatMap(\.loggedSets) }

    /// Exercises with weighted history, most-logged first.
    private var options: [ExerciseRecord] {
        let counts = Dictionary(grouping: logged.filter { $0.weightKg > 0 }, by: \.exerciseID).mapValues(\.count)
        return exercises.filter { counts[$0.id] != nil }.sorted { counts[$0.id]! > counts[$1.id]! }
    }

    var body: some View {
        let options = options
        let current = exerciseID ?? options.first { $0.seedKey == "bench_press" }?.id ?? options.first?.id
        let history = current.map { Summaries.e1RMHistory(logged, exerciseID: $0) }?.filter { $0.date >= start } ?? []
        let prDays: Set<Date> = Set(sessions.filter { session in
            session.sets.contains { $0.exerciseID == current && $0.prKinds.contains(.bestE1RM) }
        }.map { $0.date.dayStart })

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated 1RM").font(.system(size: 15, weight: .bold))
                    Text("Best set per session (Epley)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Picker("Lift", selection: Binding(get: { current }, set: { exerciseID = $0 })) {
                    ForEach(options) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            if history.count < 2 {
                EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: "Not enough sessions", message: "Log this lift a couple of times to see the curve.")
            } else {
                Chart {
                    ForEach(history, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("e1RM", Units.display(kg: point.kg, in: units.system)))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(ChartPalette.series)
                        if prDays.contains(point.date) {
                            PointMark(x: .value("Date", point.date), y: .value("e1RM", Units.display(kg: point.kg, in: units.system)))
                                .symbolSize(70)
                                .foregroundStyle(ChartPalette.series)
                                .symbol { Circle().fill(ChartPalette.series).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.surface, lineWidth: 2)) }
                        }
                    }
                    if let selected, let point = history.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                        RuleMark(x: .value("Selected", point.date))
                            .foregroundStyle(Theme.textSecondary.opacity(0.4))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartTooltip(title: point.date.shortDay, rows: [
                                    ("e1RM", units.weight(point.kg, decimals: 0)),
                                    (prDays.contains(point.date) ? "PR session" : "", ""),
                                ])
                            }
                    }
                }
                .chartXSelection(value: ScreenshotDirector.isCapturing ? .constant(nil) : $selected)
                .chartYScale(domain: .automatic(includesZero: false))
                .bulkChartAxes()
                .frame(height: 200)
                Text("Dots mark sessions that set an e1RM PR.").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

struct WeeklyBarsCard: View {
    var title: String
    var subtitle: String
    var bars: [(Date, Double)]
    var color: Color
    var valueText: (Double) -> String
    @State private var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            if bars.isEmpty {
                EmptyStateView(symbol: "chart.bar", title: "No data yet", message: "Log sessions to fill this in.")
            } else {
                Chart {
                    ForEach(bars, id: \.0) { week, value in
                        BarMark(x: .value("Week", week, unit: .weekOfYear), y: .value(title, value), width: .ratio(0.7))
                            .foregroundStyle(color.opacity(selected == nil || isSelected(week) ? 1 : 0.45))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    }
                    if let selected, let bar = bars.first(where: { isSelected($0.0, selected: selected) }) {
                        RuleMark(x: .value("Week", bar.0, unit: .weekOfYear))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartTooltip(title: "Week of \(bar.0.monthDay)", rows: [(title, valueText(bar.1))])
                            }
                    }
                }
                .chartXSelection(value: ScreenshotDirector.isCapturing ? .constant(nil) : $selected)
                .bulkChartAxes()
                .frame(height: 200)
            }
        }
        .card()
    }

    private func isSelected(_ week: Date, selected: Date? = nil) -> Bool {
        guard let date = selected ?? self.selected else { return false }
        return date.weekStart == week.weekStart
    }
}

struct AdherenceChartCard: View {
    var title: String
    var days: [DayAdherence]
    var value: KeyPath<DayAdherence, Double>
    var color: Color
    @State private var selected: Date?

    var body: some View {
        let isCalories = value == \DayAdherence.kcalPercent
        let hits = days.filter { isCalories ? abs($0.kcalPercent - 1) <= 0.1 : $0.proteinPercent >= 0.9 }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text("Logged intake as % of that day's target · band = on target").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(hits)/\(days.count) days").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            if days.isEmpty {
                EmptyStateView(symbol: "fork.knife", title: "Nothing logged yet", message: "Check meals off as you eat them.")
            } else {
                Chart {
                    RectangleMark(yStart: .value("Low", 90), yEnd: .value("High", 110))
                        .foregroundStyle(Theme.textSecondary.opacity(0.1))
                    RuleMark(y: .value("Target", 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(days, id: \.day) { day in
                        BarMark(x: .value("Day", day.day, unit: .day), y: .value("Percent", min(140, day[keyPath: value] * 100)), width: .ratio(0.7))
                            .foregroundStyle(color.opacity(selected == nil || Calendar.bulk.isDate(day.day, inSameDayAs: selected!) ? 1 : 0.45))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                    }
                    if let selected, let day = days.first(where: { Calendar.bulk.isDate($0.day, inSameDayAs: selected) }) {
                        RuleMark(x: .value("Day", day.day, unit: .day))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                let isCalories = value == \DayAdherence.kcalPercent
                                ChartTooltip(title: day.day.shortDay, rows: [
                                    ("Eaten", isCalories ? "\(Fmt.int(day.eaten.kcal)) kcal" : "\(Fmt.int(day.eaten.protein)) g"),
                                    ("Target", isCalories ? "\(Fmt.int(day.target.kcal)) kcal" : "\(Fmt.int(day.target.protein)) g"),
                                    ("Of target", "\(Fmt.int(day[keyPath: value] * 100))%"),
                                ])
                            }
                    }
                }
                .chartYScale(domain: 0...140)
                .chartXSelection(value: ScreenshotDirector.isCapturing ? .constant(nil) : $selected)
                .bulkChartAxes()
                .frame(height: 180)
            }
        }
        .card()
    }
}

struct WeeklySummaryCard: View {
    var this: WeeklySummary
    var last: WeeklySummary
    var units: UnitFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly summary").font(.system(size: 15, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    SectionLabel("This week")
                    SectionLabel("Last week")
                }
                row("Days hit macros", "\(this.daysHitMacros)/7", "\(last.daysHitMacros)/7")
                row("Workouts", "\(this.workoutsCompleted)/\(this.workoutsPlanned)", "\(last.workoutsCompleted)/\(last.workoutsPlanned)")
                row("Court sessions", "\(this.courtSessions)", "\(last.courtSessions)")
                row("PRs", "\(this.prs)", "\(last.prs)")
                row("Lifting volume", units.volume(this.liftingVolumeKg), units.volume(last.liftingVolumeKg))
                row("Weight change", this.weightChangeKg.map { units.signedWeight($0) } ?? "–", last.weightChangeKg.map { units.signedWeight($0) } ?? "–")
            }
        }
        .card()
    }

    private func row(_ label: String, _ current: String, _ previous: String) -> some View {
        GridRow {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Text(current).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(previous).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
    }
}
