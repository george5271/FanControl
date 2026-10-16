import SwiftUI

/// Editor for the temperature → fan power steps used by the "По темп." mode.
struct StepsEditor: View {
    @EnvironmentObject var model: AppModel

    private var steps: [Step] { model.settings.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ступени").font(.subheadline.bold())
                Spacer()
                Button {
                    addStep()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled((steps.last?.threshold ?? 0) >= 110)
                .help("Добавить ступень")
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.activeStep == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                    if index == 0 {
                        Text("от 0 °C").frame(width: 92, alignment: .leading)
                    } else {
                        Stepper(value: binding(step.id, \.threshold), in: thresholdRange(index), step: 1) {
                            Text("от \(Int(step.threshold)) °C").monospacedDigit()
                        }
                        .frame(width: 92, alignment: .leading)
                    }
                    Spacer()
                    Stepper(value: binding(step.id, \.percent), in: 0...100, step: 5) {
                        Text(step.percent == 0 ? "стоп" : "\(Int(step.percent)) %").monospacedDigit()
                    }
                    Button {
                        model.settings.steps.removeAll { $0.id == step.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0 : 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(model.activeStep == index ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
            }
            Text("% от максимальных оборотов (не ниже минимальных), 0 % — стоп. Вниз ступень переключается, когда температура опустится на \(Int(StepCurve.hysteresis)) °C ниже порога.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
