import BulkCore
import Foundation
import SwiftData

enum TrainingActions {
    /// Replaces the weekly plan with a freshly generated split for the profile's training days.
    static func regeneratePlan(for profile: ProfileRecord, context: ModelContext) {
        for plan in context.fetchAll(WorkoutPlanRecord.self) { context.delete(plan) }
        let plan = WorkoutPlanRecord()
        plan.liftingDays = profile.liftingDays
        plan.courtDays = profile.courtDays
        plan.days = SplitGenerator.generate(liftingDays: profile.liftingDays, courtDays: profile.courtDays, mode: profile.goalMode)
        plan.isDemo = profile.isDemo
        context.insert(plan)
    }

    /// Day type for a date, from the current plan.
    static func dayType(for date: Date, plan: WorkoutPlanRecord?) -> DayType {
        plan?.day(for: date)?.dayType ?? .lifting
    }

    // MARK: History

    static func completedSessions(_ context: ModelContext) -> [WorkoutSessionRecord] {
        let descriptor = FetchDescriptor<WorkoutSessionRecord>(predicate: #Predicate { $0.isCompleted },
                                                               sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func activeSession(_ context: ModelContext) -> WorkoutSessionRecord? {
        let descriptor = FetchDescriptor<WorkoutSessionRecord>(predicate: #Predicate { !$0.isCompleted },
                                                               sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor))?.first
    }

    /// Working sets from the most recent completed session that included the exercise.
    static func lastSessionSets(for exerciseID: UUID, in sessions: [WorkoutSessionRecord], excluding sessionID: UUID? = nil) -> [SessionSet] {
        for session in sessions where session.isCompleted && session.id != sessionID {
            let sets = session.sets.filter { $0.exerciseID == exerciseID && $0.isDone && !$0.isWarmup }
            if !sets.isEmpty { return sets }
        }
        return []
    }

    /// Sessions in a row (most recent first) where the top weight fell short of the rep floor.
    static func missedSessions(for exerciseID: UUID, repLow: Int, in sessions: [WorkoutSessionRecord]) -> Int {
        var count = 0
        for session in sessions where session.isCompleted {
            let sets = session.sets.filter { $0.exerciseID == exerciseID && $0.isDone && !$0.isWarmup }
            guard let top = sets.map(\.weightKg).max() else { continue }
            let worst = sets.filter { abs($0.weightKg - top) < 0.01 }.map(\.reps).min() ?? 0
            if worst < repLow { count += 1 } else { break }
        }
        return count
    }

    static func suggestion(for exerciseID: UUID, repLow: Int, repHigh: Int, sessions: [WorkoutSessionRecord],
                           units: UnitSystem, excluding sessionID: UUID? = nil) -> OverloadSuggestion {
        let last = lastSessionSets(for: exerciseID, in: sessions, excluding: sessionID)
            .map { (reps: $0.reps, weight: (Units.display(kg: $0.weightKg, in: units) * 10).rounded() / 10) }
        return OverloadAdvisor.suggest(lastSession: last, repLow: repLow, repHigh: repHigh,
                                       increment: Units.plateIncrement(in: units), unit: units.massLabel,
                                       missedSessions: missedSessions(for: exerciseID, repLow: repLow, in: sessions))
    }

    // MARK: Session lifecycle

    /// Starts a session from a planned day (or empty), pre-filling sets with the overload suggestion.
    @discardableResult
    static func startSession(from planned: PlannedDay?, on date: Date = .now, context: ModelContext) -> WorkoutSessionRecord {
        let units = context.profile?.unitSystem ?? .imperial
        let sessions = completedSessions(context)
        let session = WorkoutSessionRecord(date: date, title: planned?.title ?? "Workout")
        session.dayType = planned?.dayType ?? .lifting
        session.isDemo = context.profile?.isDemo ?? false
        var sets: [SessionSet] = []
        for exercise in planned?.exercises ?? [] {
            let advice = suggestion(for: exercise.exerciseID, repLow: exercise.repLow, repHigh: exercise.repHigh,
                                    sessions: sessions, units: units)
            let weightKg = advice.weight.map { Units.kg(fromDisplay: $0, in: units) } ?? 0
            for _ in 0..<exercise.sets {
                sets.append(SessionSet(exerciseID: exercise.exerciseID, reps: advice.targetReps, weightKg: weightKg))
            }
        }
        session.sets = sets
        context.insert(session)
        try? context.save()
        return session
    }

    /// Marks a set done (or not) and returns any PRs it set against all earlier history.
    @discardableResult
    static func setDone(_ setID: UUID, done: Bool, in session: WorkoutSessionRecord, context: ModelContext) -> Set<PRKind> {
        var sets = session.sets
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return [] }
        sets[index].isDone = done
        var kinds: Set<PRKind> = []
        if done {
            let earlierThisSession = sets[..<index].filter(\.isDone).map { $0.logged(on: session.date) }
            let history = completedSessions(context).filter { $0.id != session.id }.flatMap(\.loggedSets) + earlierThisSession
            kinds = Strength.detectPRs(sets[index].logged(on: session.date), history: history)
        }
        sets[index].prKinds = PRKind.allCases.filter(kinds.contains)
        session.sets = sets
        try? context.save()
        return kinds
    }

    static func finish(_ session: WorkoutSessionRecord, context: ModelContext) {
        session.sets = session.sets.filter { $0.isDone }
        session.isCompleted = true
        session.durationSeconds = max(60, Int(Date.now.timeIntervalSince(session.date)))
        session.prCount = session.sets.filter { !$0.prKinds.isEmpty }.count
        try? context.save()
    }

    static func discard(_ session: WorkoutSessionRecord, context: ModelContext) {
        context.delete(session)
        try? context.save()
    }

    static func logCourtSession(date: Date, kind: CourtSessionKind, minutes: Int, rpe: Int, notes: String, context: ModelContext) {
        let record = CourtSessionRecord(date: date)
        record.kind = kind
        record.minutes = minutes
        record.rpe = rpe
        record.notes = notes
        record.isDemo = context.profile?.isDemo ?? false
        context.insert(record)
        try? context.save()
    }

    /// Best e1RM and heaviest weight for each exercise, from completed sessions.
    static func personalBests(_ sessions: [WorkoutSessionRecord]) -> [UUID: (e1RM: Double, heaviest: Double)] {
        var bests: [UUID: (e1RM: Double, heaviest: Double)] = [:]
        for set in sessions.filter(\.isCompleted).flatMap(\.loggedSets) where !set.isWarmup {
            let e1RM = set.reps <= Strength.maxRepsForE1RM ? Strength.estimated1RM(weight: set.weightKg, reps: set.reps) : 0
            let current = bests[set.exerciseID] ?? (0, 0)
            bests[set.exerciseID] = (max(current.e1RM, e1RM), max(current.heaviest, set.weightKg))
        }
        return bests
    }
}
