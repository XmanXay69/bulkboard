import Foundation
import Testing
@testable import BulkCore

@Suite("Physique analysis")
struct PhysiqueTests {
    // 6'2", 185 lb, 18 cm wrist → chest target 117 cm.
    let measurements = BodyMeasurements(heightCm: 188, weightKg: 84, wristCm: 18, neckCm: 39, shouldersCm: 122,
                                        chestCm: 108, waistCm: 82, armCm: 39, forearmCm: 31, thighCm: 60, calfCm: 33)

    @Test func targetsComeFromTheWrist() {
        let report = PhysiqueAnalyzer.analyze(measurements, sex: .male)
        let chest = report.parts.first { $0.part == .chest }!
        #expect(abs(chest.targetCm - 117) < 1e-9)
        let calves = report.parts.first { $0.part == .calves }!
        #expect(abs(calves.targetCm - 117 * 0.34) < 1e-9)
        #expect(!report.frameEstimated)
    }

    @Test func findsTheLaggingPartAndStrengths() {
        let report = PhysiqueAnalyzer.analyze(measurements, sex: .male)
        #expect(report.parts.first?.part == .calves) // sorted weakest first
        #expect(report.lagging.first == .calves)
        #expect(report.focusMuscles.contains(.calves))
        #expect(report.strengths.contains(.thighs))
        #expect(!report.lagging.contains(.thighs))
        #expect(report.notes.first?.hasPrefix("Calves are your biggest gap") == true)
    }

    @Test func vTaperUsesShouldersOverWaist() {
        let report = PhysiqueAnalyzer.analyze(measurements, sex: .male)
        #expect(abs(report.vTaper! - 122.0 / 82.0) < 1e-9)
        #expect(report.notes.contains { $0.hasPrefix("V-taper is 1.49") })
    }

    @Test func navyBodyFatAndFFMI() {
        let bodyFat = PhysiqueAnalyzer.navyBodyFat(sex: .male, heightCm: 188, neckCm: 39, waistCm: 82, hipsCm: nil)!
        #expect(abs(bodyFat - 11.64) < 0.1)
        let report = PhysiqueAnalyzer.analyze(measurements, sex: .male)
        #expect(report.bodyFatIsEstimate)
        #expect(abs(report.ffmi! - 20.51) < 0.05)
        #expect(report.ffmiBand == "Above average")
        #expect(abs(report.leanToNextBandKg! - 5.26) < 0.1)
    }

    @Test func enteredBodyFatWins() {
        var m = measurements
        m.bodyFatPercent = 15
        let report = PhysiqueAnalyzer.analyze(m, sex: .male)
        #expect(report.bodyFatPercent == 15)
        #expect(!report.bodyFatIsEstimate)
    }

    @Test func estimatesFrameWithoutWrist() {
        var m = measurements
        m.wristCm = nil
        let report = PhysiqueAnalyzer.analyze(m, sex: .male)
        #expect(report.frameEstimated)
        #expect(report.notes.contains { $0.contains("wrist") })
    }

    @Test func handlesSparseInput() {
        let report = PhysiqueAnalyzer.analyze(BodyMeasurements(heightCm: 180, weightKg: 75, armCm: 35), sex: .male)
        #expect(report.parts.count == 1)
        #expect(report.lagging.isEmpty) // nothing to compare against
        #expect(report.ffmi == nil)
    }

    @Test func femaleNavyNeedsHips() {
        #expect(PhysiqueAnalyzer.navyBodyFat(sex: .female, heightCm: 165, neckCm: 33, waistCm: 72, hipsCm: nil) == nil)
        #expect(PhysiqueAnalyzer.navyBodyFat(sex: .female, heightCm: 165, neckCm: 33, waistCm: 72, hipsCm: 98) != nil)
    }

    @Test func looseWordingMapsToParts() {
        #expect(BodyPart.matching("Lats look narrow") == .shoulders)
        #expect(BodyPart.matching("rear delts") == .shoulders)
        #expect(BodyPart.matching("Calves") == .calves)
        #expect(BodyPart.matching("forearms") == .forearms)
        #expect(BodyPart.matching("upper chest / pecs") == .chest)
        #expect(BodyPart.matching("hamstrings") == .thighs)
        #expect(BodyPart.matching("vibes") == nil)
    }
}

@Suite("Dunk math")
struct DunkTests {
    let guardBuild = DunkInputs(heightCm: 188, wingspanCm: 195.6, weightKg: 84, goalWeightKg: 89.4, standingVerticalCm: 61)

    @Test func reachEstimateMatchesCombineData() {
        // A 6'1.75" guard with a 6'7" wingspan measured an 8'2.5" standing reach.
        let reach = DunkCalculator.estimatedReach(heightCm: 73.75 * 2.54, wingspanCm: 79 * 2.54)
        #expect(abs(reach / 2.54 - 98.5) < 1)
    }

    @Test func requirementAndGap() {
        let report = DunkCalculator.report(guardBuild)
        #expect(report.reachIsEstimate)
        #expect(abs(report.requiredTouchCm - 320.04) < 1e-6)
        #expect(abs(report.requiredJumpCm - (320.04 - report.reachCm)) < 1e-9)
        #expect(report.currentJumpIsEstimate)
        #expect(abs(report.currentJumpCm! - 61 * 1.15) < 1e-9)
        #expect(report.gapCm! > 0)
        #expect(report.verdict == .close)
    }

    @Test func measuredTouchCanDunk() {
        var input = guardBuild
        input.approachTouchCm = 325
        let report = DunkCalculator.report(input)
        #expect(!report.currentJumpIsEstimate)
        #expect(report.gapCm! <= 0)
        #expect(report.verdict == .canDunk)
        #expect(report.estimatedWeeks == nil)
    }

    @Test func palmingLowersTheBar() {
        var input = guardBuild
        input.canPalmBall = true
        #expect(DunkCalculator.report(input).requiredJumpCm < DunkCalculator.report(guardBuild).requiredJumpCm)
    }

    @Test func measuredReachOverridesEstimate() {
        var input = guardBuild
        input.standingReachCm = 252
        let report = DunkCalculator.report(input)
        #expect(!report.reachIsEstimate)
        #expect(report.reachCm == 252)
    }

    @Test func sayersPower() {
        #expect(abs(DunkCalculator.sayersPower(jumpCm: 50, massKg: 80) - 4604) < 1e-9)
        #expect(abs(DunkCalculator.jump(fromPower: 4604, massKg: 80) - 50) < 1e-9)
    }

    @Test func bulkingCostsInchesAtTheSamePower() {
        let report = DunkCalculator.report(guardBuild)
        #expect(report.projectedJumpAtGoalCm! < report.currentJumpCm!)
        // 5.4 kg heavier at the same power ≈ 4.6 cm less running jump.
        #expect(abs(report.currentJumpCm! - report.projectedJumpAtGoalCm! - 5.4 * report.jumpLossPerKgCm) < 1e-6)
        #expect(report.powerIncreaseNeededAtGoal! > 0.05)
    }

    @Test func timelineGrowsWithTheGap() {
        #expect(DunkCalculator.weeksToGain(1.27 * 8) == 8)
        var small = guardBuild
        small.standingVerticalCm = 55
        var big = guardBuild
        big.standingVerticalCm = 40
        let smallWeeks = DunkCalculator.report(small).estimatedWeeks!
        let bigWeeks = DunkCalculator.report(big).estimatedWeeks!
        #expect(bigWeeks.lowerBound > smallWeeks.lowerBound)
        #expect(DunkCalculator.report(big).verdict == .longTerm)
    }

    @Test func noJumpDataStillGivesTheRequirement() {
        let report = DunkCalculator.report(DunkInputs(heightCm: 180, weightKg: 80))
        #expect(report.currentJumpCm == nil)
        #expect(report.verdict == nil)
        #expect(report.requiredJumpCm > 70)
    }
}

@Suite("Focus and dunk training")
struct FocusSplitTests {
    let calfID = StableID.uuid("exercise", "standing_calf_raise")

    func sets(_ days: [PlannedDay], for muscle: MuscleGroup) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: SplitGenerator.muscleForKey.map { (StableID.uuid("exercise", $0.key), $0.value) })
        return days.flatMap(\.exercises).filter { byID[$0.exerciseID] == muscle }.map(\.sets).reduce(0, +)
    }

    @Test func focusAddsVolumeWhereTheMuscleIsTrained() {
        let base = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulkPerformance)
        let focused = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulkPerformance, focus: [.calves, .biceps])
        #expect(sets(focused, for: .calves) >= sets(base, for: .calves) + 4)
        #expect(sets(focused, for: .biceps) >= sets(base, for: .biceps) + 4)
        #expect(sets(focused, for: .chest) == sets(base, for: .chest))
        #expect(focused.flatMap(\.exercises).contains { $0.note == "Focus" })
    }

    @Test func upperFocusLeavesLegDaysAlone() {
        let focused = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulk, focus: [.shoulders])
        let base = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulk)
        for (a, b) in zip(focused, base) where a.title.hasPrefix("Lower") {
            #expect(a.exercises.map(\.sets) == b.exercises.map(\.sets))
        }
    }

    @Test func addedVolumeIsCapped() {
        let base = SplitGenerator.generate(liftingDays: 3, courtDays: 2, mode: .bulk)
        let everything = SplitGenerator.generate(liftingDays: 3, courtDays: 2, mode: .bulk, focus: Set(MuscleGroup.allCases))
        for (a, b) in zip(everything, base) where a.dayType == .lifting {
            let added = a.exercises.map(\.sets).reduce(0, +) - b.exercises.map(\.sets).reduce(0, +)
            #expect(added <= SplitGenerator.maxAddedSetsPerDay + 2)
        }
    }

    @Test func dunkModeAddsJumpWork() {
        let depth = StableID.uuid("exercise", "depth_jump")
        let trapJump = StableID.uuid("exercise", "trap_bar_jump")
        let box = StableID.uuid("exercise", "box_jump")
        let days = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulk, dunk: true)
        let lower = days.filter { $0.title.hasPrefix("Lower") }
        #expect(!lower.isEmpty)
        for day in lower {
            #expect(day.exercises.first?.exerciseID == depth)
            #expect(day.exercises.contains { $0.exerciseID == trapJump })
            #expect(!day.exercises.contains { $0.exerciseID == box })
            let calfIDs = Set(SplitGenerator.muscleForKey.filter { $0.value == .calves && $0.key != "pogo_jump" }.keys.map { StableID.uuid("exercise", $0) })
            #expect(day.exercises.contains { calfIDs.contains($0.exerciseID) })
        }
        for court in days.filter({ $0.dayType == .conditioning }) {
            #expect(court.block?.items.contains { $0.contains("Approach jumps") } == true)
        }
    }
}
