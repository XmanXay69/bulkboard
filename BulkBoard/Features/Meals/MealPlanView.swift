import BulkCore
import SwiftData
import SwiftUI

struct MealPlanView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord

    @Query private var allEntries: [PlanEntryRecord]
    @Query private var foods: [FoodRecord]
    @Query private var recipes: [RecipeRecord]
    @Query private var intake: [IntakeRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]
    @State private var shuffleCount: UInt64 = 0
    @AppStorage("mealVariety") private var variety: MealVariety = .balanced

    private var weekStart: Date { appModel.planWeekStart }
    private var days: [Date] { WeekMath.days(ofWeekStarting: weekStart) }
    private var library: MealLibrary { MealLibrary(foods: foods, recipes: recipes) }
    private var snapshot: TargetsSnapshot { profile.targets(latestWeightKg: weights.first?.weightKg) }

    private var weekEntries: [PlanEntryRecord] {
        let end = weekStart.adding(days: 7)
        return allEntries.filter { $0.day >= weekStart && $0.day < end }
    }

    var body: some View {
        let library = library
        let snapshot = snapshot
        let entries = weekEntries
        let slots = profile.mealSlots
        let eatenIDs = Set(intake.compactMap(\.planEntryID))

        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(eyebrow: "Meal Plan", title: "Week of \(weekStart.monthDay)") {
                        weekNavigator
                    }
                    actionBar(isEmpty: entries.isEmpty)
                    summary(entries: entries, library: library, snapshot: snapshot)

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(days, id: \.self) { day in
                            let dayType = TrainingActions.dayType(for: day, plan: plans.first)
                            DayColumn(day: day, dayType: dayType, target: snapshot.target(for: dayType), slots: slots,
                                      entries: entries.filter { $0.day == day }, library: library, eatenIDs: eatenIDs)
                        }
                    }
                }
                .padding(24)
            }
            if appModel.showMealLibrary {
                Rectangle().fill(Theme.stroke).frame(width: 1)
                MealLibraryPanel(library: library)
                    .frame(width: 280)
                    .background(Theme.surface)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appModel.showMealLibrary)
    }

    private var weekNavigator: some View {
        HStack(spacing: 6) {
            Button { appModel.planWeekStart = weekStart.adding(days: -7) } label: { Image(systemName: "chevron.left") }
                .help("Previous week")
            Button("This week") { appModel.planWeekStart = Date.now.weekStart }
                .disabled(weekStart == Date.now.weekStart)
            Button { appModel.planWeekStart = weekStart.adding(days: 7) } label: { Image(systemName: "chevron.right") }
                .help("Next week")
        }
        .buttonStyle(GhostButtonStyle(compact: true))
    }

    private func actionBar(isEmpty: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring) { MealPlanActions.autoFill(weekOf: weekStart, context: context, seed: seed()) }
            } label: { Label(isEmpty ? "Auto-fill my week" : "Re-fill unlocked", systemImage: "wand.and.stars") }
                .buttonStyle(HardwoodButtonStyle(compact: true))
                .help("Fill every unlocked slot to hit your targets (⇧⌘F)")
            Button {
                withAnimation(.spring) { MealPlanActions.autoFill(weekOf: weekStart, context: context, seed: seed()) }
            } label: { Label("Shuffle", systemImage: "shuffle") }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(isEmpty)
                .help("New picks for unlocked meals. Locked and eaten meals stay.")
            Button(role: .destructive) {
                withAnimation { MealPlanActions.clearWeek(weekStart, context: context) }
            } label: { Label("Clear unlocked", systemImage: "trash") }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(isEmpty)
            Picker("Variety", selection: $variety) {
                ForEach(MealVariety.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 170)
            .help("Meal prep repeats a few meals for a shorter grocery list")
            Spacer()
            Button {
                appModel.groceryRequest = weekStart
                appModel.section = .grocery
            } label: { Label("Grocery list", systemImage: "cart.fill") }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(isEmpty)
                .help("Build a grocery list from this week (⇧⌘G)")
            Button { appModel.showMealLibrary.toggle() } label: {
                Label("Meals", systemImage: "sidebar.trailing")
            }
            .buttonStyle(GhostButtonStyle(compact: true))
            .help("Show meals you can drag into the week")
        }
    }

    private func summary(entries: [PlanEntryRecord], library: MealLibrary, snapshot: TargetsSnapshot) -> some View {
        let perDay = days.map { day -> (Macros, Macros) in
            let total = entries.filter { $0.day == day }.map(library.macros(for:)).sum()
            return (total, snapshot.target(for: TrainingActions.dayType(for: day, plan: plans.first)))
        }
        let planned = perDay.filter { $0.0.kcal > 0 }
        let onTarget = planned.filter { TargetStatus(value: $0.0.kcal, target: $0.1.kcal) == .onTarget }.count
        let avg = planned.isEmpty ? 0 : planned.map(\.0.kcal).reduce(0, +) / Double(planned.count)
        let avgProtein = planned.isEmpty ? 0 : planned.map(\.0.protein).reduce(0, +) / Double(planned.count)
        return HStack(spacing: 28) {
            ScoreboardStat(value: Fmt.int(avg), label: "Avg kcal / day", color: Theme.kcal, size: 24)
            ScoreboardStat(value: Fmt.int(avgProtein), label: "Avg protein", unit: "g", color: Theme.protein, size: 24)
            ScoreboardStat(value: "\(onTarget)/7", label: "Days on target", color: Theme.net, size: 24)
            ScoreboardStat(value: "\(entries.filter(\.isLocked).count)", label: "Locked meals", color: Theme.textPrimary, size: 24)
            Spacer()
        }
        .card(padding: 14)
    }

    private func seed() -> UInt64 {
        shuffleCount &+= 1
        return UInt64(Date.now.timeIntervalSince1970 * 1000) &+ shuffleCount
    }
}

// MARK: - Day column

struct DayColumn: View {
    @Environment(\.modelContext) private var context
    var day: Date
    var dayType: DayType
    var target: Macros
    var slots: [MealSlot]
    var entries: [PlanEntryRecord]
    var library: MealLibrary
    var eatenIDs: Set<UUID>

    private var isToday: Bool { Calendar.bulk.isDateInToday(day) }

    var body: some View {
        let totals = entries.map(library.macros(for:)).sum()
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(WeekMath.weekdayShort[WeekMath.weekdayIndex(day)].uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(isToday ? Theme.hardwood : Theme.textPrimary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if isToday { Text("TODAY").font(.eyebrow).foregroundStyle(Theme.hardwood) }
                }
                Label(dayType == .conditioning ? "GAME" : dayType == .lifting ? "PRACTICE" : "REST", systemImage: dayType.symbol)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.color(for: dayType))
            }
            .padding(.horizontal, 4)

            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                MealSlotCell(day: day, slotIndex: index, slot: slot,
                             entry: entries.first { $0.slotIndex == index },
                             library: library, eatenIDs: eatenIDs)
            }

            DayTotalsView(totals: totals, target: target)
        }
        .padding(8)
        .frame(minWidth: 128, maxWidth: .infinity, alignment: .top)
        .background(isToday ? Theme.hardwood.opacity(0.06) : Theme.surface.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isToday ? Theme.hardwood.opacity(0.5) : Theme.stroke))
    }
}

struct DayTotalsView: View {
    var totals: Macros
    var target: Macros

    var body: some View {
        let status = TargetStatus(value: totals.kcal, target: target.kcal)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.int(totals.kcal))
                    .font(.scoreboard(18))
                    .foregroundStyle(totals.kcal == 0 ? Theme.textSecondary : status.color == Theme.textSecondary ? Theme.textPrimary : status.color)
                    .contentTransition(.numericText())
                Image(systemName: status.symbol)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(status.color)
                Spacer()
            }
            Text("of \(Fmt.int(target.kcal)) kcal")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
            MacroBar(label: "P", value: totals.protein, target: target.protein, color: Theme.protein, compact: true)
            MacroBar(label: "C", value: totals.carbs, target: target.carbs, color: Theme.carbs, compact: true)
            MacroBar(label: "F", value: totals.fat, target: target.fat, color: Theme.fat, compact: true)
        }
        .padding(10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.4), value: totals)
    }
}

// MARK: - Slot cell

struct MealSlotCell: View {
    @Environment(\.modelContext) private var context
    var day: Date
    var slotIndex: Int
    var slot: MealSlot
    var entry: PlanEntryRecord?
    var library: MealLibrary
    var eatenIDs: Set<UUID>

    @State private var showPicker = false
    @State private var isTargeted = false

    var body: some View {
        Button { showPicker = true } label: { content }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .trailing) {
                MealPickerView(slot: slot, library: library) { recipeID, foodID in
                    MealPlanActions.assign(recipeID: recipeID, foodID: foodID, day: day, slotIndex: slotIndex, slot: slot,
                                           servings: entry?.servings ?? 1, context: context)
                    showPicker = false
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first, let (recipeID, foodID) = MealDragPayload.decode(payload) else { return false }
                withAnimation(.spring) {
                    MealPlanActions.assign(recipeID: recipeID, foodID: foodID, day: day, slotIndex: slotIndex, slot: slot, context: context)
                }
                return true
            } isTargeted: { isTargeted = $0 }
            .contextMenu { if let entry { menu(for: entry) } }
    }

    @ViewBuilder
    private var content: some View {
        if let entry {
            let macros = library.macros(for: entry)
            let eaten = eatenIDs.contains(entry.id)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: slot.symbol).font(.system(size: 9))
                    Text(slot.title.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                    Spacer(minLength: 0)
                    if eaten { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.net) }
                    if entry.isLocked { Image(systemName: "lock.fill").foregroundStyle(Theme.scoreboard) }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                Text(library.name(for: entry))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text("\(Fmt.int(macros.kcal))").foregroundStyle(Theme.kcal)
                    Text("\(Fmt.int(macros.protein))P").foregroundStyle(Theme.protein)
                    Spacer(minLength: 0)
                    if entry.servings != 1 {
                        Text("×\(Fmt.number(entry.servings, maxDecimals: 2))")
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Theme.hardwood : entry.isLocked ? Theme.scoreboard.opacity(0.5) : Theme.stroke,
                              lineWidth: isTargeted ? 2 : 1))
            .opacity(eaten ? 0.75 : 1)
            .contentShape(Rectangle())
        } else {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                Text(slot.title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isTargeted ? Theme.hardwood : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [4, 4]))
                .foregroundStyle(isTargeted ? Theme.hardwood : Theme.stroke))
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func menu(for entry: PlanEntryRecord) -> some View {
        Button(entry.isLocked ? "Unlock" : "Lock (keep on shuffle)", systemImage: entry.isLocked ? "lock.open" : "lock") {
            entry.isLocked.toggle()
            try? context.save()
        }
        Button(eatenIDs.contains(entry.id) ? "Mark not eaten" : "Mark eaten", systemImage: "checkmark.circle") {
            IntakeActions.toggleEaten(entry, library: library, context: context)
        }
        Menu("Servings") {
            ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3], id: \.self) { value in
                Button {
                    entry.servings = value
                    try? context.save()
                } label: {
                    if entry.servings == value { Label("×\(Fmt.number(value, maxDecimals: 2))", systemImage: "checkmark") }
                    else { Text("×\(Fmt.number(value, maxDecimals: 2))") }
                }
            }
        }
        Button("Swap…", systemImage: "arrow.triangle.swap") { showPicker = true }
        Divider()
        Button("Remove", systemImage: "trash", role: .destructive) {
            context.delete(entry)
            try? context.save()
        }
    }
}

enum MealDragPayload {
    static func recipe(_ id: UUID) -> String { "bulkboard-recipe:\(id.uuidString)" }
    static func food(_ id: UUID) -> String { "bulkboard-food:\(id.uuidString)" }

    static func decode(_ payload: String) -> (UUID?, UUID?)? {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "bulkboard-recipe": return (id, nil)
        case "bulkboard-food": return (nil, id)
        default: return nil
        }
    }
}
