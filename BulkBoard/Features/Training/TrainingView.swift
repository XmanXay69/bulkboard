import BulkCore
import SwiftData
import SwiftUI

struct TrainingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Bindable var profile: ProfileRecord
    @Query(sort: \WorkoutSessionRecord.date, order: .reverse) private var sessions: [WorkoutSessionRecord]
    @Query(sort: \ExerciseRecord.name) private var exercises: [ExerciseRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]
    @Query(sort: \CourtSessionRecord.date, order: .reverse) private var courtSessions: [CourtSessionRecord]

    private var exerciseLookup: [UUID: ExerciseRecord] {
        Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        @Bindable var appModel = appModel
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Training", subtitle: "\(profile.liftingDays) lift · \(profile.courtDays) court · \(max(0, 7 - profile.liftingDays - profile.courtDays)) rest days a week") {
                HStack(spacing: 10) {
                    Picker("Tab", selection: $appModel.trainingTab) {
                        ForEach(TrainingTab.allCases, id: \.self) { tab in
                            Text(tab == .log && sessions.contains { !$0.isCompleted } ? "Log ●" : tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 360)
                    Button { appModel.activeSheet = .court(minutes: 60, kind: .pickup) } label: {
                        Label("Log court session", systemImage: "basketball")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Log a basketball or conditioning session (⇧⌘B)")
                }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)

            switch appModel.trainingTab {
            case .week:
                WeekPlanView(profile: profile, plan: plans.first, sessions: sessions, courtSessions: courtSessions,
                             exercises: exerciseLookup) { day in
                    start(day)
                } onLogCourt: { day in
                    appModel.activeSheet = .court(minutes: day.block?.minutes ?? 60, kind: day.title.contains("Pickup") ? .pickup : .conditioning)
                }
            case .log:
                WorkoutLoggerView(profile: profile, plan: plans.first, sessions: sessions, exercises: exerciseLookup,
                                  allExercises: exercises)
            case .history:
                TrainingHistoryView(sessions: sessions.filter(\.isCompleted), courtSessions: courtSessions,
                                    exercises: exerciseLookup, units: profile.unitSystem)
            case .exercises:
                ExerciseLibraryView(exercises: exercises, sessions: sessions, units: profile.unitSystem)
            }
        }
    }

    private func start(_ day: PlannedDay) {
        if let active = TrainingActions.activeSession(context), active.sets.contains(where: \.isDone) {
            appModel.trainingTab = .log
            return
        }
        if let active = TrainingActions.activeSession(context) { TrainingActions.discard(active, context: context) }
        TrainingActions.startSession(from: day, context: context)
        appModel.trainingTab = .log
    }
}

// MARK: - Week plan

struct WeekPlanView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: ProfileRecord
    var plan: WorkoutPlanRecord?
    var sessions: [WorkoutSessionRecord]
    var courtSessions: [CourtSessionRecord]
    var exercises: [UUID: ExerciseRecord]
    var onStart: (PlannedDay) -> Void
    var onLogCourt: (PlannedDay) -> Void

    @State private var lifting = 4
    @State private var court = 2

    private var weekStart: Date { Date.now.weekStart }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    IntStepperField(label: "Lifting days", value: $lifting, range: 0...6)
                        .frame(width: 190)
                    IntStepperField(label: "Court days", value: $court, range: 0...max(0, 7 - lifting))
                        .frame(width: 180)
                    Text("\(max(0, 7 - lifting - court)) rest").foregroundStyle(Theme.textSecondary)
                    if lifting != profile.liftingDays || court != profile.courtDays {
                        Button("Rebuild week") { rebuild() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Button("Regenerate") { rebuild() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .help("Rebuild the split from your current settings")
                    }
                    Spacer()
                    Text(profile.goalMode == .bulk ? "Hypertrophy focus" : "Plyos + strength for the court")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                }
                .card(padding: 12)

                if let plan {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(plan.days) { day in
                            let date = weekStart.adding(days: day.weekday)
                            DayPlanCard(day: day, date: date, exercises: exercises,
                                        isDone: isDone(day, on: date), onStart: { onStart(day) }, onLogCourt: { onLogCourt(day) })
                        }
                    }
                } else {
                    EmptyStateView(symbol: "dumbbell", title: "No plan yet", message: "Pick your days and build the week.",
                                   actionTitle: "Build my week") { rebuild() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            lifting = profile.liftingDays
            court = profile.courtDays
        }
    }

    private func isDone(_ day: PlannedDay, on date: Date) -> Bool {
        switch day.dayType {
        case .lifting: sessions.contains { $0.isCompleted && Calendar.bulk.isDate($0.date, inSameDayAs: date) }
        case .conditioning: courtSessions.contains { Calendar.bulk.isDate($0.date, inSameDayAs: date) }
        case .rest: false
        }
    }

    private func rebuild() {
        profile.liftingDays = lifting
        profile.courtDays = court
        withAnimation(.spring) { TrainingActions.regeneratePlan(for: profile, context: context) }
        try? context.save()
    }
}

struct DayPlanCard: View {
    var day: PlannedDay
    var date: Date
    var exercises: [UUID: ExerciseRecord]
    var isDone: Bool
    var onStart: () -> Void
    var onLogCourt: () -> Void

    private var isToday: Bool { Calendar.bulk.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(WeekMath.weekdayLong[day.weekday])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.accent : Theme.textSecondary)
                if isToday { Text("TODAY").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent) }
                Spacer()
                DayTypeBadge(dayType: day.dayType)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(day.focus).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            if !day.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(day.exercises) { planned in
                        HStack {
                            Text(exercises[planned.exerciseID]?.name ?? "Exercise")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(planned.sets) × \(planned.repText)")
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            if let block = day.block {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(block.items, id: \.self) { item in
                        Label(item, systemImage: day.dayType == .conditioning ? "basketball" : "leaf")
                            .font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                            .labelStyle(.titleAndIcon)
                    }
                    Text("~\(block.minutes) min").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            HStack {
                if isDone {
                    Label("Done", systemImage: "checkmark.seal.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.positive)
                }
                Spacer()
                switch day.dayType {
                case .lifting:
                    Button { onStart() } label: { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                case .conditioning:
                    Button { onLogCourt() } label: { Label("Log it", systemImage: "basketball.fill") }
                        .buttonStyle(.bordered).controlSize(.small)
                case .rest:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .card(padding: 16)
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(isToday ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
    }
}

// MARK: - Court sessions

struct CourtSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @State var minutes: Int
    @State var kind: CourtSessionKind
    @State private var date = Date.now
    @State private var rpe = 7.0
    @State private var notes = ""

    private var rpeLabel: String {
        switch Int(rpe) {
        case ...3: "Easy"
        case 4...5: "Moderate"
        case 6...7: "Hard"
        case 8...9: "Very hard"
        default: "All-out"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "basketball.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text("Log a court session").font(.system(size: 22, weight: .semibold))
            }
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(CourtSessionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                DatePicker("When", selection: $date)
                IntStepperField(label: "Duration", value: $minutes, range: 5...240, unit: "min")
                LabeledContent("Intensity") {
                    HStack {
                        Slider(value: $rpe, in: 1...10, step: 1)
                        Text("\(Int(rpe)) · \(rpeLabel)").font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 96, alignment: .trailing)
                    }
                }
                LabeledContent("Conditioning load") {
                    Text("\(minutes * Int(rpe))").font(.stat(18)).foregroundStyle(Theme.accent)
                }
                TextField("Notes", text: $notes, prompt: Text("Ran 5s at the Y, legs felt heavy…"), axis: .vertical)
            }
            .formStyle(.grouped)
            Text("Load = minutes × RPE (session-RPE), so court work shows up next to lifting volume.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    TrainingActions.logCourtSession(date: date, kind: kind, minutes: minutes, rpe: Int(rpe), notes: notes, context: context)
                    appModel.celebrate(.workoutComplete, title: kind.title, detail: "\(minutes) min · load \(minutes * Int(rpe))")
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
