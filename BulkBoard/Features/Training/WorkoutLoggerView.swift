import BulkCore
import SwiftData
import SwiftUI

struct WorkoutLoggerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord
    var plan: WorkoutPlanRecord?
    var sessions: [WorkoutSessionRecord]
    var exercises: [UUID: ExerciseRecord]
    var allExercises: [ExerciseRecord]

    private var active: WorkoutSessionRecord? { sessions.first { !$0.isCompleted } }

    var body: some View {
        if let active {
            ActiveSessionView(session: active, profile: profile, plan: plan, sessions: sessions,
                              exercises: exercises, allExercises: allExercises)
                .id(active.id)
        } else {
            startPanel
        }
    }

    private var startPanel: some View {
        let today = plan?.day(for: .now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let today, today.dayType == .lifting {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Today · \(today.dayType.title)", color: Theme.hardwood)
                        Text(today.title).font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text("\(today.exercises.count) exercises · \(today.exercises.map(\.sets).reduce(0, +)) sets")
                            .foregroundStyle(Theme.textSecondary)
                        Button { start(today) } label: { Label("Start today's workout", systemImage: "play.fill") }
                            .buttonStyle(HardwoodButtonStyle())
                    }
                    .card()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(today?.dayType.title ?? "No plan", color: Theme.hardwood)
                        Text(today?.dayType == .conditioning ? "Game day. Log your court session, or lift anyway below." : "Rest day. Recover, or pick a session below.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .card()
                }
                Eyebrow("Or pick a day")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(plan?.days.filter { $0.dayType == .lifting } ?? []) { day in
                        Button { start(day) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.title).font(.system(size: 14, weight: .bold, design: .rounded))
                                Text("\(WeekMath.weekdayLong[day.weekday]) · \(day.exercises.count) exercises")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { start(nil) } label: {
                        Label("Empty workout", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func start(_ day: PlannedDay?) {
        withAnimation(.spring) { _ = TrainingActions.startSession(from: day, context: context) }
    }
}

struct ActiveSessionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSessionRecord
    var profile: ProfileRecord
    var plan: WorkoutPlanRecord?
    var sessions: [WorkoutSessionRecord]
    var exercises: [UUID: ExerciseRecord]
    var allExercises: [ExerciseRecord]

    @State private var sets: [SessionSet] = []
    @State private var showAddExercise = false
    @State private var confirmDiscard = false

    private var units: UnitFormatter { UnitFormatter(system: profile.unitSystem) }

    /// Exercise IDs in the order they first appear.
    private var exerciseOrder: [UUID] {
        var seen = Set<UUID>()
        return sets.map(\.exerciseID).filter { seen.insert($0).inserted }
    }

    private func planned(_ exerciseID: UUID) -> PlannedExercise? {
        plan?.days.flatMap(\.exercises).first { $0.exerciseID == exerciseID }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    ForEach(exerciseOrder, id: \.self) { exerciseID in
                        ExerciseLogCard(
                            exerciseID: exerciseID, name: exercises[exerciseID]?.name ?? "Exercise",
                            detail: exercises[exerciseID].map { "\($0.muscle.title) · \($0.equipment.title)" } ?? "",
                            planned: planned(exerciseID), sets: $sets, units: units,
                            last: TrainingActions.lastSessionSets(for: exerciseID, in: sessions, excluding: session.id),
                            suggestion: planned(exerciseID).map {
                                TrainingActions.suggestion(for: exerciseID, repLow: $0.repLow, repHigh: $0.repHigh, sessions: sessions,
                                                           units: profile.unitSystem, excluding: session.id)
                            },
                            onToggle: toggle, onChange: commit)
                    }
                    Button { showAddExercise = true } label: { Label("Add exercise", systemImage: "plus") }
                        .buttonStyle(GhostButtonStyle())
                        .popover(isPresented: $showAddExercise) {
                            ExercisePicker(exercises: allExercises) { exercise in
                                sets.append(SessionSet(exerciseID: exercise.id, reps: 8, weightKg: 0))
                                commit()
                                showAddExercise = false
                            }
                        }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, 24)
            }
            RestTimerBar(timer: appModel.restTimer)
                .padding(.bottom, 18)
                .frame(maxWidth: 620)
        }
        .animation(.spring(response: 0.35), value: appModel.restTimer.isRunning)
        .onAppear { sets = session.sets }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) {
                appModel.restTimer.skip()
                TrainingActions.discard(session, context: context)
            }
        }
    }

    private var header: some View {
        let done = sets.filter(\.isDone)
        let volume = done.filter { !$0.isWarmup }.map { Double($0.reps) * $0.weightKg }.reduce(0, +)
        return HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Workout", text: $session.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Text(session.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(session.date))
                ScoreboardStat(value: String(format: "%d:%02d", elapsed / 60, elapsed % 60), label: "Clock", color: Theme.textPrimary, size: 24)
            }
            ScoreboardStat(value: "\(done.count)/\(sets.count)", label: "Sets", color: Theme.scoreboard, size: 24)
            ScoreboardStat(value: units.volume(volume), label: "Volume", color: Theme.paint, size: 24)
            ScoreboardStat(value: "\(sets.filter { !$0.prKinds.isEmpty }.count)", label: "PRs", color: Theme.hardwood, size: 24)
            Menu {
                Button("Discard workout", role: .destructive) { confirmDiscard = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            Button { finish() } label: { Label("Finish", systemImage: "flag.checkered") }
                .buttonStyle(HardwoodButtonStyle())
                .disabled(done.isEmpty)
        }
        .card()
    }

    private func commit() {
        session.sets = sets
        try? context.save()
    }

    private func toggle(_ set: SessionSet) {
        commit()
        let kinds = TrainingActions.setDone(set.id, done: !set.isDone, in: session, context: context)
        withAnimation(.spring(response: 0.3)) { sets = session.sets }
        guard let updated = sets.first(where: { $0.id == set.id }), updated.isDone else { return }
        let rest = planned(set.exerciseID)?.restSeconds ?? exercises[set.exerciseID]?.defaultRestSeconds ?? 90
        appModel.restTimer.start(seconds: rest)
        if !kinds.isEmpty {
            let e1RM = Strength.estimated1RM(weight: updated.weightKg, reps: updated.reps)
            let detail = updated.weightKg > 0
                ? "\(units.weightValue(updated.weightKg)) × \(updated.reps) · e1RM \(units.weight(e1RM, decimals: 0))"
                : "\(updated.reps) reps"
            appModel.celebrate(.pr, title: exercises[set.exerciseID]?.name ?? "PR", detail: detail)
        }
    }

    private func finish() {
        commit()
        appModel.restTimer.skip()
        let done = sets.filter(\.isDone)
        let prs = done.filter { !$0.prKinds.isEmpty }.count
        let volume = done.filter { !$0.isWarmup }.map { Double($0.reps) * $0.weightKg }.reduce(0, +)
        TrainingActions.finish(session, context: context)
        appModel.celebrate(.workoutComplete, title: session.title,
                           detail: "\(done.count) sets · \(units.volume(volume)) · \(prs) PR\(prs == 1 ? "" : "s") · +\(XP.perWorkout + prs * XP.perPR) XP")
    }
}

struct ExerciseLogCard: View {
    var exerciseID: UUID
    var name: String
    var detail: String
    var planned: PlannedExercise?
    @Binding var sets: [SessionSet]
    var units: UnitFormatter
    var last: [SessionSet]
    var suggestion: OverloadSuggestion?
    var onToggle: (SessionSet) -> Void
    var onChange: () -> Void

    private var indices: [Int] { sets.indices.filter { sets[$0].exerciseID == exerciseID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let planned {
                    Text("\(planned.sets) × \(planned.repText) · rest \(planned.restSeconds / 60):\(String(format: "%02d", planned.restSeconds % 60))")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 10) {
                if !last.isEmpty {
                    Label("Last: " + last.map { "\(units.weightValue($0.weightKg))×\($0.reps)" }.joined(separator: ", "),
                          systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if let suggestion, suggestion.kind != .firstTime || last.isEmpty {
                    Label(suggestion.message, systemImage: suggestion.kind == .addWeight ? "arrow.up.circle.fill" : "lightbulb.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(suggestion.kind == .addWeight ? Theme.net : Theme.scoreboard)
                        .background((suggestion.kind == .addWeight ? Theme.net : Theme.scoreboard).opacity(0.12), in: Capsule())
                }
            }
            VStack(spacing: 6) {
                ForEach(Array(indices.enumerated()), id: \.element) { number, index in
                    SetRow(number: number + 1, set: $sets[index], units: units, onToggle: { onToggle(sets[index]) }, onChange: onChange)
                        .contextMenu {
                            Button(sets[index].isWarmup ? "Mark working set" : "Mark warm-up") {
                                sets[index].isWarmup.toggle()
                                onChange()
                            }
                            Button("Delete set", role: .destructive) {
                                sets.remove(at: index)
                                onChange()
                            }
                        }
                }
            }
            Button {
                let template = indices.last.map { sets[$0] }
                let newSet = SessionSet(exerciseID: exerciseID, reps: template?.reps ?? 8, weightKg: template?.weightKg ?? 0)
                if let lastIndex = indices.last { sets.insert(newSet, at: lastIndex + 1) } else { sets.append(newSet) }
                onChange()
            } label: { Label("Add set", systemImage: "plus") }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.hardwood)
        }
        .card(padding: 16)
    }
}

struct SetRow: View {
    var number: Int
    @Binding var set: SessionSet
    var units: UnitFormatter
    var onToggle: () -> Void
    var onChange: () -> Void

    private var weight: Binding<Double> {
        Binding {
            (Units.display(kg: set.weightKg, in: units.system) * 10).rounded() / 10
        } set: {
            set.weightKg = Units.kg(fromDisplay: $0, in: units.system)
            onChange()
        }
    }

    private var reps: Binding<Int> {
        Binding { set.reps } set: {
            set.reps = max(0, $0)
            onChange()
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(set.isWarmup ? "W" : "\(number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(set.isWarmup ? Theme.paint : Theme.textSecondary)
                .frame(width: 22)
            TextField("Weight", value: weight, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .disabled(set.isDone)
            Text(units.massUnit).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Text("×").foregroundStyle(Theme.textSecondary)
            TextField("Reps", value: reps, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .disabled(set.isDone)
            Text("reps").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            ForEach(set.prKinds, id: \.self) { kind in
                Label(kind.title, systemImage: "trophy.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .foregroundStyle(Theme.scoreboard)
                    .background(Theme.scoreboard.opacity(0.15), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(set.isDone ? Theme.net : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(set.isDone ? "Undo" : "Log set and start rest timer")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(set.isDone ? Theme.net.opacity(0.08) : Theme.surfaceRaised.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ExercisePicker: View {
    var exercises: [ExerciseRecord]
    var onPick: (ExerciseRecord) -> Void
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search exercises", text: $search).textFieldStyle(.roundedBorder)
            List {
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    let matches = exercises.filter { !$0.isArchived && $0.muscle == muscle && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                    if !matches.isEmpty {
                        Section(muscle.title) {
                            ForEach(matches) { exercise in
                                Button { onPick(exercise) } label: {
                                    HStack {
                                        Text(exercise.name)
                                        Spacer()
                                        Text(exercise.equipment.title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(height: 340)
        }
        .padding(12)
        .frame(width: 340)
    }
}
