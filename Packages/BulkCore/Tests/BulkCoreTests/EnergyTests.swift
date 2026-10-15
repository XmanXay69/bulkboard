import Foundation
import Testing
@testable import BulkCore

@Suite("Energy: BMR and TDEE")
struct EnergyTests {
    @Test func mifflinStJeorMale() {
        // 10×80 + 6.25×180 − 5×25 + 5
        #expect(Energy.bmr(weightKg: 80, heightCm: 180, age: 25, sex: .male) == 1805)
    }

    @Test func mifflinStJeorFemale() {
        // 10×60 + 6.25×165 − 5×30 − 161
        #expect(Energy.bmr(weightKg: 60, heightCm: 165, age: 30, sex: .female) == 1320.25)
    }

    @Test(arguments: ActivityLevel.allCases)
    func tdeeAppliesMultiplier(level: ActivityLevel) {
        #expect(Energy.tdee(bmr: 2000, activity: level) == 2000 * level.multiplier)
    }

    @Test func dailyAdjustmentUses7700PerKg() {
        #expect(abs(Energy.dailyAdjustment(weeklyChangeKg: 0.5) - 550) < 1e-9)
        #expect(abs(Energy.dailyAdjustment(weeklyChangeKg: -1) + 1100) < 1e-9)
    }

    @Test func suggestedActivityFromSessions() {
        #expect(ActivityLevel.suggested(forSessionsPerWeek: 0) == .sedentary)
        #expect(ActivityLevel.suggested(forSessionsPerWeek: 4) == .moderate)
        #expect(ActivityLevel.suggested(forSessionsPerWeek: 6) == .active)
        #expect(ActivityLevel.suggested(forSessionsPerWeek: 9) == .veryActive)
    }
}

@Suite("Goal rate and warnings")
struct GoalPlannerTests {
    @Test func realisticBulkUsesRequiredRate() {
        // +10 lb in 16 weeks = 0.625 lb/week, inside 0.5–1.0.
        let plan = GoalPlanner.plan(profile: Fixture.profile(), today: Fixture.today)
        #expect(abs(plan.weeklyChangeLb - 0.625) < 1e-6)
        #expect(abs(plan.dailyAdjustmentKcal - Units.kg(fromLb: 0.625) * 1100) < 1e-6)
        #expect(plan.warnings.isEmpty)
        #expect(plan.projectedGoalDate == Fixture.day(112))
    }

    @Test func aggressiveTargetIsCappedAndWarned() {
        let profile = Fixture.profile(goalKg: 80 + Units.kg(fromLb: 20), weeks: 8)
        let plan = GoalPlanner.plan(profile: profile, today: Fixture.today)
        #expect(abs(plan.weeklyChangeLb - 1.0) < 1e-9)
        #expect(plan.warnings.contains { if case let .tooAggressive(required, capped) = $0 { abs(required - 2.5) < 1e-6 && capped == 1.0 } else { false } })
        #expect(plan.warnings.contains { $0.isSerious })
    }

    @Test func slowTargetUsesMinimumAndArrivesEarly() {
        let profile = Fixture.profile(goalKg: 80 + Units.kg(fromLb: 2), weeks: 20)
        let plan = GoalPlanner.plan(profile: profile, today: Fixture.today)
        #expect(abs(plan.weeklyChangeLb - 0.5) < 1e-9)
        #expect(plan.warnings.contains { if case .slowerThanMinimum = $0 { true } else { false } })
        #expect(plan.projectedGoalDate! < profile.targetDate)
    }

    @Test func pastTargetDateFallsBackToDefaultRate() {
        let profile = Fixture.profile(weeks: -2, mode: .bulk)
        let plan = GoalPlanner.plan(profile: profile, today: Fixture.today)
        #expect(plan.warnings.contains(.targetDateInPast))
        #expect(abs(plan.weeklyChangeLb - GoalMode.bulk.ratePolicy.defaultLbPerWeek) < 1e-9)
    }

    @Test func goalInWrongDirectionWarns() {
        let profile = Fixture.profile(goalKg: 75, mode: .bulk)
        let plan = GoalPlanner.plan(profile: profile, today: Fixture.today)
        #expect(plan.warnings.contains(.goalOppositeDirection(mode: .bulk)))
        #expect(plan.weeklyChangeKg > 0) // mode still drives direction
        #expect(plan.projectedGoalDate == nil)
    }

    @Test func goalReached() {
        let plan = GoalPlanner.plan(profile: Fixture.profile(goalKg: 80.1), today: Fixture.today)
        #expect(plan.warnings.contains(.goalReached))
    }

    @Test func cutIsCappedAtOnePercentBodyweight() {
        let weight = Units.kg(fromLb: 140)
        let profile = Fixture.profile(weightKg: weight, goalKg: Units.kg(fromLb: 120), weeks: 8, mode: .cut)
        let plan = GoalPlanner.plan(profile: profile, today: Fixture.today)
        #expect(abs(plan.weeklyChangeLb + 1.4) < 1e-6)
        #expect(plan.dailyAdjustmentKcal < 0)
    }

    @Test func recompAndMaintainUseFixedAdjustments() {
        #expect(GoalPlanner.plan(profile: Fixture.profile(mode: .recomp), today: Fixture.today).dailyAdjustmentKcal == -150)
        #expect(GoalPlanner.plan(profile: Fixture.profile(mode: .maintain), today: Fixture.today).dailyAdjustmentKcal == 0)
    }

    @Test func overrideRateIsRespected() {
        let plan = GoalPlanner.plan(profile: Fixture.profile(), today: Fixture.today, weeklyRateOverrideKg: Units.kg(fromLb: 0.8))
        #expect(abs(plan.weeklyChangeLb - 0.8) < 1e-9)
        #expect(plan.warnings.isEmpty)
    }
}

@Suite("Macro targets")
struct TargetsTests {
    let profile = Fixture.profile(weightKg: 84, heightCm: 188, lifting: 4, court: 2)

    @Test func macrosFollowTheRules() {
        let result = TargetsCalculator.compute(profile: profile, today: Fixture.today)
        let weightLb = Units.lb(fromKg: 84)
        #expect(result.daily.protein == (0.9 * weightLb).rounded())
        #expect(result.daily.fat == (result.daily.kcal * 0.25 / 9).rounded())
        // Macros add back up to the calorie target (within rounding).
        #expect(abs(result.daily.kcalFromMacros - result.daily.kcal) <= 10)
        #expect(result.daily.kcal == ((result.tdee + result.rate.dailyAdjustmentKcal) / 10).rounded() * 10)
    }

    @Test func dayTypesAverageBackToDailyTarget() {
        let result = TargetsCalculator.compute(profile: profile, today: Fixture.today)
        let weighted = DayType.allCases.reduce(0.0) { $0 + result.target(for: $1).kcal * Double(result.schedule[$1, default: 0]) } / 7
        #expect(abs(weighted - result.daily.kcal) <= 10)
        #expect(result.target(for: .conditioning).kcal > result.target(for: .lifting).kcal)
        #expect(result.target(for: .lifting).kcal > result.target(for: .rest).kcal)
        for dayType in DayType.allCases {
            #expect(result.target(for: dayType).protein == result.daily.protein)
            #expect(result.target(for: dayType).fat == result.daily.fat)
        }
    }

    @Test func showsTheMath() {
        let result = TargetsCalculator.compute(profile: profile, today: Fixture.today)
        let labels = result.steps.map(\.label)
        for expected in ["BMR (Mifflin-St Jeor)", "Maintenance (TDEE)", "Rate of gain", "Daily surplus", "Daily calories", "Protein", "Fat", "Carbs"] {
            #expect(labels.contains(expected))
        }
        #expect(result.steps.first?.formula == "10 × 84 kg + 6.25 × 188 cm − 5 × 25 + 5")
    }

    @Test func customSettingsApply() {
        let result = TargetsCalculator.compute(profile: profile, today: Fixture.today,
                                               settings: MacroSettings(proteinPerLb: 1.0, fatPercent: 0.30))
        #expect(result.daily.protein == Units.lb(fromKg: 84).rounded())
        #expect(result.daily.fat == (result.daily.kcal * 0.30 / 9).rounded())
    }

    @Test func caloriesNeverDropBelowFloor() {
        let small = Fixture.profile(weightKg: 50, goalKg: 40, weeks: 4, mode: .cut, sex: .female, age: 40,
                                    heightCm: 155, activity: .sedentary, lifting: 0, court: 0)
        let result = TargetsCalculator.compute(profile: small, today: Fixture.today)
        #expect(result.daily.kcal >= 1200)
        #expect(result.warnings.contains { if case .caloriesAtFloor = $0 { true } else { false } })
    }

    @Test func overridesReplaceComputedTargets() {
        let result = TargetsCalculator.compute(profile: profile, today: Fixture.today)
        let custom = Macros(kcal: 4000, protein: 200, carbs: 500, fat: 110)
        let merged = TargetsCalculator.applying(overrides: [.conditioning: custom], to: result.byDayType)
        #expect(merged[.conditioning] == custom)
        #expect(merged[.lifting] == result.byDayType[.lifting])
    }

    @Test func scheduleClampsToSevenDays() {
        let packed = Fixture.profile(lifting: 6, court: 4)
        let schedule = TargetsCalculator.defaultSchedule(for: packed)
        #expect(schedule.values.reduce(0, +) == 7)
        #expect(schedule[.conditioning] == 1)
        #expect(schedule[.rest] == 0)
    }
}
