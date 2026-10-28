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

/// Colour theme of the panel. `system` follows macOS: light by day, deep blue in dark mode.
enum ThemeChoice: String, Codable, CaseIterable, Identifiable {
    case system, ocean, violet, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Авто"
        case .ocean: return "Синяя"
        case .violet: return "Фиолет."
        case .light: return "Светлая"
        }
    }
}

/// Ready-made step sets for the "По темп." mode.
enum StepPreset: String, CaseIterable, Identifiable {
    case quiet, balanced, performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: return "Тихо"
        case .balanced: return "Баланс"
        case .performance: return "Производительность"
        }
    }

    /// (threshold °C, % of max RPM)
    private var table: [(Double, Double)] {
        switch self {
        case .quiet: return [(0, 0), (65, 25), (75, 40), (85, 65), (95, 100)]
        case .balanced: return [(0, 25), (60, 40), (70, 60), (80, 80), (90, 100)]
        case .performance: return [(0, 40), (50, 55), (60, 70), (70, 85), (80, 100)]
        }
    }

    var steps: [Step] { table.map { Step(threshold: $0.0, percent: $0.1) } }

    /// The preset these steps are an unedited copy of, if any.
    static func matching(_ steps: [Step]) -> StepPreset? {
        allCases.first { preset in
            preset.table.count == steps.count
                && zip(preset.table, steps).allSatisfy { $0.0 == $1.threshold && $0.1 == $1.percent }
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
    var theme: ThemeChoice = .system

    static let defaultSteps = StepPreset.balanced.steps

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
        theme = (try? c.decode(ThemeChoice.self, forKey: .theme)) ?? d.theme
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
