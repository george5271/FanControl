import Foundation

enum FanMode: String, Codable, CaseIterable, Identifiable {
    case max, off, curve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .max: return "Максимум"
        case .off: return "Выкл"
        case .curve: return "По темп."
        }
    }
}

/// "From `threshold` °C run the fans at `percent` % of their maximum speed".
struct Step: Codable, Identifiable, Equatable {
    var id = UUID()
    var threshold: Double
    var percent: Double
}

struct AppSettings: Codable, Equatable {
    var mode: FanMode = .curve
    var perFan = false
    var fanModes: [Int: FanMode] = [:]
    var steps: [Step] = AppSettings.defaultSteps
    // Off by default: on notched MacBooks a wide menu bar item easily ends up hidden behind the notch.
    var showInMenuBar = false

    static let defaultSteps = [
        Step(threshold: 0, percent: 25),
        Step(threshold: 60, percent: 40),
        Step(threshold: 70, percent: 60),
        Step(threshold: 80, percent: 80),
        Step(threshold: 90, percent: 100),
    ]

    init() {}

    /// Field-by-field so a missing or malformed field falls back to its default
    /// instead of discarding all saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        mode = (try? c.decode(FanMode.self, forKey: .mode)) ?? d.mode
        perFan = (try? c.decode(Bool.self, forKey: .perFan)) ?? d.perFan
        fanModes = (try? c.decode([Int: FanMode].self, forKey: .fanModes)) ?? d.fanModes
        steps = (try? c.decode([Step].self, forKey: .steps)) ?? d.steps
        showInMenuBar = (try? c.decode(Bool.self, forKey: .showInMenuBar)) ?? d.showInMenuBar
    }

    private static let defaultsKey = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        if settings.steps.isEmpty { settings.steps = defaultSteps }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

enum StepCurve {
    /// Degrees the temperature must fall below a step's threshold before dropping to a lower step,
    /// so the fans don't flap when the temperature hovers around a boundary.
    static let hysteresis = 3.0

    static func stepIndex(temperature: Double, steps: [Step], current: Int?) -> Int {
        let raw = steps.lastIndex { $0.threshold <= temperature } ?? 0
        if let current, current < steps.count, raw < current,
           temperature > steps[current].threshold - hysteresis {
            return current
        }
        return raw
    }

    /// 0 % stops the fan; otherwise a share of the maximum speed, never below the fan's minimum.
    static func rpm(percent: Double, minRPM: Double, maxRPM: Double) -> Double {
        guard percent > 0 else { return 0 }
        return Swift.max(minRPM, maxRPM * Swift.min(percent, 100) / 100)
    }
}
