import SwiftUI
import SMCKit
import FanControlShared

/// Forces panel state for debug snapshots; nil in normal use.
struct PanelOverrides {
    var theme: ThemeChoice?
    var settingsOpen = false
    var infoOpen = false
    var stepsOpen = false
}

private struct PanelOverridesKey: EnvironmentKey {
    static let defaultValue: PanelOverrides? = nil
}

extension EnvironmentValues {
    var panelOverrides: PanelOverrides? {
        get { self[PanelOverridesKey.self] }
        set { self[PanelOverridesKey.self] = newValue }
    }
}

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.panelOverrides) private var overrides

    var body: some View {
        let choice = overrides?.theme ?? model.settings.theme
        let palette = choice.palette(system: systemScheme)
        PanelContent(initialSettings: overrides?.settingsOpen ?? false,
                     initialInfo: overrides?.infoOpen ?? false,
                     initialSteps: overrides?.stepsOpen ?? false)
            .environment(\.palette, palette)
            .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }
}

private struct PanelContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    @State private var showSettings: Bool
    @State private var showInfo: Bool
    @State private var showSteps: Bool
    /// Fan whose mode the bottom row edits when each fan has its own mode.
    @State private var selectedFan = 0

    init(initialSettings: Bool, initialInfo: Bool, initialSteps: Bool) {
        _showSettings = State(initialValue: initialSettings)
        _showInfo = State(initialValue: initialInfo)
        _showSteps = State(initialValue: initialSteps)
    }

    @Environment(\.panelSizeDidChange) private var panelSizeDidChange
    @Environment(\.panelChrome) private var chrome

    var body: some View {
        panel
            .frame(width: 372)
            .fixedSize(horizontal: false, vertical: true)  // ideal height, whatever the window is now
            .background(SlabBackground())
            .modifier(Chrome(chrome: chrome))
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { panelSizeDidChange?(geo.size) }
                    .onChange(of: geo.size) { panelSizeDidChange?($0) }
            })
            // The panel window is taller than the content: keep the content at its top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(chrome == nil ? SlabBackground() : nil)
            .background(quitShortcut)
            .ignoresSafeArea()
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .debugToggleSettings)) { _ in toggleSettings() }
            #endif
    }

    private var panel: some View {
        VStack(spacing: 14) {
            VStack(spacing: -27) {
                hero
                fans
            }
            notice
            // One slot: the outgoing and incoming cards cross-fade in place instead of stacking.
            ZStack(alignment: .top) {
                if showSettings {
                    SettingsCard(close: { toggleSettings() })
                        .transition(.opacity)
                } else if showInfo {
                    InfoCard(close: { toggleInfo() })
                        .transition(.opacity)
                } else {
                    modeCard
                        .transition(.opacity)
                }
            }
            // The slot's frame animates between the two heights. Masking to it keeps a taller outgoing
            // card (or a collapsing steps editor) from drawing over the buttons while it fades out;
            // the extra margins leave room for the card shadow.
            .mask(alignment: .top) {
                Rectangle()
                    .padding(.horizontal, -30)
                    .padding(.top, -30)
                    .padding(.bottom, -12)
            }
            actions
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var connected: Bool { model.helperState == .connected }
    private var perFan: Bool { model.settings.perFan && !model.fans.isEmpty }
    private var editedFan: Int? { perFan ? min(selectedFan, model.fans.count - 1) : nil }
    private var editedMode: FanMode { editedFan.map { model.mode(forFan: $0) } ?? model.settings.mode }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.heroBottom)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.92), in: Circle())
                Text("FanControl")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(.white)
                Spacer()
                statusButton
            }

            Text("ТЕМПЕРАТУРА ЦП")
                .font(.system(size: 11.5))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.28)))
                .padding(.top, 10)

            ZStack {
                Text(model.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "— °C")
                    .font(Typo.figure)
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)  // "100 °C" shrinks instead of running into the side readings
                    .padding(.horizontal, 60)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: model.cpuTemperature.map { Int($0.rounded()) })
                HStack {
                    sideReading("GPU", model.gpuTemperature)
                    Spacer()
                    sideReading("Батарея", model.batteryTemperature)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, model.fans.isEmpty ? 22 : 44)
        .frame(maxWidth: .infinity)
        .background(HeroBackground())
    }

    /// Smaller reading beside the CPU figure; nothing when the Mac has no such sensor.
    @ViewBuilder
    private func sideReading(_ title: String, _ value: Double?) -> some View {
        if let value {
            VStack(spacing: 2) {
                Text("\(Int(value.rounded()))°")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.35), value: Int(value.rounded()))
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 58)
            .help("\(title): \(Int(value.rounded())) °C")
        } else {
            Color.clear.frame(width: 58, height: 1)
        }
    }

    private var statusButton: some View {
        let problem = !(connected || model.helperState == .unknown)
        return Button { toggleInfo() } label: {
            Image(systemName: showInfo ? "xmark" : (problem ? "exclamationmark" : "info"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(problem ? p.warning : Color.white.opacity(showInfo ? 0.3 : 0.16), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(showInfo ? "Закрыть" : "О приложении и состоянии помощника")
    }

    // MARK: - Fans

    @ViewBuilder
    private var fans: some View {
        if !model.fans.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                ForEach(model.fans) { fan in
                    fanAvatar(fan)
                }
            }
        }
    }

    private func fanAvatar(_ fan: FanInfo) -> some View {
        let tone = Pastel.tone(fan.id)
        let selected = perFan && editedFan == fan.id
        let disk = Image(systemName: "fan")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(tone.ink)
            .frame(width: 54, height: 54)
            .background(
                Circle().fill(LinearGradient(colors: [tone.fill.opacity(0.85), tone.fill],
                                             startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(p.slabTop, lineWidth: 3))
            .overlay(Circle().inset(by: -3).strokeBorder(selected ? p.accent : .clear, lineWidth: 2))
            .shadow(color: .black.opacity(p.isDark ? 0.3 : 0.1), radius: 6, y: 4)

        return VStack(spacing: 5) {
            if perFan {
                Button { withAnimation(.easeOut(duration: 0.2)) { selectedFan = fan.id } } label: { disk }
                    .buttonStyle(.plain)
                    .help("Режим вентилятора \(fan.id + 1)")
            } else {
                disk
            }
            Text(verbatim: "\(Int(fan.actualRPM.rounded()))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(p.text)
            Text("об/мин · \(fan.id + 1)")
                .font(.system(size: 10.5))
                .foregroundStyle(p.textSecondary)
        }
        .frame(minWidth: 64)
    }

    // MARK: - Helper problems

    @ViewBuilder
    private var notice: some View {
        let text: String? = {
            switch model.helperState {
            case .connected, .unknown: return model.lastError
            case .notInstalled: return "Помощник не установлен. Запустите scripts/install.sh — без него вентиляторами управлять нельзя."
            case .outdated(let v): return "Установлен помощник версии \(v). Переустановите: scripts/install.sh"
            case .failed(let message): return "Помощник не отвечает: \(message)"
            }
        }()
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.warning)
                Text(text)
                    .font(Typo.caption)
                    .foregroundStyle(p.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Mode card

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(perFan ? "Вентилятор \((editedFan ?? 0) + 1) сейчас" : "Сейчас")
                    .font(Typo.caption)
                    .foregroundStyle(p.textSecondary)
                Spacer()
                if editedMode == .curve {
                    Button(showSteps ? "Свернуть" : "Настроить") {
                        withAnimation(Motion.panel) { showSteps.toggle() }
                    }
                    .buttonStyle(LinkButtonStyle())
                }
            }

            HStack(spacing: 12) {
                Image(systemName: summary.icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(p.isDark ? p.heroBottom : p.text)
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(RadialGradient(colors: [.white, Color(hex: 0xD9DBE3)],
                                                     center: UnitPoint(x: 0.35, y: 0.25),
                                                     startRadius: 2, endRadius: 34))
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(Typo.title)
                        .foregroundStyle(p.text)
                    Text(summary.detail)
                        .font(Typo.caption)
                        .foregroundStyle(p.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(summary.value)
                    .font(.system(size: 21, weight: .semibold).monospacedDigit())
                    .foregroundStyle(p.text)
            }

            if editedMode == .curve {
                PresetPicker()
            }

            if editedMode == .curve && showSteps {
                Rectangle().fill(p.hairline).frame(height: 1)
                StepsEditor()
                    .transition(.opacity)
            }
        }
        .glassCard()
    }

    private var summary: (icon: String, title: String, detail: String, value: String) {
        if model.lidClosed && !model.lidOverheat {
            return ("laptopcomputer", "Крышка закрыта", "вентиляторы остановлены", "0 %")
        }
        var mode = modeSummary
        if model.lidClosed {
            mode.detail = "крышка закрыта, но ЦП горячий"
        }
        return mode
    }

    private var modeSummary: (icon: String, title: String, detail: String, value: String) {
        let fans = editedFan.map { [$0] } ?? model.fans.map(\.id)
        switch editedMode {
        case .max:
            let rpms = model.fans.filter { fans.contains($0.id) }.map { "\(Int($0.maxRPM))" }
            return ("wind", "Максимум",
                    rpms.isEmpty ? "полные обороты" : rpms.joined(separator: " / ") + " об/мин", "100 %")
        case .off:
            return ("power", "Выключены", "без защиты от перегрева", "0 %")
        case .curve:
            let steps = model.settings.steps
            guard let i = model.activeStep, steps.indices.contains(i) else {
                return ("thermometer.medium", "По температуре", "ждём показаний датчика", "—")
            }
            let step = steps[i]
            return ("thermometer.medium", "от \(Int(step.threshold)) °C",
                    "ступень \(i + 1) из \(steps.count)",
                    step.percent == 0 ? "стоп" : "\(Int(step.percent)) %")
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button { toggleSettings() } label: {
                Image(systemName: showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 17, weight: .light))
            }
            .buttonStyle(GlossyButtonStyle(form: .circle))
            .help(showSettings ? "Закрыть настройки" : "Настройки")

            Button { select(.off) } label: {
                Image(systemName: "power").font(.system(size: 17, weight: .light))
            }
            .buttonStyle(GlossyButtonStyle(form: .circle, prominent: editedMode == .off))
            .help("Выкл: вентиляторы остановлены при любой температуре")

            Button { select(.max) } label: {
                HStack(spacing: 6) {
                    Text("Максимум")
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .regular))
                }
            }
            .buttonStyle(GlossyButtonStyle(form: .capsule, prominent: editedMode == .max))

            Button { select(.curve) } label: {
                HStack(spacing: 6) {
                    Text("По темп.")
                    Image(systemName: "thermometer.medium").font(.system(size: 13, weight: .regular))
                }
            }
            .buttonStyle(GlossyButtonStyle(form: .capsule, prominent: editedMode == .curve))
        }
        .padding(.horizontal, 4)
    }

    private func select(_ mode: FanMode) {
        withAnimation(Motion.panel) {
            model.setMode(mode, forFan: editedFan)
            showSettings = false
            showInfo = false
        }
    }

    private func toggleSettings() {
        withAnimation(Motion.panel) {
            showSettings.toggle()
            showInfo = false
        }
    }

    private func toggleInfo() {
        withAnimation(Motion.panel) {
            showInfo.toggle()
            showSettings = false
        }
    }

    /// ⌘Q works whichever card is showing.
    private var quitShortcut: some View {
        Button("") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Settings

private struct SettingsCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Настройки")
                    .font(Typo.title)
                    .foregroundStyle(p.text)
                Spacer()
                Button("Готово", action: close).buttonStyle(LinkButtonStyle())
            }

            VStack(spacing: 12) {
                row("Температура и обороты в строке меню", isOn: $model.settings.showInMenuBar)
                row("Отдельный режим для каждого вентилятора", isOn: $model.settings.perFan)
                row("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Rectangle().fill(p.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Оформление")
                    .font(Typo.caption)
                    .foregroundStyle(p.textSecondary)
                HStack(spacing: 0) {
                    ForEach(ThemeChoice.allCases) { choice in
                        swatch(choice).frame(maxWidth: .infinity)
                    }
                }
            }

            Rectangle().fill(p.hairline).frame(height: 1)

            Button { NSApp.terminate(nil) } label: {
                HStack {
                    Text("Выйти из FanControl")
                    Spacer()
                    Text("⌘Q").foregroundStyle(p.textSecondary)
                }
                .font(Typo.body)
                .foregroundStyle(p.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Typo.body)
                .foregroundStyle(p.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(ThemedSwitchStyle())
    }

    private func swatch(_ choice: ThemeChoice) -> some View {
        let selected = model.settings.theme == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { model.settings.theme = choice }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch choice {
                    case .system:
                        Circle().fill(Palette.light.heroBottom)
                            .overlay(
                                Circle().fill(Palette.ocean.slabTop)
                                    .mask(Rectangle().frame(width: 18).offset(x: 9))
                            )
                    case .light:
                        Circle().fill(Palette.light.slabTop)
                            .overlay(Circle().fill(Palette.light.heroBottom).padding(9))
                    default:
                        let s = choice.palette(system: .dark)
                        Circle().fill(LinearGradient(colors: [s.heroTop, s.heroBottom],
                                                     startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(p.isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? p.accent : .clear, lineWidth: 2))
                Text(choice.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? p.text : p.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(choice == .system ? "Как в системе: светлая днём, синяя в тёмном режиме" : choice.title)
    }
}

// MARK: - Info

private struct InfoCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("О FanControl")
                    .font(Typo.title)
                    .foregroundStyle(p.text)
                Spacer()
                Button("Готово", action: close).buttonStyle(LinkButtonStyle())
            }

            VStack(spacing: 10) {
                row("Помощник", helper.text, tint: helper.ok ? nil : p.warning)
                row("Версия", appVersion)
                row("Датчик", "самое горячее ядро ЦП")
                row("Вентиляторы", fans)
                row("Обновление", "каждые 2 с")
            }

            Rectangle().fill(p.hairline).frame(height: 1)

            Text("При закрытой крышке вентиляторы останавливаются, пока ЦП не нагреется до \(Int(AppModel.lidOverheatOn)) °C. При выходе из приложения они возвращаются под управление macOS.")
                .font(Typo.caption)
                .foregroundStyle(p.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(Typo.body)
                .foregroundStyle(p.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(Typo.bodyMedium)
                .foregroundStyle(tint ?? p.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var helper: (text: String, ok: Bool) {
        switch model.helperState {
        case .connected: return ("подключён", true)
        case .unknown: return ("подключение…", true)
        case .notInstalled: return ("не установлен", false)
        case .outdated(let v): return ("версия \(v), нужна \(HelperConstants.version)", false)
        case .failed: return ("не отвечает", false)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "отладочная сборка"
    }

    private var fans: String {
        guard !model.fans.isEmpty else { return "не найдены" }
        let max = model.fans.map { "\(Int($0.maxRPM))" }.joined(separator: " / ")
        return "\(model.fans.count), макс. \(max) об/мин"
    }
}

// MARK: - Presets

/// Тихо / Баланс / Производительность, plus "Свои" once the steps have been edited by hand.
private struct PresetPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    var body: some View {
        let current = StepPreset.matching(model.settings.steps)
        FillRow(spacing: 2) {
            ForEach(StepPreset.allCases) { preset in
                Button {
                    withAnimation(Motion.panel) { model.settings.steps = preset.steps }
                } label: {
                    chip(preset.title, selected: preset == current)
                }
                .buttonStyle(.plain)
                .help("Ступени «\(preset.title)»")
            }
            if current == nil {
                chip("Свои", selected: true)
                    .help("Ступени изменены вручную")
            }
        }
        .padding(3)
        .background(p.text.opacity(p.isDark ? 0.07 : 0.05), in: Capsule())
    }

    private func chip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : p.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    Capsule().fill(p.accent)
                        .shadow(color: p.accent.opacity(0.35), radius: 4, y: 2)
                }
            }
            .contentShape(Capsule())
    }
}

#if DEBUG
extension Notification.Name {
    /// `--anim-test` flips the settings card to time the window animation.
    static let debugToggleSettings = Notification.Name("FanControl.debugToggleSettings")
}
#endif

/// The borderless panel's rounded slab, hairline edge and shadow, drawn around the content so they
/// animate with it. Nothing in a debug snapshot.
private struct Chrome: ViewModifier {
    let chrome: PanelChrome?
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        if let chrome {
            let shape = RoundedRectangle(cornerRadius: chrome.cornerRadius, style: .continuous)
            content
                .clipShape(shape)
                .overlay(shape.strokeBorder(p.isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                            lineWidth: 1))
                .background(shape.fill(p.slabBottom)
                    .shadow(color: .black.opacity(p.isDark ? 0.45 : 0.18), radius: 16, y: 10))
                .padding(chrome.margins)
        } else {
            content
        }
    }
}
