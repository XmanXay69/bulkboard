import AppKit
import BulkCore
import SwiftData
import SwiftUI

/// Measurements in display units while editing. Blank fields stay nil.
@Observable
final class CheckInDraft: Identifiable {
    let id = UUID()
    let units: UnitFormatter
    var date = Date.now
    var height: Double?
    var weight: Double?
    var wingspan: Double?
    var standingReach: Double?
    var wrist: Double?
    var neck: Double?
    var shoulders: Double?
    var chest: Double?
    var waist: Double?
    var hips: Double?
    var arm: Double?
    var forearm: Double?
    var thigh: Double?
    var calf: Double?
    var bodyFat: Double?
    var standingVertical: Double?
    var approachTouch: Double?
    var canPalm = false
    var photo: Data?
    var logWeight = true

    init(units: UnitFormatter, previous: BodyMeasurements?, heightCm: Double, weightKg: Double?) {
        self.units = units
        let len: (Double?) -> Double? = { $0.map { (units.lengthValue($0) * 10).rounded() / 10 } }
        height = len(previous?.heightCm ?? heightCm)
        weight = (weightKg ?? previous?.weightKg).map { (Units.display(kg: $0, in: units.system) * 10).rounded() / 10 }
        wingspan = len(previous?.wingspanCm)
        standingReach = len(previous?.standingReachCm)
        wrist = len(previous?.wristCm)
        neck = len(previous?.neckCm)
        shoulders = len(previous?.shouldersCm)
        chest = len(previous?.chestCm)
        waist = len(previous?.waistCm)
        hips = len(previous?.hipsCm)
        arm = len(previous?.armCm)
        forearm = len(previous?.forearmCm)
        thigh = len(previous?.thighCm)
        calf = len(previous?.calfCm)
        bodyFat = previous?.bodyFatPercent
        standingVertical = len(previous?.standingVerticalCm)
        approachTouch = len(previous?.approachTouchCm)
        canPalm = previous?.canPalmBall ?? false
    }

    var isValid: Bool { (height ?? 0) > 0 && (weight ?? 0) > 0 }

    var measurements: BodyMeasurements {
        let cm: (Double?) -> Double? = { $0.flatMap { $0 > 0 ? self.units.cm(fromDisplay: $0) : nil } }
        return BodyMeasurements(
            heightCm: cm(height) ?? 0, weightKg: Units.kg(fromDisplay: weight ?? 0, in: units.system),
            wingspanCm: cm(wingspan), standingReachCm: cm(standingReach), wristCm: cm(wrist), neckCm: cm(neck),
            shouldersCm: cm(shoulders), chestCm: cm(chest), waistCm: cm(waist), hipsCm: cm(hips), armCm: cm(arm),
            forearmCm: cm(forearm), thighCm: cm(thigh), calfCm: cm(calf), bodyFatPercent: bodyFat.flatMap { $0 > 0 ? $0 : nil },
            standingVerticalCm: cm(standingVertical), approachTouchCm: cm(approachTouch), canPalmBall: canPalm)
    }
}

struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @Bindable var draft: CheckInDraft
    @State private var error: String?

    private var unit: String { draft.units.lengthUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New check-in").font(.system(size: 20, weight: .bold))
                Spacer()
                DatePicker("Date", selection: $draft.date, displayedComponents: .date).labelsHidden()
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Basics") {
                        field("Height", $draft.height, unit)
                        field("Weight", $draft.weight, draft.units.massUnit)
                        Toggle("Also log this as today's weigh-in", isOn: $draft.logWeight)
                    }
                    Section {
                        field("Wingspan", $draft.wingspan, unit, hint: "Fingertip to fingertip, arms straight out")
                        field("Standing reach", $draft.standingReach, unit, hint: "Flat-footed, one arm straight up. Leave blank to estimate")
                        field("Wrist", $draft.wrist, unit, hint: "Smallest point, just above the bone. Sets your proportion targets")
                    } header: {
                        Text("Frame and reach")
                    }
                    Section {
                        field("Neck", $draft.neck, unit, hint: "Below the Adam's apple")
                        field("Shoulders", $draft.shoulders, unit, hint: "Around the widest part of the delts, arms relaxed")
                        field("Chest", $draft.chest, unit, hint: "At the nipples, after a normal exhale")
                        field("Waist", $draft.waist, unit, hint: "At the belly button, relaxed")
                        field("Hips", $draft.hips, unit, hint: "Widest part of the glutes")
                        field("Upper arm", $draft.arm, unit, hint: "Flexed, at the peak")
                        field("Forearm", $draft.forearm, unit, hint: "Widest part, fist clenched")
                        field("Thigh", $draft.thigh, unit, hint: "Just below the glute fold")
                        field("Calf", $draft.calf, unit, hint: "Widest part, standing")
                        field("Body fat", $draft.bodyFat, "%", hint: "Optional. Estimated from neck and waist if blank")
                    } header: {
                        Text("Tape measurements")
                    } footer: {
                        Text("Skip anything you don't have. Measure the same way, same time of day, each check-in.")
                    }
                    Section {
                        field("Standing vertical", $draft.standingVertical, unit, hint: "Two-foot jump from a standstill: touch height minus reach")
                        field("Best running touch", $draft.approachTouch, unit, hint: "Highest point you can touch on an approach jump (10 ft = 120 in)")
                        Toggle("I can palm a basketball", isOn: $draft.canPalm)
                    } header: {
                        Text("Jumping")
                    }
                }
                .formStyle(.grouped)

                photoColumn
                    .frame(width: 230)
                    .padding(.top, 20)
                    .padding(.trailing, 20)
            }

            if let error { WarningBanner(message: error, serious: true).padding(.horizontal, 20) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save check-in") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid)
            }
            .padding(20)
        }
        .frame(width: 760, height: 720)
    }

    private var photoColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Photo (optional)")
            PhotoInput(photo: $draft.photo, height: 300, prompt: "Front-facing, relaxed, good light")
            Text("Stays on this Mac; location data is stripped. Only the AI model running on this Mac sees it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(_ label: String, _ value: Binding<Double?>, _ unit: String, hint: String? = nil) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .labelsHidden()
                Text(unit).foregroundStyle(Theme.textSecondary).frame(width: 22, alignment: .leading)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
            }
        }
    }

    private func save() {
        do {
            let record = try BodyActions.saveCheckIn(draft.measurements, date: draft.date, photo: draft.photo,
                                                     logWeight: draft.logWeight, context: context)
            let ai = OllamaClient.shared.isAvailable
            if ai { BodyCoach.shared.review(record, context: context) }
            appModel.celebrate(.workoutComplete, title: "Check-in saved",
                               detail: ai ? "The AI coach is reviewing it now" : draft.date.formatted(date: .abbreviated, time: .omitted))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
