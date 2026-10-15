import BulkCore
import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord

    @Query(sort: \WeightRecord.date) private var weights: [WeightRecord]
    @Query private var intake: [IntakeRecord]
    @Query(sort: \WorkoutSessionRecord.date) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \CourtSessionRecord.date) private var court: [CourtSessionRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]
    @Query private var entries: [PlanEntryRecord]
    @Query private var foods: [FoodRecord]
    @Query private var recipes: [RecipeRecord]

    @State private var showWeighIn = false
    @State private var showQuickAdd = false
    @State private var showCourt = false
    @State private var showCoach = false

    private var today: Date { Date.now.dayStart }
    private var units: UnitFormatter { UnitFormatter(system: profile.unitSystem) }

    var body: some View {
        let stats = ProgressService.stats(profile: profile, weights: weights, intake: intake, sessions: sessions,
                                          court: court, plan: plans.first)
        let plannedDay = plans.first?.day(for: today)
        let dayType = plannedDay?.dayType ?? .lifting
        let target = profile.targets(latestWeightKg: weights.last?.weightKg).target(for: dayType)
        let todaysIntake = intake.filter { $0.day == today }
        let eaten = todaysIntake.map(\.macros).sum()
        let library = MealLibrary(foods: foods, recipes: recipes)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header(dayType: dayType, stats: stats)
                HStack(alignment: .top, spacing: Theme.spacing) {
                    TodayMacrosCard(eaten: eaten, target: target, dayType: dayType)
                    TodayWorkoutCard(day: plannedDay, sessions: sessions, court: court) {
                        appModel.section = .training
                        appModel.trainingTab = .log
                    } onLogCourt: { showCourt = true }
                        .frame(width: 360)
                }
                HStack(alignment: .top, spacing: Theme.spacing) {
                    TodayMealsCard(entries: entries.filter { $0.day == today }.sorted { $0.slotIndex < $1.slotIndex },
                                   intake: todaysIntake, library: library, target: target, onQuickAdd: { showQuickAdd = true }) {
                        appModel.section = .meals
                    }
                    VStack(spacing: Theme.spacing) {
                        WeightTrendCard(stats: stats, profile: profile, units: units) { showWeighIn = true }
                        StreakCard(stats: stats)
                    }
                    .frame(width: 360)
                }
            }
            .padding(24)
            .background(Theme.background)
        }
        .sheet(isPresented: $showWeighIn) { WeighInSheet(units: profile.unitSystem, last: weights.last?.weightKg) }
        .sheet(isPresented: $showQuickAdd) { QuickAddSheet(library: library) }
        .sheet(isPresented: $showCourt) {
            CourtSessionSheet(minutes: plannedDay?.block?.minutes ?? 60, kind: .conditioning)
        }
        .sheet(isPresented: $showCoach) { AskCoachSheet(profile: profile) }
    }

    private func header(dayType: DayType, stats: ProgressStats) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()), color: Theme.hardwood)
                HStack(spacing: 12) {
                    Text(dayType.title.uppercased())
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Theme.textPrimary)
                    DayTypeBadge(dayType: dayType, large: true)
                }
                Text(greeting(dayType)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if OllamaClient.shared.isAvailable {
                    Button { showCoach = true } label: { Label("Ask the coach", systemImage: "sparkles") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                }
                Button { showWeighIn = true } label: { Label("Weigh-in", systemImage: "scalemass.fill") }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button { showQuickAdd = true } label: { Label("Quick add food", systemImage: "plus") }
                    .buttonStyle(HardwoodButtonStyle(compact: true))
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    private func greeting(_ dayType: DayType) -> String {
        switch dayType {
        case .lifting: "Weight room today. Eat big, lift heavy."
        case .conditioning: "Court day. Carbs are up to fuel the runs."
        case .rest: "Recovery day. Hit protein, walk, sleep."
        }
    }
}

// MARK: - Cards

struct TodayMacrosCard: View {
    var eaten: Macros
    var target: Macros
    var dayType: DayType

    var body: some View {
        let remaining = target - eaten
        ScoreboardPanel {
            HStack(spacing: 26) {
                ZStack {
                    RingGauge(value: eaten.kcal, target: target.kcal, color: Theme.kcal, lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(Fmt.int(eaten.kcal)).font(.scoreboard(30)).foregroundStyle(Theme.kcal).contentTransition(.numericText())
                        Text("of \(Fmt.int(target.kcal)) kcal").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Eyebrow("Today's macros", color: Theme.hardwood)
                        Spacer()
                        if Adherence.isHit(eaten: eaten, target: target) {
                            Label("ON TARGET", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.net)
                        }
                    }
                    MacroBar(label: "Protein", value: eaten.protein, target: target.protein, color: Theme.protein)
                    MacroBar(label: "Carbs", value: eaten.carbs, target: target.carbs, color: Theme.carbs)
                    MacroBar(label: "Fat", value: eaten.fat, target: target.fat, color: Theme.fat)
                    Text(remaining.kcal > 0
                         ? "\(Fmt.int(remaining.kcal)) kcal and \(Fmt.int(max(0, remaining.protein))) g protein to go"
                         : "Target hit. \(Fmt.int(-remaining.kcal)) kcal over.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct TodayWorkoutCard: View {
    var day: PlannedDay?
    var sessions: [WorkoutSessionRecord]
    var court: [CourtSessionRecord]
    var onStart: () -> Void
    var onLogCourt: () -> Void
    @Query(sort: \ExerciseRecord.name) private var exercises: [ExerciseRecord]

    var body: some View {
        let todayLift = sessions.first { $0.isCompleted && Calendar.bulk.isDateInToday($0.date) }
        let todayCourt = court.first { Calendar.bulk.isDateInToday($0.date) }
        let active = sessions.first { !$0.isCompleted }
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("Today's session", color: Theme.hardwood)
                Spacer()
                if let day { DayTypeBadge(dayType: day.dayType) }
            }
            Text(day?.title ?? "No plan").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
            if let day {
                if !day.exercises.isEmpty {
                    ForEach(day.exercises.prefix(5)) { planned in
                        HStack {
                            Text(names[planned.exerciseID] ?? "Exercise").font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Text("\(planned.sets)×\(planned.repText)").font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.scoreboard)
                        }
                    }
                    if day.exercises.count > 5 {
                        Text("+\(day.exercises.count - 5) more").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                } else if let block = day.block {
                    ForEach(block.items.prefix(4), id: \.self) { Text("• \($0)").font(.system(size: 12)) }
                }
            }
            Spacer(minLength: 4)
            HStack {
                if let todayLift {
                    Label("Done · \(todayLift.prCount) PRs", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.net)
                        .font(.system(size: 12, weight: .bold))
                } else if let todayCourt {
                    Label("Logged \(todayCourt.minutes) min", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.net)
                        .font(.system(size: 12, weight: .bold))
                }
                Spacer()
                if active != nil {
                    Button { onStart() } label: { Label("Resume", systemImage: "play.fill") }.buttonStyle(HardwoodButtonStyle(compact: true))
                } else if day?.dayType == .lifting && todayLift == nil {
                    Button { onStart() } label: { Label("Start workout", systemImage: "play.fill") }.buttonStyle(HardwoodButtonStyle(compact: true))
                } else if day?.dayType == .conditioning && todayCourt == nil {
                    Button { onLogCourt() } label: { Label("Log hoops", systemImage: "basketball.fill") }.buttonStyle(HardwoodButtonStyle(compact: true))
                }
            }
        }
        .frame(minHeight: 186, alignment: .topLeading)
        .card()
    }
}

struct TodayMealsCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var entries: [PlanEntryRecord]
    var intake: [IntakeRecord]
    var library: MealLibrary
    var target: Macros
    var onQuickAdd: () -> Void
    var onOpenPlan: () -> Void

    var body: some View {
        let eatenIDs = Set(intake.compactMap(\.planEntryID))
        let extras = intake.filter { $0.planEntryID == nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("Today's meals", color: Theme.hardwood)
                Spacer()
                Button("Week plan", action: onOpenPlan).buttonStyle(GhostButtonStyle(compact: true))
            }
            if entries.isEmpty && extras.isEmpty {
                EmptyStateView(symbol: "fork.knife", title: "Nothing planned today", message: "Auto-fill your week in Meal Plan, or quick-add what you eat.",
                               actionTitle: "Open meal plan", action: onOpenPlan)
            }
            ForEach(entries) { entry in
                let eaten = eatenIDs.contains(entry.id)
                Button { toggle(entry) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: eaten ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(eaten ? Theme.net : Theme.textSecondary)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.slot.title.uppercased()).font(.eyebrow).tracking(1).foregroundStyle(Theme.textSecondary)
                            Text(library.name(for: entry) + (entry.servings != 1 ? " ×\(Fmt.number(entry.servings, maxDecimals: 2))" : ""))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(eaten ? Theme.textSecondary : Theme.textPrimary)
                                .strikethrough(eaten)
                        }
                        Spacer()
                        MacroPill(macros: library.macros(for: entry))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(extras) { record in
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.paint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXTRA").font(.eyebrow).tracking(1).foregroundStyle(Theme.textSecondary)
                        Text(record.name).font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                    MacroPill(macros: record.macros)
                    Button {
                        context.delete(record)
                        try? context.save()
                    } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                }
            }
            Button(action: onQuickAdd) { Label("Quick add something else", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.hardwood)
        }
        .card()
    }

    /// Logs the meal and celebrates when it tips the day onto target.
    private func toggle(_ entry: PlanEntryRecord) {
        let before = Adherence.isHit(eaten: intake.map(\.macros).sum(), target: target)
        withAnimation(.spring(response: 0.3)) { IntakeActions.toggleEaten(entry, library: library, context: context) }
        let now = context.fetchAll(IntakeRecord.self).filter { $0.day == entry.day }.map(\.macros).sum()
        if !before && Adherence.isHit(eaten: now, target: target) {
            appModel.celebrate(.dayComplete, title: "Macros on target", detail: "\(Fmt.int(now.kcal)) kcal · \(Fmt.int(now.protein)) g protein · +\(XP.perMacroDay) XP")
        }
    }
}

struct WeightTrendCard: View {
    var stats: ProgressStats
    var profile: ProfileRecord
    var units: UnitFormatter
    var onLog: () -> Void

    var body: some View {
        let recent = stats.trend.filter { $0.date >= Date.now.adding(days: -42) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow("Weight trend", color: Theme.hardwood)
                Spacer()
                Button("Log", action: onLog).buttonStyle(GhostButtonStyle(compact: true))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stats.latestTrendKg.map { units.weightValue($0) } ?? "–").font(.scoreboard(30)).foregroundStyle(Theme.textPrimary)
                Text(units.massUnit).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let perWeek = stats.projection?.kgPerWeek {
                    Text("\(units.signedWeight(perWeek, decimals: 2))/wk").font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if recent.count >= 2 {
                Chart(recent, id: \.date) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Weight", Units.display(kg: point.kg, in: profile.unitSystem)))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(ChartPalette.weight)
                    AreaMark(x: .value("Date", point.date), y: .value("Weight", Units.display(kg: point.kg, in: profile.unitSystem)))
                        .foregroundStyle(LinearGradient(colors: [ChartPalette.weight.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 70)
                .accessibilityLabel("Six-week weight trend")
            }
            Text(stats.projection?.projectedGoalDate.map { "On pace for \(units.weight(profile.goalWeightKg)) around \($0.formatted(date: .abbreviated, time: .omitted))" }
                 ?? "Log a few more weigh-ins for a projection")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

struct StreakCard: View {
    var stats: ProgressStats

    var body: some View {
        let level = stats.level
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [Theme.scoreboard, Theme.hardwood], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: stats.currentStreak)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(stats.currentStreak)-day streak").font(.system(size: 18, weight: .heavy, design: .rounded))
                    Text("Days on macros · best \(stats.longestStreak)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("LV \(level.level)").font(.scoreboard(22)).foregroundStyle(Theme.scoreboard)
            }
            XPBar(progress: Double(level.into) / Double(level.needed))
            Text("\(level.needed - level.into) XP to level \(level.level + 1)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                chip("\(stats.thisWeek.daysHitMacros)/7", "macro days")
                chip("\(stats.thisWeek.workoutsCompleted)/\(stats.thisWeek.workoutsPlanned)", "lifts")
                chip("\(stats.thisWeek.courtSessions)", "court")
                chip("\(stats.thisWeek.prs)", "PRs")
            }
        }
        .card()
    }

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Log something you ate that wasn't in the plan.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var library: MealLibrary
    @State private var foodID: UUID?
    @State private var recipeID: UUID?
    @State private var servings = 1.0
    @State private var slot: MealSlot = .snack
    @State private var tab = 0

    private var macros: Macros {
        library.macros(recipeID: recipeID, foodID: foodID, servings: servings)
    }

    private var name: String {
        if let recipeID, let recipe = library.recipes[recipeID] { return recipe.name }
        if let foodID, let food = library.foodRecords[foodID] { return food.name }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick add").font(.system(size: 22, weight: .heavy, design: .rounded))
            Picker("Source", selection: $tab) {
                Text("Foods").tag(0)
                Text("Meals").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            if tab == 0 {
                FoodSearchPicker(library: library, shakerOnly: false) { id in
                    foodID = id
                    recipeID = nil
                }
                .frame(height: 300)
            } else {
                MealPickerView(slot: slot, library: library) { recipe, food in
                    recipeID = recipe
                    foodID = food
                }
                .frame(height: 380)
            }
            if !name.isEmpty {
                HStack {
                    Text(name).font(.system(size: 14, weight: .bold))
                    Spacer()
                    MacroPill(macros: macros)
                }
                .card(padding: 10)
            }
            HStack {
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 180)
                Stepper("×\(Fmt.number(servings, maxDecimals: 2)) servings", value: $servings, in: 0.25...6, step: 0.25)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Log it") {
                    IntakeActions.logQuick(name: servings == 1 ? name : "\(name) ×\(Fmt.number(servings, maxDecimals: 2))",
                                           macros: macros, slot: slot, context: context)
                    dismiss()
                }
                .buttonStyle(HardwoodButtonStyle(compact: true))
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
