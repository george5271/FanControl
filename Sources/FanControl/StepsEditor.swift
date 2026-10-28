import SwiftUI

/// Editor for the temperature → fan power steps used by the "По темп." mode.
struct StepsEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) private var p

    private var steps: [Step] { model.settings.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepChart(steps: steps, temperature: model.cpuTemperature, activeStep: model.activeStep)
                .frame(height: 70)
                .padding(.bottom, 6)

            // Beyond seven steps the list scrolls instead of stretching the panel past the screen.
            if steps.count > Self.visibleRows {
                ScrollView(.vertical) { rows }
                    .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight)
            } else {
                rows
            }

            HStack(alignment: .top) {
                Text("% от максимальных оборотов, 0 % — стоп. Ступень понижается, когда температура упадёт на \(Int(StepCurve.hysteresis)) °C ниже порога.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { addStep() }
                } label: {
                    Label("Ступень", systemImage: "plus")
                }
                .buttonStyle(LinkButtonStyle())
                .disabled((steps.last?.threshold ?? 0) >= 110)
                .help("Добавить ступень")
            }
            .padding(.top, 4)
        }
    }

    private static let visibleRows = 7
    private static let rowHeight: CGFloat = 36

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                row(index: index, step: step)
            }
        }
    }

    private func row(index: Int, step: Step) -> some View {
        let active = model.activeStep == index
        return HStack(spacing: 8) {
            if index == 0 {
                Text("от 0 °C")
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(p.textSecondary)
                    .frame(width: 96)
            } else {
                PillStepper(value: binding(step.id, \.threshold), range: thresholdRange(index), step: 1,
                            label: "от \(Int(step.threshold))°")
                    .frame(width: 96)
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0 : 1)
            .help("Удалить ступень")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(active ? p.accent.opacity(p.isDark ? 0.18 : 0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    @Environment(\.palette) private var p

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
            let y = { (pct: Double) in size.height - CGFloat(pct / 100) * (size.height - 10) }
            let line = path(x: x, y: y)

            ZStack(alignment: .topLeading) {
                Path { $0.move(to: CGPoint(x: 0, y: size.height)); $0.addLine(to: CGPoint(x: size.width, y: size.height)) }
                    .stroke(p.hairline, lineWidth: 1)

                closed(line, size: size)
                    .fill(LinearGradient(colors: [p.accent.opacity(0.28), p.accent.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                line
                    .stroke(p.accent, style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

                if let temperature, let activeStep, steps.indices.contains(activeStep) {
                    let mx = x(temperature)
                    let my = y(steps[activeStep].percent)
                    Path { $0.move(to: CGPoint(x: mx, y: 12)); $0.addLine(to: CGPoint(x: mx, y: size.height)) }
                        .stroke(p.text.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    Circle()
                        .fill(p.isDark ? .white : p.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(p.slabTop, lineWidth: 2).padding(-2))
                        .position(x: mx, y: my)
                    Text("\(Int(temperature.rounded()))°")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(p.text)
                        .fixedSize()
                        .position(x: min(max(mx, 12), size.width - 12), y: 4)
                }
            }
        }
        .padding(.horizontal, 4)
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
