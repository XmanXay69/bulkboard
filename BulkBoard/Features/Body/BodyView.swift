import BulkCore
import Charts
import SwiftData
import SwiftUI

struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var profile: ProfileRecord
    @Query(sort: \BodyCheckInRecord.date, order: .reverse) private var checkIns: [BodyCheckInRecord]
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]
    @State private var draft: CheckInDraft?

    private var units: UnitFormatter { UnitFormatter(system: profile.unitSystem) }

    var body: some View {
        @Bindable var appModel = appModel
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                PageHeader(title: "Body & Dunk", subtitle: "Measurements, weak points, and what it takes to dunk") {
                    HStack(spacing: 10) {
                        Picker("View", selection: $appModel.bodyTab) {
                            ForEach(BodyTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                        Button { newCheckIn() } label: { Label("New check-in", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if checkIns.isEmpty {
                    EmptyStateView(symbol: "ruler", title: "Add your first check-in",
                                   message: "Height, wingspan, a few tape measurements and your jump numbers. Add a photo if you want an AI second opinion. Takes about five minutes.",
                                   actionTitle: "New check-in") { newCheckIn() }
                        .card()
                } else {
                    switch appModel.bodyTab {
                    case .physique:
                        PhysiqueTab(profile: profile, checkIns: checkIns, units: units)
                    case .dunk:
                        DunkTab(profile: profile, checkIns: checkIns, latestWeightKg: weights.first?.weightKg, units: units) { newCheckIn() }
                    }
                }
            }
            .padding(24)
            .background(Theme.background)
        }
        .sheet(item: $draft) { draft in CheckInSheet(draft: draft) }
    }

    private func newCheckIn() {
        draft = CheckInDraft(units: units, previous: checkIns.first?.measurements, heightCm: profile.heightCm,
                             weightKg: weights.first?.weightKg)
    }
}

// MARK: - Physique

struct PhysiqueTab: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var profile: ProfileRecord
    var checkIns: [BodyCheckInRecord]
    var units: UnitFormatter

    private var latest: BodyCheckInRecord { checkIns[0] }
    private var previous: BodyCheckInRecord? { checkIns.count > 1 ? checkIns[1] : nil }

    var body: some View {
        let report = BodyActions.report(latestOf: checkIns, sex: profile.sex)
        let review = latest.aiNotes.flatMap { Blob.decode(PhysiqueReview?.self, from: Data($0.utf8), default: nil) }
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(alignment: .top, spacing: Theme.spacing) {
                CheckInSummaryCard(checkIn: latest, previous: previous, report: report, units: units, count: checkIns.count)
                    .frame(width: 330)
                ProportionsCard(report: report, units: units)
            }
            HStack(alignment: .top, spacing: Theme.spacing) {
                AIReviewCard(checkIn: latest, report: report, review: review, sex: profile.sex)
                FocusCard(profile: profile, report: report, review: review)
            }
        }
    }
}

struct CheckInSummaryCard: View {
    @Environment(\.modelContext) private var context
    var checkIn: BodyCheckInRecord
    var previous: BodyCheckInRecord?
    var report: PhysiqueReport?
    var units: UnitFormatter
    var count: Int
    @State private var confirmDelete = false

    var body: some View {
        let m = checkIn.measurements
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Latest check-in · \(checkIn.date.formatted(date: .abbreviated, time: .omitted))")
                Spacer()
                Menu {
                    Button("Delete check-in", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            if let filename = checkIn.photoFilename, let image = PhotoStore.image(filename) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 260).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if let m {
                HStack(spacing: 22) {
                    StatView(value: units.weightValue(m.weightKg), label: "Weight", unit: units.massUnit, size: 22)
                    if let bf = report?.bodyFatPercent {
                        StatView(value: Fmt.number(bf), label: report?.bodyFatIsEstimate == true ? "Body fat (est.)" : "Body fat", unit: "%", size: 22)
                    }
                    if let ffmi = report?.ffmi {
                        StatView(value: Fmt.number(ffmi), label: "FFMI", size: 22)
                    }
                }
                if let band = report?.ffmiBand {
                    Text(report?.leanToNextBandKg.map { "\(band). About \(units.weight($0, decimals: 0)) more lean mass reaches the next level." } ?? band)
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let previous, let before = previous.measurements {
                    Divider()
                    SectionLabel("Since \(previous.date.monthDay)")
                    changes(from: before, to: m)
                }
            }
            Text("\(count) check-in\(count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .card()
        .confirmationDialog("Delete this check-in?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { BodyActions.delete(checkIn, context: context) }
        } message: {
            Text("Its photo is deleted too.")
        }
    }

    private func changes(from a: BodyMeasurements, to b: BodyMeasurements) -> some View {
        let rows: [(String, Double?, Double?, Bool)] = [
            ("Weight", a.weightKg, b.weightKg, true), ("Chest", a.chestCm, b.chestCm, false), ("Arm", a.armCm, b.armCm, false),
            ("Waist", a.waistCm, b.waistCm, false), ("Thigh", a.thighCm, b.thighCm, false), ("Calf", a.calfCm, b.calfCm, false),
            ("Running touch", a.approachTouchCm, b.approachTouchCm, false),
        ]
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                if let old = row.1, let new = row.2 {
                    HStack {
                        Text(row.0).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        let delta = new - old
                        Text(row.3 ? units.signedWeight(delta) : "\(delta >= 0 ? "+" : "−")\(units.length(abs(delta)))")
                            .foregroundStyle(Theme.textPrimary).monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}

struct ProportionsCard: View {
    var report: PhysiqueReport?
    var units: UnitFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proportions").font(.system(size: 15, weight: .semibold))
                    Text("Each part vs a classic target scaled to your frame. Lowest first.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let vTaper = report?.vTaper {
                    StatView(value: Fmt.number(vTaper, maxDecimals: 2), label: "V-taper (goal 1.6)", size: 20)
                }
            }
            if let report, !report.parts.isEmpty {
                VStack(spacing: 10) {
                    ForEach(report.parts) { score in
                        ProportionRow(score: score, units: units,
                                      tag: report.lagging.contains(score.part) ? "Focus" : report.strengths.contains(score.part) ? "Strong" : nil)
                    }
                }
                if !report.notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text("Add tape measurements (and your wrist) to see how each part compares.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

struct ProportionRow: View {
    var score: PartScore
    var units: UnitFormatter
    var tag: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(score.part.title).font(.system(size: 13, weight: .medium))
                if let tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .foregroundStyle(tag == "Focus" ? Theme.accent : Theme.textSecondary)
                        .background(tag == "Focus" ? Theme.accent.opacity(0.1) : Theme.surfaceRaised, in: Capsule())
                }
            }
            .frame(width: 140, alignment: .leading)
            GeometryReader { proxy in
                let scale = proxy.size.width / 1.2
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule().fill(tag == "Focus" ? Theme.accent : Theme.textSecondary.opacity(0.6))
                        .frame(width: min(proxy.size.width, max(4, score.ratio * scale)))
                    Rectangle().fill(Theme.textPrimary.opacity(0.5)).frame(width: 1.5, height: 12).offset(x: scale - 0.75)
                }
            }
            .frame(height: 6)
            Text("\(Fmt.int(score.ratio * 100))%").font(.system(size: 12, weight: .semibold).monospacedDigit()).frame(width: 40, alignment: .trailing)
            Text("\(units.length(score.actualCm)) / \(units.length(score.targetCm))")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .frame(width: 120, alignment: .trailing)
        }
        .help("Target \(units.length(score.targetCm)). The tick marks 100%.")
    }
}

/// The local AI coach's read on the latest check-in: what's behind, and what to change in training and food.
/// Runs by itself when the AI is ready, so the card fills in without a click.
struct AIReviewCard: View {
    @Environment(\.modelContext) private var context
    var checkIn: BodyCheckInRecord
    var report: PhysiqueReport?
    var review: PhysiqueReview?
    var sex: Sex

    @State private var client = OllamaClient.shared
    @State private var coach = BodyCoach.shared

    private var isReviewing: Bool { coach.reviewing.contains(checkIn.id) }

    private var photoNote: String {
        guard review?.usedPhoto == true else { return "" }
        guard let date = review?.photoDate, !Calendar.bulk.isDate(date, inSameDayAs: checkIn.date) else { return " · with photo" }
        return " · photo from \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI coach", systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
                Spacer()
                if let model = checkIn.aiModel, review != nil {
                    Text("\(model)\(photoNote)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                }
            }
            if isReviewing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reviewing your check-in, plan and recent meals on this Mac…")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            } else if let review {
                reviewBody(review)
            }
            if !isReviewing { setupOrActions }
            if let error = coach.errors[checkIn.id], !isReviewing { WarningBanner(message: error, serious: true) }
        }
        .card()
        .task(id: checkIn.id) {
            await client.connect()
            coach.reviewIfNeeded(checkIn, context: context)
        }
        .onChange(of: client.isAvailable) { _, ready in
            if ready { coach.reviewIfNeeded(checkIn, context: context) }
        }
    }

    @ViewBuilder
    private func reviewBody(_ review: PhysiqueReview) -> some View {
        if !review.lagging.isEmpty {
            LabeledContent("Behind") { Text(review.lagging.joined(separator: ", ").capitalized) }.font(.system(size: 13, weight: .medium))
        }
        if !review.strengths.isEmpty {
            LabeledContent("Strong") { Text(review.strengths.joined(separator: ", ").capitalized) }.font(.system(size: 13))
        }
        bullets("What it sees", review.observations)
        bullets("Training", review.training)
        bullets("Food", review.nutrition)
        bullets("Dunk", review.dunk)
        Text("An AI opinion from your numbers\(review.usedPhoto == true ? " and photo" : ""). The tape is the steadier signal. Apply focus areas on the right to change the plan.")
            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func bullets(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                ForEach(lines, id: \.self) { line in
                    Text("• \(line)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var setupOrActions: some View {
        if client.pull != nil || !client.isInstalled || (!client.isAvailable && !client.isStarting) {
            AIModelSetupView()
            if client.isInstalled && client.pull == nil && !client.isAvailable {
                Button("Start Ollama") { Task { await client.startServer() } }.buttonStyle(.bordered).controlSize(.small)
            }
        } else if client.isStarting || client.isChecking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting the local AI…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        } else {
            if checkIn.photoFilename != nil && !client.canSeeImages {
                Text("Your photo isn't included yet: the installed model can't read images.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                AIModelSetupView()
            }
            HStack {
                Button(review == nil ? "Review this check-in" : "Review again") { coach.review(checkIn, context: context) }
                    .buttonStyle(.bordered).controlSize(.small)
                if checkIn.photoFilename == nil && review?.usedPhoto != true {
                    Text("Add a photo to a check-in for a visual read too.").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

struct FocusCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var profile: ProfileRecord
    var report: PhysiqueReport?
    var review: PhysiqueReview?
    @State private var selection: Set<MuscleGroup> = []
    @State private var raiseProtein = true

    static let choices: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .quads, .hamstrings, .glutes, .calves, .core]

    private var suggested: Set<MuscleGroup> {
        var muscles = report?.focusMuscles ?? []
        for part in review?.laggingParts ?? [] { muscles.formUnion(part.muscles) }
        if review?.mentionsCore == true { muscles.insert(.core) }
        return muscles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus areas").font(.system(size: 15, weight: .semibold))
                Text("Extra sets and an accessory for these on the days that train them.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(Self.choices, id: \.self) { muscle in
                    Chip(title: muscle.title + (suggested.contains(muscle) && !selection.contains(muscle) ? " ·" : ""),
                         isOn: selection.contains(muscle)) {
                        if selection.contains(muscle) { selection.remove(muscle) } else { selection.insert(muscle) }
                    }
                }
            }
            if !suggested.isEmpty && suggested != selection {
                Button("Use suggestion: \(suggested.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", "))") {
                    selection = suggested
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            Toggle("Raise protein to 1.0 g/lb while specializing", isOn: $raiseProtein)
                .font(.system(size: 13))
            Text("Food can't aim at one muscle. Calories and protein fuel growth everywhere; the extra sets decide where it shows up.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(profile.focusMuscles == selection ? "Applied" : "Apply to my plan") {
                    BodyActions.applyFocus(selection, raiseProtein: raiseProtein && !selection.isEmpty, profile: profile, context: context)
                    appModel.celebrate(.workoutComplete, title: "Training plan updated",
                                       detail: selection.isEmpty ? "Focus cleared" : "Extra work for \(selection.map(\.title).sorted().joined(separator: ", ").lowercased())")
                }
                .buttonStyle(.borderedProminent)
                .disabled(profile.focusMuscles == selection)
                if !profile.focusMuscles.isEmpty {
                    Button("Clear focus") {
                        selection = []
                        BodyActions.applyFocus([], raiseProtein: false, profile: profile, context: context)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("See the plan") {
                    appModel.section = .training
                    appModel.trainingTab = .week
                }
                .buttonStyle(.link)
            }
        }
        .card()
        .onAppear { selection = profile.focusMuscles.isEmpty ? suggested : profile.focusMuscles }
    }
}

// MARK: - Dunk

struct DunkTab: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var profile: ProfileRecord
    var checkIns: [BodyCheckInRecord]
    var latestWeightKg: Double?
    var units: UnitFormatter
    var onUpdate: () -> Void
    @State private var leanGain = true

    var body: some View {
        let inputs = BodyActions.dunkInputs(profile: profile, checkIn: checkIns.first, latestWeightKg: latestWeightKg)
        let report = DunkCalculator.report(inputs)
        VStack(alignment: .leading, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(report)).font(.system(size: 20, weight: .bold))
                        Text(subline(report)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Update jump numbers") { onUpdate() }.buttonStyle(.bordered)
                }
                HStack(spacing: 30) {
                    StatView(value: units.tall(report.reachCm), label: report.reachIsEstimate ? "Standing reach (est.)" : "Standing reach", size: 24)
                    StatView(value: units.tall(report.requiredTouchCm), label: "Need to touch", size: 24)
                    StatView(value: report.currentJumpCm.map { units.tall(report.reachCm + $0) } ?? "–",
                             label: report.currentJumpIsEstimate ? "Your touch (est.)" : "Your best touch", size: 24)
                    StatView(value: gapText(report), label: (report.gapCm ?? 1) <= 0 ? "Clearance" : "Gap", size: 24)
                    Spacer()
                }
                DunkGauge(report: report, units: units)
                    .frame(height: 70)
            }
            .card(padding: 20)

            HStack(alignment: .top, spacing: Theme.spacing) {
                bulkCard(report)
                programCard(report)
            }
            touchHistory(report)
        }
    }

    private func headline(_ report: DunkReport) -> String {
        switch report.verdict {
        case .canDunk: "You can dunk"
        case .close: "Almost there"
        case .reachable: "Within reach"
        case .longTerm: "A longer project"
        case nil: "Add your jump numbers"
        }
    }

    private func subline(_ report: DunkReport) -> String {
        guard let gap = report.gapCm else {
            return "Rim is 10 ft. With your reach you need a \(units.length(report.requiredJumpCm, decimals: 0)) running jump. Log a standing vertical or your best running touch to see the gap."
        }
        if gap <= 0 { return "Your running touch clears what a dunk needs by \(units.length(-gap, decimals: 0)). Work on doing it on demand." }
        let weeks = report.estimatedWeeks.map { "Rough estimate: \($0.lowerBound)–\($0.upperBound) weeks of focused jump training." } ?? ""
        return "You need a \(units.length(report.requiredJumpCm, decimals: 0)) running jump and you're about \(units.length(gap, decimals: 0)) short. \(weeks)"
    }

    private func gapText(_ report: DunkReport) -> String {
        guard let gap = report.gapCm else { return "–" }
        return units.length(abs(gap), decimals: 1)
    }

    private func bulkCard(_ report: DunkReport) -> some View {
        let perStep = units.system == .imperial ? Units.kg(fromLb: 10) : 5.0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Bulking vs. dunking").font(.system(size: 15, weight: .semibold))
            Text("At the same leg power, every \(units.system == .imperial ? "10 lb" : "5 kg") you add costs about \(units.length(report.jumpLossPerKgCm * perStep)) of running jump.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            if let projected = report.projectedJumpAtGoalCm, let current = report.currentJumpCm {
                LabeledContent("Jump at \(units.weight(profile.goalWeightKg, decimals: 0)), same power") {
                    let delta = projected - current
                    Text("\(units.length(projected)) (\(delta < 0 ? "−" : "+")\(units.length(abs(delta))))").monospacedDigit()
                }
                .font(.system(size: 13))
            }
            if let more = report.powerIncreaseNeededAtGoal {
                LabeledContent("Power needed to dunk at goal weight") {
                    Text(more <= 0 ? "You already have it" : "+\(Fmt.int(more * 100))%").monospacedDigit()
                }
                .font(.system(size: 13))
            }
            Text("Strength and jump work have to outpace the weight gain. A slower bulk makes that easier.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func programCard(_ report: DunkReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dunk program").font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Label("Depth jumps and trap-bar jumps to start leg days", systemImage: "arrow.up")
                Label("Calf raises and pogo jumps for stiff, springy ankles", systemImage: "arrow.up")
                Label("Approach jumps to the rim on court days, full rest", systemImage: "arrow.up")
                Label("Heavy squats and hinges stay in to build force", systemImage: "arrow.up")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            Toggle("Cap weight gain at 0.5 lb/week while chasing the dunk", isOn: $leanGain)
                .font(.system(size: 13))
                .disabled(!profile.goalMode.isGain)
            HStack {
                Button(profile.dunkGoal ? "Turn off dunk program" : "Add to my training plan") {
                    let turningOn = !profile.dunkGoal
                    BodyActions.setDunkGoal(turningOn, leanGain: leanGain, profile: profile, context: context)
                    appModel.celebrate(.workoutComplete, title: "Training plan updated",
                                       detail: turningOn ? "Jump training added" : "Jump training removed")
                }
                .buttonStyle(profile.dunkGoal ? AnyPrimitiveButtonStyle(.bordered) : AnyPrimitiveButtonStyle(.borderedProminent))
                Spacer()
                Text("Re-test every 2–3 weeks").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func touchHistory(_ report: DunkReport) -> some View {
        let points = checkIns.compactMap { record -> (Date, Double)? in
            guard let m = record.measurements else { return nil }
            if let touch = m.approachTouchCm { return (record.date, touch) }
            if let standing = m.standingVerticalCm { return (record.date, report.reachCm + standing * DunkCalculator.approachFactor) }
            return nil
        }.sorted { $0.0 < $1.0 }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Running touch over time").font(.system(size: 15, weight: .semibold))
                Chart {
                    ForEach(points, id: \.0) { date, touch in
                        LineMark(x: .value("Date", date), y: .value("Touch", units.lengthValue(touch)))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(ChartPalette.series)
                        PointMark(x: .value("Date", date), y: .value("Touch", units.lengthValue(touch)))
                            .foregroundStyle(ChartPalette.series)
                    }
                    RuleMark(y: .value("Dunk", units.lengthValue(report.requiredTouchCm)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(ChartPalette.neutral)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Dunk line \(units.tall(report.requiredTouchCm))").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .bulkChartAxes()
                .frame(height: 180)
            }
            .card()
        }
    }
}

/// Horizontal gauge from 7 ft to 11 ft: standing reach, best touch, the rim and the dunk line.
struct DunkGauge: View {
    var report: DunkReport
    var units: UnitFormatter

    private let low = 213.0
    private let high = 335.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x: (Double) -> CGFloat = { CGFloat((min(max($0, low), high) - low) / (high - low)) * width }
            let touch = report.currentJumpCm.map { report.reachCm + $0 }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.surfaceRaised).frame(height: 10).offset(y: 30)
                if let touch {
                    Capsule().fill(Theme.accent.opacity(0.35)).frame(width: x(touch), height: 10).offset(y: 30)
                }
                Capsule().fill(Theme.textSecondary.opacity(0.6)).frame(width: x(report.reachCm), height: 10).offset(y: 30)
                marker(at: x(DunkCalculator.rimCm), label: "Rim 10′", y: 0, color: Theme.textSecondary)
                marker(at: x(report.requiredTouchCm), label: "Dunk", y: 0, color: Theme.accent, alignTrailing: false)
                Text("Reach").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                    .offset(x: max(0, x(report.reachCm) - 34), y: 46)
                if let touch {
                    Text("You").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                        .offset(x: max(0, x(touch) - 22), y: 46)
                }
            }
        }
    }

    private func marker(at position: CGFloat, label: String, y: CGFloat, color: Color, alignTrailing: Bool = true) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(color).frame(width: 1.5, height: 30).offset(x: position, y: 16)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
                .fixedSize()
                .offset(x: alignTrailing ? position - 46 : position + 4, y: y)
        }
    }
}

/// Lets a button switch between two primitive styles.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
