import SwiftUI
import SMCKit

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            helperWarning
            readings
            Divider()
            modes
            if model.usesCurve {
                Divider()
                StepsEditor()
            }
            Divider()
            DisclosureGroup("Настройки", isExpanded: $showSettings) {
                settings.padding(.top, 6)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("FanControl").font(.headline)
            Spacer()
            Circle()
                .fill(model.helperState == .connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .help(model.helperState == .connected ? "Помощник подключён" : "Помощник недоступен")
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
            Text(text)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(icon: "cpu", title: "ЦП (самое горячее ядро)",
                value: model.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "—")
            ForEach(model.fans) { fan in
                row(icon: "fan", title: "Вентилятор \(fan.id + 1)",
                    value: "\(Int(fan.actualRPM.rounded())) об/мин")
            }
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    @ViewBuilder
    private var modes: some View {
        if model.settings.perFan {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.fans) { fan in
                    HStack {
                        Text("Вент. \(fan.id + 1)").frame(width: 56, alignment: .leading)
                        modePicker(fan: fan.id)
                    }
                }
            }
        } else {
            modePicker(fan: nil)
        }
        Text(modeDescription).font(.caption).foregroundStyle(.secondary)
    }

    private func modePicker(fan: Int?) -> some View {
        Picker("", selection: Binding(
            get: { fan.map { model.mode(forFan: $0) } ?? model.settings.mode },
            set: { model.setMode($0, forFan: fan) }
        )) {
            ForEach(FanMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Температура и обороты в строке меню", isOn: $model.settings.showInMenuBar)
            Toggle("Отдельный режим для каждого вентилятора", isOn: $model.settings.perFan)
            Toggle("Запускать при входе в систему", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
        .toggleStyle(.checkbox)
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
