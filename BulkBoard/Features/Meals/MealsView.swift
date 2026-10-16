import BulkCore
import SwiftData
import SwiftUI

/// Meals: what you've logged (yours), and a suggested week you can pull from.
struct MealsView: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        switch appModel.mealsTab {
        case .mine: MyMealsView(profile: profile)
        case .suggested: MealPlanView(profile: profile)
        }
    }
}

struct MealsTabPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        Picker("View", selection: $appModel.mealsTab) {
            ForEach(MealsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 210)
    }
}

// MARK: - My meals

struct MyMealsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord

    @Query(sort: \IntakeRecord.timestamp) private var intake: [IntakeRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]

    private var day: Date { appModel.mealsDay }

    var body: some View {
        let snapshot = profile.targets(latestWeightKg: weights.first?.weightKg)
        let dayType = TrainingActions.dayType(for: day, plan: plans.first)
        let target = snapshot.target(for: dayType)
        let meals = intake.filter { $0.day == day }
            .sorted { (slotOrder($0.slot), $0.timestamp) < (slotOrder($1.slot), $1.timestamp) }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                PageHeader(title: "Meals", subtitle: dayTitle) {
                    HStack(spacing: 10) {
                        MealsTabPicker()
                        dayNavigator
                        Button { appModel.logMeal(day: day) } label: { Label("Log a meal", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                            .help("Log a meal (⇧⌘E)")
                    }
                }
                HStack(alignment: .top, spacing: Theme.spacing) {
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        TodayMacrosCard(eaten: meals.map(\.macros).sum(), target: target, dayType: dayType,
                                        title: Calendar.bulk.isDateInToday(day) ? "Today's macros" : "Macros")
                        mealsCard(meals)
                    }
                    VStack(spacing: Theme.spacing) {
                        WeekIntakeStrip(intake: intake, snapshot: snapshot, plan: plans.first)
                        SavedMealsCard(day: day)
                    }
                    .frame(width: 320)
                }
            }
            .padding(24)
            .background(Theme.background)
        }
    }

    private var dayTitle: String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if Calendar.bulk.isDateInToday(day) { return "Today, \(date)" }
        if Calendar.bulk.isDateInYesterday(day) { return "Yesterday, \(date)" }
        return date
    }

    private var dayNavigator: some View {
        HStack(spacing: 6) {
            Button { appModel.mealsDay = day.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day")
            Button("Today") { appModel.mealsDay = Date.now.dayStart }
                .disabled(Calendar.bulk.isDateInToday(day))
            Button { appModel.mealsDay = day.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next day")
        }
        .buttonStyle(.bordered)
    }

    private func mealsCard(_ meals: [IntakeRecord]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel("Logged")
                Spacer()
                if !meals.isEmpty {
                    Text("\(meals.count) meal\(meals.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, 6)
            if meals.isEmpty {
                EmptyStateView(symbol: "fork.knife", title: "Nothing logged",
                               message: "Log what you eat: snap a photo, say what's in it, and BulkBoard finds the label numbers. Want ideas? Check Suggested.",
                               actionTitle: "Log a meal") { appModel.logMeal(day: day) }
            } else {
                ForEach(meals) { meal in
                    LoggedMealRow(meal: meal)
                    if meal.id != meals.last?.id { Divider() }
                }
            }
        }
        .card()
    }

    private func slotOrder(_ slot: MealSlot) -> Int {
        [MealSlot.breakfast, .snack, .lunch, .dinner, .shake].firstIndex(of: slot) ?? 9
    }
}

/// A logged meal: photo, name, what was in it, and its macros.
struct LoggedMealRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var meal: IntakeRecord
    var compact = false

    var body: some View {
        let items = meal.items
        Button { appModel.activeSheet = .logMeal(MealDraft(editing: meal)) } label: {
            HStack(alignment: .center, spacing: 12) {
                if let photo = meal.photoFilename {
                    StoredPhoto(filename: photo, size: compact ? 40 : 56)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)
                        .overlay(Image(systemName: meal.slot.symbol).foregroundStyle(Theme.textSecondary))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(meal.slot.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        if meal.planEntryID != nil {
                            Text("from Suggested").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        }
                        if meal.hasEstimates { AIEstimateBadge() }
                    }
                    Text(meal.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if !compact, !items.isEmpty {
                        Text(items.prefix(4).map { "\($0.displayName), \($0.amountText)" }.joined(separator: " · ")
                             + (items.count > 4 ? " · +\(items.count - 4) more" : ""))
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                MacroPill(macros: meal.macros)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { appModel.activeSheet = .logMeal(MealDraft(editing: meal)) }
            Button("Log again today", systemImage: "arrow.clockwise") {
                MealLogActions.duplicate(meal, to: .now, context: context)
                appModel.celebrate(.dayComplete, title: "Logged again", detail: "\(meal.name) · today")
            }
            if meal.recipeID == nil, !meal.items.isEmpty {
                Button("Save as a meal", systemImage: "star") {
                    meal.recipeID = MealLogActions.saveAsMeal(name: meal.name, items: meal.items, slot: meal.slot, context: context).id
                    try? context.save()
                    appModel.celebrate(.dayComplete, title: "Saved", detail: "\(meal.name) is in your saved meals")
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { MealLogActions.delete(meal, context: context) }
            }
        }
    }
}

/// Your saved meals, one click to log.
struct SavedMealsCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var day: Date
    @Query private var foods: [FoodRecord]
    @Query(sort: \RecipeRecord.name) private var recipes: [RecipeRecord]

    var body: some View {
        let library = MealLibrary(foods: foods, recipes: recipes)
        let saved = recipes.filter { !$0.isArchived && (!$0.isBuiltIn || $0.isFavorite) }
            .sorted { ($0.isBuiltIn ? 1 : 0, $0.createdAt) < ($1.isBuiltIn ? 1 : 0, $1.createdAt) }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Saved meals")
            if saved.isEmpty {
                Text("Tick \"Save as a meal I can reuse\" when you log something and it shows up here for one-click logging.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(saved.prefix(8)) { recipe in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recipe.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(Fmt.int(library.perServing(recipeID: recipe.id).kcal)) kcal · \(Fmt.int(library.perServing(recipeID: recipe.id).protein)) g protein")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Log") {
                        let slot = recipe.slots.count == 1 ? recipe.slots.first! : MealLogActions.defaultSlot()
                        _ = try? MealLogActions.log(recipe: recipe, servings: 1, slot: slot, day: day, library: library, context: context)
                        appModel.celebrate(.dayComplete, title: "Meal logged", detail: "\(recipe.name) · \(slot.title)")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Button("Log a saved meal…") {
                let draft = MealDraft(day: day)
                draft.mode = .saved
                appModel.activeSheet = .logMeal(draft)
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
        .card()
    }
}

/// Seven small bars: calories logged each day this week against that day's target.
struct WeekIntakeStrip: View {
    @Environment(AppModel.self) private var appModel
    var intake: [IntakeRecord]
    var snapshot: TargetsSnapshot
    var plan: WorkoutPlanRecord?

    var body: some View {
        let days = WeekMath.days(ofWeekStarting: appModel.mealsDay.weekStart)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("This week")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let eaten = intake.filter { $0.day == day }.map(\.macros).sum()
                    let target = snapshot.target(for: TrainingActions.dayType(for: day, plan: plan))
                    let ratio = target.kcal > 0 ? min(1.15, eaten.kcal / target.kcal) : 0
                    let selected = day == appModel.mealsDay
                    Button { appModel.mealsDay = day } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.surfaceRaised).frame(height: 56)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(selected ? Theme.accent : Theme.accent.opacity(0.45))
                                    .frame(height: max(eaten.kcal > 0 ? 3 : 0, 56 * ratio / 1.15))
                            }
                            Text(WeekMath.weekdayShort[WeekMath.weekdayIndex(day)].prefix(1))
                                .font(.system(size: 11, weight: selected ? .bold : .regular))
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(day.shortDay): \(Fmt.int(eaten.kcal)) of \(Fmt.int(target.kcal)) kcal")
                }
            }
            Text("Bar height is calories logged against that day's target.").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}
