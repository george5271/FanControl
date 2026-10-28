import AppKit
import SMCKit
import FanControlShared

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            tick()
        }
    }
    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var cpuTemperature: Double?
    /// Hottest GPU sensor and hottest battery sensor; nil where the Mac has none.
    @Published private(set) var gpuTemperature: Double?
    @Published private(set) var batteryTemperature: Double?
    @Published private(set) var activeStep: Int?
    @Published private(set) var helperState: HelperClient.State = .unknown
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published private(set) var lastError: String?
    /// Lid closed: fans are stopped whatever the mode (built in, not a setting).
    @Published private(set) var lidClosed = false
    /// Lid closed but the CPU got too hot to keep the fans stopped; the selected mode runs instead.
    @Published private(set) var lidOverheat = false

    /// Last 30 minutes of readings, oldest first, for the history chart.
    @Published private(set) var history: [Sample] = []
    /// Fans are stopped (or being stopped): drives the menu bar icon.
    @Published private(set) var fansStopped = false

    struct Sample {
        let time: Date
        let temperature: Double?
        /// Fastest fan, as a share of its maximum (0...1).
        let fanLoad: Double
        let rpm: Double
    }

    static let historySpan: TimeInterval = 30 * 60

    /// With the lid closed the fans restart at `lidOverheatOn` °C and stop again below `lidOverheatOff` °C.
    static let lidOverheatOn = 90.0
    static let lidOverheatOff = 80.0

    private let smc: SMC?
    private let cpuKeys: [String]
    private let gpuKeys: [String]
    private let batteryKeys: [String]
    private let helper = HelperClient()
    private var timer: Timer?

    private init() {
        settings = AppSettings.load()
        smc = try? SMC()
        cpuKeys = smc?.cpuTemperatureKeys() ?? []
        gpuKeys = smc?.gpuTemperatureKeys() ?? []
        batteryKeys = smc?.batteryTemperatureKeys() ?? []

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.tick() }
        }
        // After sleep the SMC may have dropped manual mode: re-apply immediately.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.tick() }
        }
    }

    // MARK: - Modes

    func mode(forFan fan: Int) -> FanMode {
        settings.perFan ? (settings.fanModes[fan] ?? settings.mode) : settings.mode
    }

    func setMode(_ mode: FanMode, forFan fan: Int?) {
        if let fan, settings.perFan {
            settings.fanModes[fan] = mode
        } else {
            settings.mode = mode
        }
    }

    var usesCurve: Bool {
        fans.indices.contains { mode(forFan: $0) == .curve } || (fans.isEmpty && settings.mode == .curve)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = "Автозапуск: \(error.localizedDescription)"
        }
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: - Control loop

    func tick() {
        guard let smc else {
            lastError = "Нет доступа к SMC"
            return
        }
        fans = smc.fans()
        cpuTemperature = smc.maxTemperature(of: cpuKeys)
        gpuTemperature = smc.maxTemperature(of: gpuKeys)
        batteryTemperature = smc.maxTemperature(of: batteryKeys)
        updateLid()
        record()

        if let t = cpuTemperature, usesCurve {
            activeStep = StepCurve.stepIndex(temperature: t, steps: settings.steps, current: activeStep)
        } else if !usesCurve {
            activeStep = nil
        }

        let lidStopsFans = lidClosed && !lidOverheat
        let targets = fans.map { fan -> Double in
            if lidStopsFans { return 0 }
            switch mode(forFan: fan.id) {
            case .max:
                return fan.maxRPM
            case .off:
                return 0
            case .curve:
                // No temperature reading: fail safe to full speed rather than guess.
                guard let step = activeStep, settings.steps.indices.contains(step) else { return fan.maxRPM }
                return StepCurve.rpm(percent: settings.steps[step].percent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
            }
        }
        guard !targets.isEmpty else { return }
        // Commanded to stop (only meaningful when the helper can actually do it), or already standing still.
        fansStopped = (helperState == .connected && targets.allSatisfy { $0 == 0 })
            || fans.allSatisfy { $0.actualRPM < 50 }
        helper.apply(targets) { [weak self] state in
            self?.helperState = state
        }
    }

    private func record() {
        let now = Date()
        // tick() also runs on settings changes and wake: keep roughly one sample per timer period.
        if let last = history.last, now.timeIntervalSince(last.time) < 1.5 { return }
        let fastest = fans.max { $0.actualRPM < $1.actualRPM }
        let load = fastest.map { $0.maxRPM > 0 ? min(1, $0.actualRPM / $0.maxRPM) : 0 } ?? 0
        history.append(Sample(time: now, temperature: cpuTemperature, fanLoad: load, rpm: fastest?.actualRPM ?? 0))
        let cutoff = now.addingTimeInterval(-Self.historySpan)
        if let firstKept = history.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            history.removeFirst(firstKept)
        }
    }

    #if DEBUG
    /// Snapshots only: a plausible half hour of load so the history chart has something to draw.
    func fillDemoHistory() {
        let now = Date()
        history = (0..<900).map { i in
            let t = Double(i) / 900
            let burst = t > 0.35 && t < 0.62 ? 18 * sin((t - 0.35) / 0.27 * .pi) : 0
            let temp = 52 + 6 * sin(t * 9) + burst + Double((i * 7919) % 13) / 6
            let load = min(1, max(0.25, (temp - 45) / 40))
            return Sample(time: now.addingTimeInterval(-Self.historySpan + Double(i) * 2),
                          temperature: temp, fanLoad: load, rpm: load * 6241)
        }
    }
    #endif

    private func updateLid() {
        lidClosed = Clamshell.isClosed
        guard lidClosed else {
            lidOverheat = false
            return
        }
        // No temperature reading: never keep the fans stopped blind.
        guard let t = cpuTemperature else {
            lidOverheat = true
            return
        }
        if t >= Self.lidOverheatOn {
            lidOverheat = true
        } else if t < Self.lidOverheatOff {
            lidOverheat = false
        }
    }

    /// Called on quit: give the fans back to macOS.
    func shutdown() {
        timer?.invalidate()
        helper.resetToAutoSync()
    }

    // MARK: - Menu bar text

    var menuBarTitle: String {
        var parts: [String] = []
        if let t = cpuTemperature { parts.append("\(Int(t.rounded()))°") }
        if let rpm = fans.map(\.actualRPM).max() { parts.append("\(Int(rpm.rounded()))") }
        return parts.joined(separator: " · ")
    }
}
