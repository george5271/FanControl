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
    @Published private(set) var activeStep: Int?
    @Published private(set) var helperState: HelperClient.State = .unknown
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published private(set) var lastError: String?

    private let smc: SMC?
    private let cpuKeys: [String]
    private let helper = HelperClient()
    private var timer: Timer?

    private init() {
        settings = AppSettings.load()
        smc = try? SMC()
        cpuKeys = smc?.cpuTemperatureKeys() ?? []

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

        if let t = cpuTemperature, usesCurve {
            activeStep = StepCurve.stepIndex(temperature: t, steps: settings.steps, current: activeStep)
        } else if !usesCurve {
            activeStep = nil
        }

        let targets = fans.map { fan -> Double in
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
        helper.apply(targets) { [weak self] state in
            self?.helperState = state
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
