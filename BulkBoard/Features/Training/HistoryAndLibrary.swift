import BulkCore
import SwiftData
import SwiftUI

struct TrainingHistoryView: View {
    @Environment(\.modelContext) private var context
    var sessions: [WorkoutSessionRecord]
    var courtSessions: [CourtSessionRecord]
    var exercises: [UUID: ExerciseRecord]
    var units: UnitSystem

    private enum Item: Identifiable {
        case lift(WorkoutSessionRecord)
        case court(CourtSessionRecord)

        var id: UUID {
            switch self {
            case let .lift(session): session.id
            case let .court(session): session.id
            }
        }

        var date: Date {
            switch self {
            case let .lift(session): session.date
            case let .court(session): session.date
            }
        }
    }

    private var weeks: [(start: Date, items: [Item])] {
        let items = sessions.map(Item.lift) + courtSessions.map(Item.court)
        return Dictionary(grouping: items) { $0.date.weekStart }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        let formatter = UnitFormatter(system: units)
        ScrollView {
            if weeks.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "No sessions yet",
                               message: "Finish a workout or log a court session and it shows up here.")
            }
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(weeks, id: \.start) { week in
                    let lifts = week.items.compactMap { if case let .lift(s) = $0 { s } else { nil } }
                    let courts = week.items.compactMap { if case let .court(s) = $0 { s } else { nil } }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            Eyebrow("Week of \(week.start.monthDay)", color: Theme.textPrimary)
                            Spacer()
                            Text("\(lifts.count) lifts · \(formatter.volume(lifts.map(\.volumeKg).reduce(0, +)))")
                            Text("\(courts.count) court · load \(courts.map(\.log.load).reduce(0, +))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        ForEach(week.items) { item in
                            switch item {
                            case let .lift(session): liftRow(session, formatter: formatter)
                            case let .court(session): courtRow(session)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func liftRow(_ session: WorkoutSessionRecord, formatter: UnitFormatter) -> some View {
        let byExercise = Dictionary(grouping: session.sets.filter { !$0.isWarmup }, by: \.exerciseID)
        var order: [UUID] = []
        for set in session.sets where !order.contains(set.exerciseID) { order.append(set.exerciseID) }
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(order, id: \.self) { id in
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercises[id]?.name ?? "Exercise").font(.system(size: 12, weight: .semibold)).frame(width: 220, alignment: .leading)
                        Text((byExercise[id] ?? []).map { "\(formatter.weightValue($0.weightKg))×\($0.reps)" }.joined(separator: "  "))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                        if (byExercise[id] ?? []).contains(where: { !$0.prKinds.isEmpty }) {
                            Image(systemName: "trophy.fill").foregroundStyle(Theme.scoreboard)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill").foregroundStyle(Theme.hardwood).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(session.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(session.sets.count) sets").foregroundStyle(Theme.textSecondary)
                Text(formatter.volume(session.volumeKg)).font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                if session.prCount > 0 {
                    Label("\(session.prCount)", systemImage: "trophy.fill").foregroundStyle(Theme.scoreboard)
                        .font(.system(size: 12, weight: .bold))
                }
                if session.isDemo { DemoBadge() }
            }
        }
        .card(padding: 12)
        .contextMenu {
            Button("Delete workout", systemImage: "trash", role: .destructive) {
                context.delete(session)
                try? context.save()
            }
        }
    }

    private func courtRow(_ session: CourtSessionRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "basketball.fill").foregroundStyle(Theme.paint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.kind.title).font(.system(size: 14, weight: .bold, design: .rounded))
                Text(session.date.formatted(.dateTime.weekday(.wide).month().day()) + (session.notes.isEmpty ? "" : " · \(session.notes)"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Text("\(session.minutes) min · RPE \(session.rpe)").foregroundStyle(Theme.textSecondary)
            Text("load \(session.log.load)").font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.paint)
            if session.isDemo { DemoBadge() }
        }
        .card(padding: 12)
        .contextMenu {
            Button("Delete session", systemImage: "trash", role: .destructive) {
                context.delete(session)
                try? context.save()
            }
        }
    }
}

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    var exercises: [ExerciseRecord]
    var sessions: [WorkoutSessionRecord]
    var units: UnitSystem
    @State private var search = ""
    @State private var editing: ExerciseRecord?

    var body: some View {
        let bests = TrainingActions.personalBests(sessions)
        let formatter = UnitFormatter(system: units)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search exercises", text: $search).textFieldStyle(.roundedBorder).frame(width: 260)
                Spacer()
                Button {
                    let exercise = ExerciseRecord(name: "")
                    context.insert(exercise)
                    editing = exercise
                } label: { Label("Custom exercise", systemImage: "plus") }
                    .buttonStyle(HardwoodButtonStyle(compact: true))
            }
            .padding(.horizontal, 24)
            List {
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    let matches = exercises.filter { !$0.isArchived && $0.muscle == muscle && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
                    if !matches.isEmpty {
                        Section(muscle.title) {
                            ForEach(matches) { exercise in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(exercise.name).font(.system(size: 13, weight: .semibold))
                                            if !exercise.isBuiltIn { Text("CUSTOM").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.hardwood) }
                                        }
                                        Text("\(exercise.equipment.title) · \(exercise.isCompound ? "Compound" : "Isolation") · rest \(exercise.defaultRestSeconds)s")
                                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    if let best = bests[exercise.id], best.heaviest > 0 {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text("e1RM \(formatter.weight(best.e1RM, decimals: 0))")
                                                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                                                .foregroundStyle(Theme.scoreboard)
                                            Text("top \(formatter.weight(best.heaviest))").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { editing = exercise }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = exercise }
                                    if !exercise.isBuiltIn {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            context.delete(exercise)
                                            try? context.save()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .sheet(item: $editing) { exercise in ExerciseEditor(exercise: exercise) }
    }
}

struct ExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var exercise: ExerciseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exercise.name.isEmpty ? "New exercise" : exercise.name).font(.system(size: 22, weight: .heavy, design: .rounded))
            Form {
                TextField("Name", text: $exercise.name)
                Picker("Muscle", selection: $exercise.muscleRaw) {
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Equipment", selection: $exercise.equipmentRaw) {
                    ForEach(Equipment.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Compound lift", isOn: $exercise.isCompound)
                IntStepperField(label: "Default rest", value: $exercise.defaultRestSeconds, range: 15...300, unit: "s")
                TextField("Notes", text: $exercise.notes, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") {
                    if exercise.name.isEmpty { context.delete(exercise) } else { context.rollback() }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(HardwoodButtonStyle(compact: true))
                .keyboardShortcut(.defaultAction)
                .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
