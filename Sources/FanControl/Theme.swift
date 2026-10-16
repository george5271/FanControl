import SwiftUI

/// Magenta / black / white palette and the small building blocks every view shares.
enum Theme {
    static let magenta = Color(red: 1.00, green: 0.17, blue: 0.60)       // #FF2B99
    static let magentaDeep = Color(red: 0.76, green: 0.05, blue: 0.44)   // #C20D70
    static let magentaSoft = Color(red: 1.00, green: 0.55, blue: 0.80)   // text on dark
    static let ink = Color(red: 0.055, green: 0.020, blue: 0.040)        // near-black
    static let wine = Color(red: 0.165, green: 0.035, blue: 0.105)

    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
    static let surface = Color.white.opacity(0.045)
    static let surfaceHover = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.08)

    static let accent = LinearGradient(colors: [magenta, magentaDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

    static let nsInk = NSColor(red: 0.055, green: 0.020, blue: 0.040, alpha: 1)
}

/// Black-to-wine panel with a magenta glow coming from the corners.
struct PanelBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink, Theme.wine], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.magenta.opacity(0.30), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 340)
            RadialGradient(colors: [Theme.magenta.opacity(0.12), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 260)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Translucent rounded card used for every section of the panel.
    func card(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }

    /// Repeats the action while the button is held, where the OS supports it (macOS 14+).
    @ViewBuilder
    func repeatsWhenHeld() -> some View {
        if #available(macOS 14.0, *) {
            self.buttonRepeatBehavior(.enabled)
        } else {
            self
        }
    }
}

/// Small uppercase caption above a section.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// Outlined capsule with an optional glowing dot, like "CREATOR" / "In Progress".
struct PillBadge: View {
    let text: String
    var dot: Color? = nil
    var tint: Color = Theme.magenta

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
                    .shadow(color: dot.opacity(0.9), radius: 4)
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(Theme.text.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.55)))
    }
}

/// Capsule switch with a magenta knob.
struct MagentaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Theme.magenta.opacity(0.28) : Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(configuration.isOn ? Theme.magenta.opacity(0.7) : Theme.stroke))
                    Circle()
                        .fill(configuration.isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.55)))
                        .padding(3)
                        .shadow(color: configuration.isOn ? Theme.magenta.opacity(0.8) : .clear, radius: 5)
                }
                .frame(width: 34, height: 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `[ − value + ]` capsule replacing the system Stepper, which reads poorly on the dark panel.
struct PillStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(label)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.text)
                .frame(minWidth: 50)
            button("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(enabled ? 0.08 : 0.03), in: Circle())
                .foregroundStyle(enabled ? Theme.text : Theme.textTertiary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .repeatsWhenHeld()
        .disabled(!enabled)
    }
}

/// Plain button that brightens a capsule background on hover.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration)
    }

    private struct GhostButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hovering ? Theme.surfaceHover : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
        }
    }
}
