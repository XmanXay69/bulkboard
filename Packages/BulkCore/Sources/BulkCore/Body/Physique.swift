import Foundation

/// Tape-measure numbers for one check-in. Lengths are centimetres; anything can be skipped.
public struct BodyMeasurements: Codable, Hashable, Sendable {
    public var heightCm: Double
    public var weightKg: Double
    public var wingspanCm: Double?
    public var standingReachCm: Double?
    public var wristCm: Double?
    public var neckCm: Double?
    public var shouldersCm: Double?
    public var chestCm: Double?
    public var waistCm: Double?
    public var hipsCm: Double?
    public var armCm: Double?
    public var forearmCm: Double?
    public var thighCm: Double?
    public var calfCm: Double?
    public var bodyFatPercent: Double?
    /// Two-foot jump from standing, no step (jump height, not touch height).
    public var standingVerticalCm: Double?
    /// Highest point touched on a running jump.
    public var approachTouchCm: Double?
    public var canPalmBall: Bool?

    public init(heightCm: Double, weightKg: Double, wingspanCm: Double? = nil, standingReachCm: Double? = nil,
                wristCm: Double? = nil, neckCm: Double? = nil, shouldersCm: Double? = nil, chestCm: Double? = nil,
                waistCm: Double? = nil, hipsCm: Double? = nil, armCm: Double? = nil, forearmCm: Double? = nil,
                thighCm: Double? = nil, calfCm: Double? = nil, bodyFatPercent: Double? = nil,
                standingVerticalCm: Double? = nil, approachTouchCm: Double? = nil, canPalmBall: Bool? = nil) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.wingspanCm = wingspanCm
        self.standingReachCm = standingReachCm
        self.wristCm = wristCm
        self.neckCm = neckCm
        self.shouldersCm = shouldersCm
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipsCm = hipsCm
        self.armCm = armCm
        self.forearmCm = forearmCm
        self.thighCm = thighCm
        self.calfCm = calfCm
        self.bodyFatPercent = bodyFatPercent
        self.standingVerticalCm = standingVerticalCm
        self.approachTouchCm = approachTouchCm
        self.canPalmBall = canPalmBall
    }
}

/// Body parts that can be compared against proportion targets.
public enum BodyPart: String, Codable, CaseIterable, Sendable {
    case shoulders, chest, arms, forearms, neck, thighs, calves

    public var title: String { rawValue.capitalized }

    /// Muscle groups to train harder when this part lags.
    public var muscles: Set<MuscleGroup> {
        switch self {
        case .shoulders: [.shoulders, .back]
        case .chest: [.chest]
        case .arms: [.biceps, .triceps]
        case .forearms: [.biceps]
        case .neck: [.back]
        case .thighs: [.quads, .hamstrings, .glutes]
        case .calves: [.calves]
        }
    }

    /// Matches loose wording ("lats", "delts", "legs") from people or a model.
    public static func matching(_ text: String) -> BodyPart? {
        let word = text.lowercased()
        let table: [(String, BodyPart)] = [
            ("calf", .calves), ("calv", .calves), ("forearm", .forearms), ("grip", .forearms),
            ("delt", .shoulders), ("shoulder", .shoulders), ("lat", .shoulders), ("back", .shoulders), ("trap", .neck),
            ("neck", .neck), ("chest", .chest), ("pec", .chest), ("bicep", .arms), ("tricep", .arms), ("arm", .arms),
            ("quad", .thighs), ("hamstring", .thighs), ("glute", .thighs), ("thigh", .thighs), ("leg", .thighs),
        ]
        return table.first { word.contains($0.0) }?.1
    }
}

public struct PartScore: Hashable, Sendable, Identifiable {
    public var part: BodyPart
    public var actualCm: Double
    public var targetCm: Double

    public var id: BodyPart { part }
    /// Actual as a share of the proportion target (1.0 = on target).
    public var ratio: Double { targetCm > 0 ? actualCm / targetCm : 0 }
}

public struct PhysiqueReport: Sendable {
    /// Lowest ratio first.
    public var parts: [PartScore]
    public var lagging: [BodyPart]
    public var strengths: [BodyPart]
    /// Shoulder circumference ÷ waist. Classic target ≈ 1.6.
    public var vTaper: Double?
    public var waistTargetCm: Double?
    public var bodyFatPercent: Double?
    public var bodyFatIsEstimate: Bool
    public var ffmi: Double?
    public var ffmiBand: String?
    /// Lean mass to add to reach the next FFMI band.
    public var leanToNextBandKg: Double?
    /// True when the wrist wasn't measured and the frame was estimated from height.
    public var frameEstimated: Bool
    public var averageRatio: Double?
    public var notes: [String]

    public var focusMuscles: Set<MuscleGroup> { lagging.reduce(into: Set<MuscleGroup>()) { $0.formUnion($1.muscles) } }
}

/// Compares measurements to classic proportion targets.
///
/// Targets follow John McCallum's wrist-based system: ideal chest = 6.5 × wrist, and every other
/// part is a fixed share of that chest. The V-taper uses the golden ratio (shoulders ≈ 1.618 × waist).
/// These are aesthetic yardsticks, not health standards, and they're most useful for spotting
/// which part lags behind the rest of *you*.
public enum PhysiqueAnalyzer {
    public static let chestPerWrist = 6.5
    public static let shareOfChest: [BodyPart: Double] = [
        .arms: 0.36, .forearms: 0.29, .neck: 0.37, .thighs: 0.53, .calves: 0.34,
    ]
    public static let waistShareOfChest = 0.70
    public static let goldenRatio = 1.618

    /// Wrist estimate when it wasn't measured (≈ 9.4% of height for men, 8.8% for women).
    public static func estimatedWrist(heightCm: Double, sex: Sex) -> Double {
        heightCm * (sex == .male ? 0.094 : 0.088)
    }

    /// U.S. Navy circumference method.
    public static func navyBodyFat(sex: Sex, heightCm: Double, neckCm: Double, waistCm: Double, hipsCm: Double?) -> Double? {
        switch sex {
        case .male:
            guard waistCm > neckCm else { return nil }
            return 495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * log10(heightCm)) - 450
        case .female:
            guard let hipsCm, waistCm + hipsCm > neckCm else { return nil }
            return 495 / (1.29579 - 0.35004 * log10(waistCm + hipsCm - neckCm) + 0.22100 * log10(heightCm)) - 450
        }
    }

    /// Fat-free mass index, height-normalized to 1.8 m.
    public static func ffmi(weightKg: Double, heightCm: Double, bodyFatPercent: Double) -> Double {
        let meters = heightCm / 100
        let lean = weightKg * (1 - bodyFatPercent / 100)
        return lean / (meters * meters) + 6.1 * (1.8 - meters)
    }

    static let ffmiBands: [(upper: Double, name: String)] = [
        (18, "Below average"), (20, "Average"), (22, "Above average"), (23, "Excellent"), (25, "Near the natural ceiling"),
        (.infinity, "Beyond typical natural range"),
    ]

    public static func analyze(_ m: BodyMeasurements, sex: Sex) -> PhysiqueReport {
        let wrist = m.wristCm ?? estimatedWrist(heightCm: m.heightCm, sex: sex)
        let idealChest = chestPerWrist * wrist
        var parts: [PartScore] = []
        if let chest = m.chestCm { parts.append(PartScore(part: .chest, actualCm: chest, targetCm: idealChest)) }
        let measured: [(BodyPart, Double?)] = [(.arms, m.armCm), (.forearms, m.forearmCm), (.neck, m.neckCm), (.thighs, m.thighCm), (.calves, m.calfCm)]
        for (part, value) in measured {
            if let value { parts.append(PartScore(part: part, actualCm: value, targetCm: idealChest * shareOfChest[part]!)) }
        }
        var vTaper: Double?
        if let shoulders = m.shouldersCm, let waist = m.waistCm, waist > 0 {
            vTaper = shoulders / waist
            parts.append(PartScore(part: .shoulders, actualCm: shoulders, targetCm: goldenRatio * waist))
        }
        parts.sort { $0.ratio < $1.ratio }

        // Lagging = clearly behind your own average; strengths = clearly ahead.
        let average = parts.isEmpty ? nil : parts.map(\.ratio).reduce(0, +) / Double(parts.count)
        var lagging: [BodyPart] = []
        var strengths: [BodyPart] = []
        if let average, parts.count >= 2 {
            lagging = parts.filter { $0.ratio <= average - 0.04 }.map(\.part)
            if lagging.isEmpty, let lowest = parts.first, lowest.ratio < 0.97 { lagging = [lowest.part] }
            lagging = Array(lagging.prefix(3))
            strengths = parts.filter { $0.ratio >= average + 0.04 }.map(\.part).reversed()
        }

        var bodyFat = m.bodyFatPercent
        var bodyFatIsEstimate = false
        if bodyFat == nil, let neck = m.neckCm, let waist = m.waistCm {
            bodyFat = navyBodyFat(sex: sex, heightCm: m.heightCm, neckCm: neck, waistCm: waist, hipsCm: m.hipsCm)
            bodyFatIsEstimate = bodyFat != nil
        }
        var ffmiValue: Double?
        var band: String?
        var leanToNext: Double?
        if let bodyFat, bodyFat > 2, bodyFat < 60 {
            let value = ffmi(weightKg: m.weightKg, heightCm: m.heightCm, bodyFatPercent: bodyFat)
            ffmiValue = value
            band = ffmiBands.first { value < $0.upper }?.name
            if let next = ffmiBands.first(where: { value < $0.upper && $0.upper.isFinite && $0.upper <= 25 })?.upper {
                let meters = m.heightCm / 100
                leanToNext = (next - value) * meters * meters
            }
        }

        let waistTarget = idealChest * waistShareOfChest
        var notes: [String] = []
        if let weakest = parts.first, !lagging.isEmpty {
            notes.append("\(weakest.part.title) are your biggest gap at \(Fmt.int(weakest.ratio * 100))% of the proportion target.")
        }
        if let vTaper, vTaper < 1.5 {
            notes.append("V-taper is \(Fmt.number(vTaper, maxDecimals: 2)) (classic target 1.6). Wider lats and side delts move this most.")
        }
        if let average, average < 0.9 {
            notes.append("Overall you're at \(Fmt.int(average * 100))% of the proportion targets, so total size is still the main job. Keep the surplus.")
        }
        if let waist = m.waistCm, waist > waistTarget * 1.08 {
            notes.append("Waist is above its proportion target; a slower gain rate keeps the taper.")
        }
        if m.wristCm == nil {
            notes.append("Add your wrist measurement for targets scaled to your frame (they're estimated from height for now).")
        }

        return PhysiqueReport(parts: parts, lagging: lagging, strengths: strengths, vTaper: vTaper, waistTargetCm: waistTarget,
                              bodyFatPercent: bodyFat, bodyFatIsEstimate: bodyFatIsEstimate, ffmi: ffmiValue, ffmiBand: band,
                              leanToNextBandKg: leanToNext, frameEstimated: m.wristCm == nil, averageRatio: average, notes: notes)
    }
}
