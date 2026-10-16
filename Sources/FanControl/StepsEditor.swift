import SwiftUI

/// Editor for the temperature → fan power steps used by the "По темп." mode.
struct StepsEditor: View {
    @EnvironmentObject var model: AppModel

    private var steps: [Step] { model.settings.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Ступени")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { addStep() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 22, height: 22)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: Theme.magenta.opacity(0.5), radius: 5)
                }
                .buttonStyle(.plain)
                .disabled((steps.last?.threshold ?? 0) >= 110)
                .help("Добавить ступень")
            }

            VStack(spacing: 6) {
                StepChart(steps: steps, temperature: model.cpuTemperature, activeStep: model.activeStep)
                    .frame(height: 74)
                    .padding(.bottom, 4)
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    row(index: index, step: step)
                }
            }
            .card(padding: 8)

            Text("% от максимальных оборотов (не ниже минимальных), 0 % — стоп. Вниз ступень переключается, когда температура опустится на \(Int(StepCurve.hysteresis)) °C ниже порога.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(index: Int, step: Step) -> some View {
        let active = model.activeStep == index
        return HStack(spacing: 8) {
            Circle()
                .fill(active ? Theme.magenta : Color.white.opacity(0.18))
                .frame(width: 6, height: 6)
                .shadow(color: active ? Theme.magenta : .clear, radius: 4)
            if index == 0 {
                Text("от 0 °C")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 94)
            } else {
                PillStepper(value: binding(step.id, \.threshold), range: thresholdRange(index), step: 1,
                            label: "от \(Int(step.threshold))°")
                    .frame(width: 94)
            }
            Spacer(minLength: 4)
            PillStepper(value: binding(step.id, \.percent), range: 0...100, step: 5,
                        label: step.percent == 0 ? "стоп" : "\(Int(step.percent)) %")
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.settings.steps.removeAll { $0.id == step.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0 : 1)
            .help("Удалить ступень")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(active ? Theme.magenta.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(active ? Theme.magenta.opacity(0.5) : Color.clear))
    }

    /// Thresholds stay strictly increasing: each one lies between its neighbours.
    private func thresholdRange(_ index: Int) -> ClosedRange<Double> {
        let lower = steps[index - 1].threshold + 1
        let upper = index + 1 < steps.count ? steps[index + 1].threshold - 1 : 110
        return lower...max(lower, upper)
    }

    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<Step, Double>) -> Binding<Double> {
        Binding(
            get: { model.settings.steps.first { $0.id == id }?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard let i = model.settings.steps.firstIndex(where: { $0.id == id }) else { return }
                model.settings.steps[i][keyPath: keyPath] = value
            }
        )
    }

    private func addStep() {
        let last = steps.last ?? Step(threshold: 0, percent: 0)
        model.settings.steps.append(Step(threshold: min(110, last.threshold + 5),
                                         percent: min(100, last.percent + 10)))
    }
}

/// Step graph of fan power over temperature, with a marker at the current CPU temperature.
private struct StepChart: View {
    let steps: [Step]
    let temperature: Double?
    let activeStep: Int?

    private let maxT = 110.0

    /// Start the axis a little before the first real threshold so the interesting part fills the width.
    private var minT: Double {
        var t = 30.0
        if steps.count > 1 { t = min(t, steps[1].threshold - 10) }
        if let temperature { t = min(t, temperature - 5) }
        return max(0, t)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let x = { (t: Double) in CGFloat((min(max(t, minT), maxT) - minT) / (maxT - minT)) * size.width }
            let y = { (p: Double) in size.height - CGFloat(p / 100) * (size.height - 8) }
            let line = path(x: x, y: y)

            ZStack(alignment: .topLeading) {
                // Grid: 50 % and 100 %.
                ForEach([50.0, 100.0], id: \.self) { p in
                    Path { $0.move(to: CGPoint(x: 0, y: y(p))); $0.addLine(to: CGPoint(x: size.width, y: y(p))) }
                        .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                closed(line, size: size)
                    .fill(LinearGradient(colors: [Theme.magenta.opacity(0.35), Theme.magenta.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                line
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.magenta.opacity(0.7), radius: 4)

                if let temperature, let activeStep, steps.indices.contains(activeStep) {
                    let mx = x(temperature)
                    let my = y(steps[activeStep].percent)
                    Path { $0.move(to: CGPoint(x: mx, y: 0)); $0.addLine(to: CGPoint(x: mx, y: size.height)) }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: Theme.magenta, radius: 5)
                        .position(x: mx, y: my)
                    Text("\(Int(temperature.rounded()))°")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.magenta.opacity(0.85), in: Capsule())
                        .fixedSize()
                        .position(x: min(max(mx, 16), size.width - 16), y: 6)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.4), value: temperature)
    }

    private func closed(_ line: Path, size: CGSize) -> Path {
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        return area
    }

    private func path(x: (Double) -> CGFloat, y: (Double) -> CGFloat) -> Path {
        Path { p in
            guard let first = steps.first else { return }
            p.move(to: CGPoint(x: x(minT), y: y(first.percent)))
            for step in steps.dropFirst() {
                p.addLine(to: CGPoint(x: x(step.threshold), y: p.currentPoint?.y ?? y(first.percent)))
                p.addLine(to: CGPoint(x: x(step.threshold), y: y(step.percent)))
            }
            p.addLine(to: CGPoint(x: x(maxT), y: y(steps.last?.percent ?? first.percent)))
        }
    }
}
