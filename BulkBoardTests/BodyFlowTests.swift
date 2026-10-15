import AppKit
import BulkCore
import Foundation
import ImageIO
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Body check-ins, focus and dunk")
@MainActor
struct BodyFlowTests {
    let sample = BodyMeasurements(heightCm: 188, weightKg: 84, wingspanCm: 195.6, wristCm: 18, neckCm: 39, shouldersCm: 122,
                                  chestCm: 108, waistCm: 82, armCm: 39, forearmCm: 31, thighCm: 60, calfCm: 33,
                                  standingVerticalCm: 58)

    @Test func savingACheckInStoresMeasurementsAndWeight() throws {
        let context = try makeContext()
        onboard(context)
        let weighIns = context.fetchAll(WeightRecord.self).count
        let record = try BodyActions.saveCheckIn(sample, date: .now, photo: nil, logWeight: true, context: context)
        #expect(record.measurements == sample)
        #expect(context.latestCheckIn === record)
        #expect(context.fetchAll(WeightRecord.self).count == weighIns + 1)
        let report = try #require(BodyActions.report(for: record, sex: .male))
        #expect(report.lagging.first == .calves)
    }

    @Test func photosAreDownscaledAndStripped() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bulkboard-photos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 2000, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let filename = try PhotoStore.save(png, in: folder)
        #expect(filename.hasSuffix(".jpg"))
        let data = try #require(PhotoStore.jpegData(filename, in: folder))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        #expect((props[kCGImagePropertyPixelWidth] as? Int ?? 0) <= 1600)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        PhotoStore.delete(filename, in: folder)
        #expect(PhotoStore.jpegData(filename, in: folder) == nil)
        #expect(throws: PhotoError.self) { try PhotoStore.save(Data("not an image".utf8), in: folder) }
    }

    @Test func applyingFocusRebuildsThePlanAndBumpsProtein() throws {
        let context = try makeContext()
        let profile = onboard(context)
        BodyActions.applyFocus([.calves, .biceps], raiseProtein: true, profile: profile, context: context)
        #expect(profile.focusMuscles == [.calves, .biceps])
        #expect(profile.macroSettings.proteinPerLb == 1.0)
        let plan = try #require(context.workoutPlan)
        #expect(plan.days.flatMap(\.exercises).contains { $0.note == "Focus" })

        BodyActions.applyFocus([], raiseProtein: false, profile: profile, context: context)
        #expect(!(context.workoutPlan?.days.flatMap(\.exercises).contains { $0.note == "Focus" } ?? true))
    }

    @Test func dunkProgramAddsJumpsAndCapsTheRate() throws {
        let context = try makeContext()
        let profile = onboard(context)
        BodyActions.setDunkGoal(true, leanGain: true, profile: profile, context: context)
        #expect(profile.dunkGoal)
        #expect(abs(Units.lb(fromKg: profile.weeklyRateOverrideKg ?? 0) - 0.5) < 1e-9)
        let depth = SeedLibrary.exerciseID("depth_jump")
        #expect(context.workoutPlan?.days.flatMap(\.exercises).contains { $0.exerciseID == depth } == true)
        #expect(context.fetchAll(ExerciseRecord.self).contains { $0.id == depth }, "Seeded so the plan can show its name")
    }

    @Test func dunkInputsPreferTheLatestWeighIn() throws {
        let context = try makeContext()
        let profile = onboard(context)
        let record = try BodyActions.saveCheckIn(sample, date: .now.adding(days: -10), photo: nil, logWeight: false, context: context)
        context.insert(WeightRecord(date: .now, weightKg: 86))
        let inputs = BodyActions.dunkInputs(profile: profile, checkIn: record, latestWeightKg: context.latestWeightKg)
        #expect(inputs.weightKg == 86)
        #expect(inputs.wingspanCm == 195.6)
        #expect(inputs.goalWeightKg == profile.goalWeightKg)
    }

    @Test func backupsCarryCheckInsAndFocus() throws {
        let context = try makeContext()
        let profile = onboard(context)
        try BodyActions.saveCheckIn(sample, date: .now, photo: nil, logWeight: false, context: context)
        BodyActions.applyFocus([.shoulders], raiseProtein: false, profile: profile, context: context)
        profile.dunkGoal = true

        let restored = try makeContext()
        BackupService.restore(try BackupService.decode(BackupService.encode(BackupService.snapshot(context))), into: restored)
        #expect(restored.fetchAll(BodyCheckInRecord.self).first?.measurements == sample)
        #expect(restored.profile?.focusMuscles == [.shoulders])
        #expect(restored.profile?.dunkGoal == true)
    }

    @Test func demoIncludesCheckInsAndWipesThem() throws {
        let context = try makeContext()
        SeedService.ensureBuiltIns(context)
        DemoData.load(into: context)
        let checkIns = context.fetchAll(BodyCheckInRecord.self)
        #expect(checkIns.count == 2)
        let latest = try #require(context.latestCheckIn)
        let report = DunkCalculator.report(BodyActions.dunkInputs(profile: context.profile!, checkIn: latest, latestWeightKg: context.latestWeightKg))
        #expect(report.verdict == .close)
        DemoData.wipe(context)
        #expect(context.fetchAll(BodyCheckInRecord.self).isEmpty)
    }
}
