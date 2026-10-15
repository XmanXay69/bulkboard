import BulkCore
import Foundation
import SwiftData

/// Clearly-labeled sample data for screenshots and kicking the tires. Everything it creates has
/// `isDemo = true` (shown with a DEMO badge) and `wipe` removes it in one pass.
/// The person is fictional: a 24-year-old, 6′2″ hooper ten weeks into a lean bulk.
enum DemoData {
    static let weeksOfHistory = 10

    static func load(into context: ModelContext, today: Date = .now) {
        var rng = SplitMix64(seed: 2026)
        let start = today.dayStart.adding(days: -weeksOfHistory * 7)

        let draft = OnboardingDraft()
        draft.age = 24
        draft.sex = .male
        draft.heightFeet = 6
        draft.heightInches = 2
        draft.weight = 180
        draft.goalWeight = 197
        draft.targetDate = today.dayStart.adding(days: 16 * 7)
        draft.mode = .bulkPerformance
        draft.liftingDays = 4
        draft.courtDays = 2
        draft.dislikesText = "mushrooms"
        let profile = ProfileActions.completeOnboarding(draft, context: context)
        profile.isDemo = true
        profile.startDate = start
        for weight in context.fetchAll(WeightRecord.self) { context.delete(weight) }

        addWeighIns(from: start, to: today, rng: &rng, context: context)
        addTraining(from: start, to: today, rng: &rng, context: context)
        addIntake(from: start, to: today, profile: profile, rng: &rng, context: context)
        addCheckIns(today: today, context: context)

        GroceryActions.generate(weekOf: today, context: context)
        for item in context.fetchAll(GroceryItemRecord.self).sorted(by: { $0.sortIndex < $1.sortIndex }).prefix(7) {
            item.isChecked = true
        }
        GroceryActions.addManual(name: "Sports tape", amount: "2 rolls", section: .other, context: context)

        markAllDemo(context)
        try? context.save()
    }

    /// Deletes every demo record. If the profile itself was demo, the app returns to onboarding.
    static func wipe(_ context: ModelContext) {
        func purge<T: PersistentModel>(_ type: T.Type, _ isDemo: (T) -> Bool) {
            for record in context.fetchAll(type) where isDemo(record) { context.delete(record) }
        }
        purge(ProfileRecord.self) { $0.isDemo }
        purge(PlanEntryRecord.self) { $0.isDemo }
        purge(IntakeRecord.self) { $0.isDemo }
        purge(GroceryItemRecord.self) { $0.isDemo }
        purge(WorkoutPlanRecord.self) { $0.isDemo }
        purge(WorkoutSessionRecord.self) { $0.isDemo }
        purge(CourtSessionRecord.self) { $0.isDemo }
        purge(WeightRecord.self) { $0.isDemo }
        purge(FoodRecord.self) { $0.isDemo }
        purge(RecipeRecord.self) { $0.isDemo }
        for record in context.fetchAll(BodyCheckInRecord.self) where record.isDemo {
            if let photo = record.photoFilename { PhotoStore.delete(photo) }
            context.delete(record)
        }
        try? context.save()
    }

    static func hasDemoData(_ context: ModelContext) -> Bool {
        context.fetchAll(WeightRecord.self).contains(where: \.isDemo) || context.profile?.isDemo == true
    }

    // MARK: - Generators

    private static func noise(_ rng: inout SplitMix64, _ amplitude: Double) -> Double {
        (Double(rng.next() % 10_000) / 10_000 - 0.5) * 2 * amplitude
    }

    private static func chance(_ rng: inout SplitMix64, _ p: Double) -> Bool {
        Double(rng.next() % 10_000) / 10_000 < p
    }

    /// ~0.65 lb/week upward trend with daily water-weight noise; skips some mornings.
    private static func addWeighIns(from start: Date, to today: Date, rng: inout SplitMix64, context: ModelContext) {
        let days = WeekMath.daysBetween(start, today)
        for day in 0...days {
            guard day == days || !chance(&rng, 0.22) else { continue }
            let lb = 180 + 0.093 * Double(day) + noise(&rng, 0.9)
            let date = start.adding(days: day).addingTimeInterval(7.5 * 3600)
            context.insert(WeightRecord(date: date, weightKg: Units.kg(fromLb: lb)))
        }
    }

    /// Starting working weights (lb) for a fictional intermediate lifter.
    private static let baseLb: [String: Double] = [
        "bench_press": 175, "barbell_row": 155, "overhead_press": 105, "db_curl": 30, "triceps_pushdown": 50,
        "back_squat": 225, "romanian_deadlift": 185, "bulgarian_split_squat": 40, "standing_calf_raise": 140,
        "med_ball_chest_pass": 12, "trap_bar_deadlift": 275, "leg_press": 360, "walking_lunge": 40, "leg_curl": 90,
        "leg_extension": 100, "seated_calf_raise": 90, "incline_db_press": 60, "lat_pulldown": 140,
        "seated_cable_row": 140, "db_shoulder_press": 50, "lateral_raise": 20, "cable_fly": 30, "hammer_curl": 35,
        "overhead_triceps_extension": 45, "chest_supported_row": 50, "pallof_press": 30, "med_ball_slam": 20,
        "hip_thrust": 225, "face_pull": 40, "cable_crunch": 70,
    ]

    /// Follows the plan week by week with double progression, so PRs show up naturally.
    private static func addTraining(from start: Date, to today: Date, rng: inout SplitMix64, context: ModelContext) {
        guard let plan = context.workoutPlan else { return }
        let keyByID = Dictionary(uniqueKeysWithValues: ((try? SeedLibrary.exercises()) ?? []).map { ($0.id, $0.key) })
        var state: [UUID: (weightLb: Double, reps: Int)] = [:]
        var history: [LoggedSet] = []
        let kinds: [CourtSessionKind] = [.conditioning, .pickup, .leagueGame, .skills]
        var courtCount = 0

        var weekStart = start.weekStart
        while weekStart <= today {
            for day in plan.days {
                let date = weekStart.adding(days: day.weekday)
                guard date >= start, date < today.dayStart else { continue }
                switch day.dayType {
                case .lifting:
                    guard !chance(&rng, 0.06) else { continue } // the occasional missed session
                    let session = WorkoutSessionRecord(date: date.addingTimeInterval(18 * 3600), title: day.title)
                    var sets: [SessionSet] = []
                    for planned in day.exercises {
                        let key = keyByID[planned.exerciseID] ?? ""
                        var current = state[planned.exerciseID] ?? (baseLb[key] ?? 0, planned.repLow)
                        for setIndex in 0..<planned.sets {
                            let reps = max(planned.repLow - 1, current.reps - (setIndex == planned.sets - 1 && chance(&rng, 0.25) ? 1 : 0))
                            var set = SessionSet(exerciseID: planned.exerciseID, reps: reps,
                                                 weightKg: Units.kg(fromLb: current.weightLb), isDone: true)
                            let logged = set.logged(on: session.date)
                            set.prKinds = PRKind.allCases.filter(Strength.detectPRs(logged, history: history).contains)
                            history.append(logged)
                            sets.append(set)
                        }
                        if planned.repLow == planned.repHigh {
                            // Power work holds load steady.
                        } else if current.reps < planned.repHigh {
                            if chance(&rng, 0.55) { current.reps += 1 }
                        } else if current.weightLb > 0 {
                            current = (current.weightLb + (current.weightLb >= 100 ? 5 : 2.5), planned.repLow)
                        }
                        state[planned.exerciseID] = current
                    }
                    session.sets = sets
                    session.isCompleted = true
                    session.durationSeconds = 60 * (55 + Int(rng.next() % 25))
                    session.prCount = sets.filter { !$0.prKinds.isEmpty }.count
                    session.dayType = .lifting
                    context.insert(session)
                case .conditioning:
                    let record = CourtSessionRecord(date: date.addingTimeInterval(19 * 3600))
                    record.kind = kinds[courtCount % kinds.count]
                    record.minutes = 55 + Int(rng.next() % 6) * 5
                    record.rpe = 6 + Int(rng.next() % 4)
                    courtCount += 1
                    context.insert(record)
                case .rest:
                    break
                }
            }
            weekStart = weekStart.adding(days: 7)
        }
    }

    /// Past four weeks of intake near target (most days hit), plus this week's plan checked off up to now.
    private static func addIntake(from start: Date, to today: Date, profile: ProfileRecord, rng: inout SplitMix64, context: ModelContext) {
        let plan = context.workoutPlan
        let snapshot = profile.targets(latestWeightKg: context.latestWeightKg)
        let slots: [(MealSlot, Double)] = [(.breakfast, 0.22), (.lunch, 0.25), (.snack, 0.13), (.dinner, 0.25), (.shake, 0.15)]
        let thisWeek = today.weekStart
        let firstDay = max(start, today.dayStart.adding(days: -28))

        var day = firstDay
        while day < thisWeek {
            let target = snapshot.target(for: TrainingActions.dayType(for: day, plan: plan))
            let miss = chance(&rng, 0.2)
            let scale = miss ? 0.8 + noise(&rng, 0.05) : 1 + noise(&rng, 0.06)
            for (slot, share) in slots {
                let record = IntakeRecord(day: day, name: slot.title)
                record.slotRaw = slot.rawValue
                record.macros = target * (share * scale)
                record.timestamp = day.addingTimeInterval(8 * 3600)
                context.insert(record)
            }
            day = day.adding(days: 1)
        }

        let library = MealLibrary(context)
        let hour = Calendar.bulk.component(.hour, from: today)
        for entry in MealPlanActions.entries(weekOf: today, context: context) {
            let isPast = entry.day < today.dayStart
            let isEarlierToday = entry.day == today.dayStart && entry.slotIndex < (hour >= 13 ? 2 : 1)
            if isPast || isEarlierToday {
                IntakeActions.toggleEaten(entry, library: library, context: context)
            }
        }
    }

    /// Two tape check-ins eight weeks apart (inches converted to cm). Calves lag; the dunk is about 3 in away.
    private static func addCheckIns(today: Date, context: ModelContext) {
        func inches(_ value: Double) -> Double { value * 2.54 }
        let earlier = BodyMeasurements(
            heightCm: inches(74), weightKg: Units.kg(fromLb: 181.5), wingspanCm: inches(77), wristCm: 17.8,
            neckCm: inches(15.5), shouldersCm: inches(47), chestCm: inches(41), waistCm: inches(31.5), hipsCm: inches(38.5),
            armCm: inches(14.5), forearmCm: inches(12), thighCm: inches(23), calfCm: inches(13.5),
            standingVerticalCm: inches(22), approachTouchCm: inches(121), canPalmBall: false)
        let recent = BodyMeasurements(
            heightCm: inches(74), weightKg: Units.kg(fromLb: 186), wingspanCm: inches(77), wristCm: 17.8,
            neckCm: inches(15.75), shouldersCm: inches(48.25), chestCm: inches(42.25), waistCm: inches(32.25), hipsCm: inches(39),
            armCm: inches(15.25), forearmCm: inches(12.25), thighCm: inches(23.75), calfCm: inches(13.75),
            standingVerticalCm: inches(23.5), approachTouchCm: inches(123), canPalmBall: false)
        for (offset, measurements) in [(-56, earlier), (-3, recent)] {
            let record = BodyCheckInRecord(date: today.dayStart.adding(days: offset).addingTimeInterval(8 * 3600))
            record.measurements = measurements
            context.insert(record)
        }
    }

    private static func markAllDemo(_ context: ModelContext) {
        for record in context.fetchAll(BodyCheckInRecord.self) { record.isDemo = true }
        context.profile?.isDemo = true
        for record in context.fetchAll(PlanEntryRecord.self) { record.isDemo = true }
        for record in context.fetchAll(IntakeRecord.self) { record.isDemo = true }
        for record in context.fetchAll(GroceryItemRecord.self) { record.isDemo = true }
        for record in context.fetchAll(WorkoutPlanRecord.self) { record.isDemo = true }
        for record in context.fetchAll(WorkoutSessionRecord.self) { record.isDemo = true }
        for record in context.fetchAll(CourtSessionRecord.self) { record.isDemo = true }
        for record in context.fetchAll(WeightRecord.self) { record.isDemo = true }
    }
}
