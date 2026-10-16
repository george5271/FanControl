import SwiftUI
import SMCKit

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            helperWarning
            readings
            modes
            if model.usesCurve {
                StepsEditor()
            }
            settings
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.magentaSoft)
            }
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(PanelBackground())
        .environment(\.colorScheme, .dark)
        .tint(Theme.magenta)
    }

    // MARK: - Sections

    private var connected: Bool { model.helperState == .connected }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: "fan.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: Theme.magenta.opacity(0.55), radius: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text("FanControl")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Охлаждение Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            PillBadge(text: connected ? "ОНЛАЙН" : "НЕТ СВЯЗИ",
                      dot: connected ? Theme.magenta : Color.white.opacity(0.4),
                      tint: connected ? Theme.magenta : .white)
                .help(connected ? "Помощник подключён" : "Помощник недоступен")
        }
    }

    @ViewBuilder
    private var helperWarning: some View {
        let text: String? = {
            switch model.helperState {
            case .connected, .unknown: return nil
            case .notInstalled: return "Помощник не установлен. Запустите scripts/install.sh — без него вентиляторами управлять нельзя."
            case .outdated(let v): return "Установлен помощник версии \(v). Переустановите: scripts/install.sh"
            case .failed(let message): return "Ошибка помощника: \(message)"
            }
        }()
        if let text {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.magenta)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.magenta.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.magenta.opacity(0.45)))
        }
    }

    private var readings: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                rowIcon("cpu")
                VStack(alignment: .leading, spacing: 1) {
                    Text("ЦП").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text("самое горячее ядро").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(model.cpuTemperature.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("°C")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.text)
            }
            ForEach(model.fans) { fan in
                Rectangle().fill(Theme.stroke).frame(height: 1)
                fanRow(fan)
            }
        }
        .card()
    }

    private func fanRow(_ fan: FanInfo) -> some View {
        let share = fan.maxRPM > 0 ? min(1, max(0, fan.actualRPM / fan.maxRPM)) : 0
        return HStack(spacing: 12) {
            rowIcon("fan")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Вентилятор \(fan.id + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(verbatim: "\(Int(fan.actualRPM.rounded()))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Theme.text)
                    + Text(" об/мин")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule().fill(Theme.accent)
                            .frame(width: max(share > 0 ? 4 : 0, geo.size.width * share))
                            .shadow(color: Theme.magenta.opacity(0.6), radius: 3)
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.6), value: share)
            }
        }
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Theme.magentaSoft)
            .frame(width: 32, height: 32)
            .background(Theme.magenta.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.magenta.opacity(0.25)))
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Режим")
            if model.settings.perFan {
                VStack(spacing: 8) {
                    ForEach(model.fans) { fan in
                        HStack(spacing: 10) {
                            Text("\(fan.id + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.magentaSoft)
                                .frame(width: 22, height: 22)
                                .background(Theme.magenta.opacity(0.12), in: Circle())
                                .overlay(Circle().strokeBorder(Theme.magenta.opacity(0.35)))
                                .help("Вентилятор \(fan.id + 1)")
                            modeBar(fan: fan.id, compact: true)
                        }
                    }
                }
            } else {
                modeBar(fan: nil, compact: false)
            }
            Text(modeDescription)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeBar(fan: Int?, compact: Bool) -> some View {
        ModeBar(selection: fan.map { model.mode(forFan: $0) } ?? model.settings.mode,
                compact: compact) { model.setMode($0, forFan: fan) }
    }

    private var modeDescription: String {
        let modes = Set(model.fans.map { model.mode(forFan: $0.id) })
        guard modes.count == 1, let mode = modes.first else { return "Режимы заданы для каждого вентилятора отдельно." }
        switch mode {
        case .max:
            let rpms = model.fans.map { "\(Int($0.maxRPM))" }.joined(separator: " / ")
            return "Вентиляторы на максимуме (\(rpms) об/мин)."
        case .off:
            return "Вентиляторы остановлены при любой температуре."
        case .curve:
            guard let i = model.activeStep, model.settings.steps.indices.contains(i) else {
                return "Обороты зависят от температуры ЦП по ступеням ниже."
            }
            let step = model.settings.steps[i]
            let power = step.percent == 0 ? "вентиляторы стоят" : "\(Int(step.percent)) %"
            return "Сейчас ступень «от \(Int(step.threshold)) °C»: \(power)."
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.magentaSoft)
                        .frame(width: 20)
                    Text("Настройки")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(showSettings ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(spacing: 12) {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                    settingRow("menubar.rectangle", "Температура и обороты в строке меню",
                               isOn: $model.settings.showInMenuBar)
                    settingRow("square.split.2x1", "Отдельный режим для каждого вентилятора",
                               isOn: $model.settings.perFan)
                    settingRow("power", "Запускать при входе в систему", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .card()
    }

    private func settingRow(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(MagentaToggleStyle())
    }

    private var footer: some View {
        HStack {
            Text(model.fans.isEmpty ? "Вентиляторы не найдены" : "Обновление каждые 2 с")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Text("Выйти")
                    Text("⌘Q").foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(GhostButtonStyle())
            .keyboardShortcut("q")
        }
    }
}

extension FanMode {
    var icon: String {
        switch self {
        case .max: return "wind"
        case .off: return "power"
        case .curve: return "thermometer.medium"
        }
    }
}

/// Pinterest-style tab bar: the selected mode sits on a magenta pill with a dot beneath its label.
struct ModeBar: View {
    let selection: FanMode
    let compact: Bool
    let onSelect: (FanMode) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FanMode.allCases) { mode in
                item(mode, selected: mode == selection)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: compact ? 13 : 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 13 : 18, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func item(_ mode: FanMode, selected: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { onSelect(mode) }
        } label: {
            Group {
                if compact {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon).font(.system(size: 11, weight: .semibold))
                        Text(mode.title).font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 16, weight: selected ? .semibold : .regular))
                            .frame(height: 18)
                        Text(mode.title).font(.system(size: 11, weight: .medium))
                        Circle().fill(.white).frame(width: 4, height: 4).opacity(selected ? 1 : 0)
                    }
                    .padding(.top, 9)
                    .padding(.bottom, 6)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                        .fill(Theme.accent)
                        .shadow(color: Theme.magenta.opacity(0.55), radius: 8, y: 2)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: "fan.fill")
        if model.settings.showInMenuBar, !model.menuBarTitle.isEmpty {
            Text(model.menuBarTitle)
        }
    }
}
