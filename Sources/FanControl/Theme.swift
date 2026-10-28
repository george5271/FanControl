import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Every colour the panel uses. One instance per theme; views read it from the environment.
struct Palette {
    var isDark: Bool

    // Outer slab and the saturated hero panel inset into it.
    var slabTop: Color
    var slabBottom: Color
    var heroTop: Color
    var heroBottom: Color
    var heroBloom: Color

    var text: Color
    var textSecondary: Color
    var hairline: Color

    var cardFill: Color
    var cardEdge: Color          // dark themes: hairline edge; light: none (shadow carries depth)
    var cardShadow: Color

    // Glossy secondary buttons.
    var buttonTop: Color
    var buttonBottom: Color
    var buttonText: Color
    var buttonShadow: Color

    // Filled primary: the selected mode.
    var primaryTop: Color
    var primaryBottom: Color
    var primaryText: Color

    /// Chart line, switches, selection rings.
    var accent: Color
    var warning: Color

    static let ocean = Palette(
        isDark: true,
        slabTop: Color(hex: 0x1A2668), slabBottom: Color(hex: 0x0E1440),
        heroTop: Color(hex: 0x3B8CFF), heroBottom: Color(hex: 0x1F4FE3), heroBloom: Color(hex: 0x7CC4FF),
        text: .white, textSecondary: Color.white.opacity(0.62), hairline: Color.white.opacity(0.10),
        cardFill: Color.white.opacity(0.06), cardEdge: Color.white.opacity(0.12), cardShadow: .clear,
        buttonTop: Color(hex: 0x34408F), buttonBottom: Color(hex: 0x1D2563), buttonText: .white,
        buttonShadow: Color(hex: 0x050A26, opacity: 0.6),
        primaryTop: Color(hex: 0x4A97FF), primaryBottom: Color(hex: 0x1E58F0), primaryText: .white,
        accent: Color(hex: 0x5CA2FF), warning: Color(hex: 0xFFB547)
    )

    static let violet = Palette(
        isDark: true,
        slabTop: Color(hex: 0x2A2233), slabBottom: Color(hex: 0x17131D),
        heroTop: Color(hex: 0xA65CFF), heroBottom: Color(hex: 0x6E22E6), heroBloom: Color(hex: 0xD7A8FF),
        text: .white, textSecondary: Color.white.opacity(0.6), hairline: Color.white.opacity(0.09),
        cardFill: Color.white.opacity(0.055), cardEdge: Color.white.opacity(0.11), cardShadow: .clear,
        buttonTop: Color(hex: 0x3A3343), buttonBottom: Color(hex: 0x221D29), buttonText: .white,
        buttonShadow: Color(hex: 0x07050A, opacity: 0.65),
        primaryTop: Color(hex: 0xB173FF), primaryBottom: Color(hex: 0x7B2FF2), primaryText: .white,
        accent: Color(hex: 0xB47BFF), warning: Color(hex: 0xFFB547)
    )

    static let light = Palette(
        isDark: false,
        slabTop: Color(hex: 0xF8F8FA), slabBottom: Color(hex: 0xEDEDF1),
        heroTop: Color(hex: 0x6A9AF4), heroBottom: Color(hex: 0x4374E6), heroBloom: Color(hex: 0xA9C8FF),
        text: Color(hex: 0x111114), textSecondary: Color(hex: 0x111114, opacity: 0.6),
        hairline: Color.black.opacity(0.07),
        cardFill: .white, cardEdge: .clear, cardShadow: Color.black.opacity(0.07),
        buttonTop: .white, buttonBottom: Color(hex: 0xF1F1F4), buttonText: Color(hex: 0x111114),
        buttonShadow: Color.black.opacity(0.12),
        primaryTop: Color(hex: 0x3A3A40), primaryBottom: Color(hex: 0x050506), primaryText: .white,
        accent: Color(hex: 0x3D6FE6), warning: Color(hex: 0xD98200)
    )
}

extension ThemeChoice {
    func palette(system: ColorScheme) -> Palette {
        switch self {
        case .system: return system == .dark ? .ocean : .light
        case .ocean: return .ocean
        case .violet: return .violet
        case .light: return .light
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.ocean
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Motion

enum Motion {
    /// Every expand/collapse of the panel. The window keeps its larger size until a collapse finishes.
    static let duration = 0.25
    static let panel = Animation.easeInOut(duration: duration)
}

// MARK: - Type

/// SF Pro Display / Text, the grotesk the references are set in.
enum Typo {
    static let figure = Font.system(size: 60, weight: .semibold).monospacedDigit()
    static let title = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11.5)
    static let button = Font.system(size: 14.5)
}

// MARK: - Surfaces

/// The slab every other element sits on.
struct SlabBackground: View {
    @Environment(\.palette) private var p

    var body: some View {
        LinearGradient(colors: [p.slabTop, p.slabBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Saturated panel with a soft light bloom at the top centre.
struct HeroBackground: View {
    @Environment(\.palette) private var p
    var cornerRadius: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [p.heroTop, p.heroBottom], startPoint: .top, endPoint: .bottom))
            .overlay(
                GeometryReader { geo in
                    RadialGradient(colors: [p.heroBloom.opacity(0.75), p.heroBloom.opacity(0)],
                                   center: UnitPoint(x: 0.5, y: 0.0),
                                   startRadius: 0, endRadius: geo.size.width * 0.62)
                }
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
    }
}

extension View {
    /// Glass card: translucent fill with a hairline edge on dark themes, plain white with a soft shadow on light.
    func glassCard() -> some View { modifier(GlassCard()) }

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

private struct GlassCard: ViewModifier {
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(14)
            .background(shape.fill(p.cardFill))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [p.cardEdge, p.cardEdge.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
            .shadow(color: p.cardShadow, radius: 14, y: 6)
    }
}

/// A raised, glossy body: vertical fill, a sheen on the upper left, a light top edge and a soft drop shadow.
struct Gloss<S: InsettableShape>: View {
    let shape: S
    let top: Color
    let bottom: Color
    var shadow: Color
    var hovered = false

    var body: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            GeometryReader { geo in
                RadialGradient(colors: [Color.white.opacity(hovered ? 0.30 : 0.20), .clear],
                               center: UnitPoint(x: 0.32, y: 0.08),
                               startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.55)
            }
            .clipShape(shape)
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.0), Color.black.opacity(0.12)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .shadow(color: shadow, radius: 12, y: 7)
    }
}

/// Glossy circle or capsule button. `prominent` paints it in the primary fill.
struct GlossyButtonStyle: ButtonStyle {
    enum Form { case circle, capsule }
    var form: Form
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, form: form, prominent: prominent)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let form: Form
        let prominent: Bool
        @Environment(\.palette) private var p
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typo.button)
                .foregroundStyle(prominent ? p.primaryText : p.buttonText)
                .frame(maxWidth: form == .capsule ? .infinity : nil)
                .frame(width: form == .circle ? 50 : nil, height: 50)
                .background {
                    let top = prominent ? p.primaryTop : p.buttonTop
                    let bottom = prominent ? p.primaryBottom : p.buttonBottom
                    let shadow = prominent ? p.primaryBottom.opacity(0.45) : p.buttonShadow
                    switch form {
                    case .circle: Gloss(shape: Circle(), top: top, bottom: bottom, shadow: shadow, hovered: hovering)
                    case .capsule: Gloss(shape: Capsule(), top: top, bottom: bottom, shadow: shadow, hovered: hovering)
                    }
                }
                .contentShape(form == .circle ? AnyShape(Circle()) : AnyShape(Capsule()))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Underlined text link, like "View all".
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.palette) private var p

        var body: some View {
            configuration.label
                .font(Typo.caption.weight(.medium))
                .underline()
                .foregroundStyle(p.text.opacity(configuration.isPressed ? 0.6 : 0.9))
                .contentShape(Rectangle())
        }
    }
}

/// iOS-style switch in the theme accent.
struct ThemedSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        @Environment(\.palette) private var p

        var body: some View {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { configuration.isOn.toggle() }
            } label: {
                HStack(spacing: 10) {
                    configuration.label
                    Spacer(minLength: 8)
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule().fill(configuration.isOn ? p.accent : p.text.opacity(p.isDark ? 0.16 : 0.12))
                        Circle()
                            .fill(.white)
                            .padding(2)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    }
                    .frame(width: 36, height: 22)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// `[ − value + ]` capsule replacing the system Stepper.
struct PillStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(label)
                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                .foregroundStyle(p.text)
                .frame(minWidth: 48)
            button("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .padding(2)
        .background(p.text.opacity(p.isDark ? 0.07 : 0.05), in: Capsule())
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(p.text.opacity(enabled ? 0.85 : 0.25))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .repeatsWhenHeld()
        .disabled(!enabled)
    }
}

/// Circular "avatar" in the pastel tones of the references.
enum Pastel {
    static let tones: [(fill: Color, ink: Color)] = [
        (Color(hex: 0xA9DDF7), Color(hex: 0x1C5A85)),   // sky
        (Color(hex: 0xD3C2F8), Color(hex: 0x4B2C8F)),   // lilac
        (Color(hex: 0xADE7C4), Color(hex: 0x1D6B3F)),   // mint
        (Color(hex: 0xF8C3CB), Color(hex: 0x8A2C3C)),   // pink
        (Color(hex: 0xF5D2B3), Color(hex: 0x86501F)),   // peach
    ]

    static func tone(_ index: Int) -> (fill: Color, ink: Color) { tones[index % tones.count] }
}

/// Row whose items keep their natural widths and share the leftover space equally,
/// so a long label ("Производительность") is never truncated to match a short one.
struct FillRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideals.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? natural, height: ideals.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideals.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        let extra = max(0, bounds.width - natural) / CGFloat(max(1, subviews.count))
        var x = bounds.minX
        for (subview, ideal) in zip(subviews, ideals) {
            let width = ideal.width + extra
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
