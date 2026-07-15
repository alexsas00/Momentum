import SwiftUI

// MARK: - Palette

/// A Momentum palette: how day-intensity `t` (0…1) maps to color.
/// `interrupt` (optional) marks "today" in languages where accent ≠ ramp (Nothing mono+red).
struct Palette: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var isDark: Bool                 // designed for dark widget background?
    var emptyHex: String             // rest-day cell
    var rampLowHex: String
    var rampHighHex: String
    var accentHex: String
    var interruptHex: String?        // e.g. Nothing red — today only
    var widgetBackgroundHex: String
    var cornerRadius: CGFloat        // 24 apple, 16 nothing-technical

    func ramp(_ t: Double) -> Color {
        Color(hex: Self.mix(rampLowHex, rampHighHex, pow(max(0, min(1, t)), 0.8)))
    }
    var empty: Color { Color(hex: emptyHex) }
    var accent: Color { Color(hex: accentHex) }
    var interrupt: Color? { interruptHex.map { Color(hex: $0) } }
    var widgetBackground: Color { Color(hex: widgetBackgroundHex) }
    var primaryText: Color { isDark ? .white : Color(hex: "1A1A1A") }
    var secondaryText: Color { primaryText.opacity(isDark ? 0.62 : 0.60) }
    var tertiaryText: Color { primaryText.opacity(isDark ? 0.40 : 0.42) }

    // MARK: curated set

    static let greenDark = Palette(
        id: "green-dark", name: "3x Green", isDark: true,
        emptyHex: "282B31", rampLowHex: "1D4527", rampHighHex: "8EE887",
        accentHex: "8EE887", interruptHex: nil,
        widgetBackgroundHex: "1C1D22", cornerRadius: 24)

    static let greenLight = Palette(
        id: "green-light", name: "3x Green Light", isDark: false,
        emptyHex: "E7E9EC", rampLowHex: "C4E7BB", rampHighHex: "0A7736",
        accentHex: "0A7736", interruptHex: nil,
        widgetBackgroundHex: "FFFFFF", cornerRadius: 24)

    static let monoRed = Palette(
        id: "mono-red", name: "Mono + Red", isDark: true,
        emptyHex: "1E1E1E", rampLowHex: "3C3C3C", rampHighHex: "FFFFFF",
        accentHex: "FFFFFF", interruptHex: "D71921",
        widgetBackgroundHex: "000000", cornerRadius: 16)

    static let ember = Palette(
        id: "ember", name: "Ember", isDark: true,
        emptyHex: "2B2420", rampLowHex: "4A2A18", rampHighHex: "FFB86B",
        accentHex: "FFB86B", interruptHex: nil,
        widgetBackgroundHex: "191512", cornerRadius: 24)

    static let ocean = Palette(
        id: "ocean", name: "Ocean", isDark: true,
        emptyHex: "20262E", rampLowHex: "173A54", rampHighHex: "7FD4FF",
        accentHex: "7FD4FF", interruptHex: nil,
        widgetBackgroundHex: "12161C", cornerRadius: 24)

    static let paper = Palette(
        id: "paper", name: "Paper", isDark: false,
        emptyHex: "E8E6DF", rampLowHex: "C9C5B8", rampHighHex: "1A1A1A",
        accentHex: "1A1A1A", interruptHex: "D71921",
        widgetBackgroundHex: "F1EFE9", cornerRadius: 16)

    static let curated: [Palette] = [greenDark, greenLight, monoRed, ember, ocean, paper]

    /// Custom palette derived from a single user-picked accent (Studio ColorPicker).
    static func custom(from accent: Color, dark: Bool = true) -> Palette {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let low = UIColor(hue: h, saturation: min(1, s * 0.9), brightness: max(0.18, b * 0.35), alpha: 1)
        let high = UIColor(hue: h, saturation: s, brightness: max(b, 0.85), alpha: 1)
        return Palette(
            id: "custom", name: "Custom", isDark: dark,
            emptyHex: dark ? "26282D" : "E7E9EC",
            rampLowHex: low.hexString, rampHighHex: high.hexString,
            accentHex: high.hexString, interruptHex: nil,
            widgetBackgroundHex: dark ? "16181C" : "FFFFFF", cornerRadius: 24)
    }

    static func mix(_ aHex: String, _ bHex: String, _ t: Double) -> String {
        let a = UIColor(Color(hex: aHex)), b = UIColor(Color(hex: bHex))
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let m = UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
        return m.hexString
    }
}

// MARK: - App chrome (dark-first)

enum Chrome {
    static let background = Color(hex: "0C0D0F")
    static let card = Color(hex: "17181C")          // one notch quieter than before
    static let cardElevated = Color(hex: "1C1D22")  // legacy card / widget mirror surfaces
    static let hairline = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.40)
    static let accent = Palette.greenDark.accent
}

// MARK: - Motion tokens

/// One motion vocabulary for the whole app. Springs only; Reduce Motion is handled
/// at the call site via `Motion.respect(_:reduce:)`.
enum Motion {
    /// Default state changes — crisp, no overshoot.
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.92)
    /// Larger layout settles (cards swapping, sections appearing).
    static let settle = Animation.spring(response: 0.45, dampingFraction: 1.0)
    /// Direct user gestures — a touch of bounce as tactile confirmation.
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.72)

    /// Returns the spring, or a plain fade when Reduce Motion is on.
    static func respect(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

// MARK: - Liquid Glass helpers (iOS 26+, graceful fallback)

/// Groups sibling glass shapes so they render in one pass and can blend/morph.
/// On < iOS 26 it is a transparent pass-through.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Liquid Glass capsule surface for chips, pills and floating controls.
    /// Falls back to `.ultraThinMaterial` on earlier systems.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.resolvedGlass(tint: tint, interactive: interactive), in: .capsule)
        } else {
            self.background(tint?.opacity(0.16) ?? .clear)
                .background(.ultraThinMaterial, in: Capsule())
                .clipShape(Capsule())
        }
    }

    /// Liquid Glass rounded-rect surface for larger floating controls.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.resolvedGlass(tint: tint, interactive: interactive),
                             in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(tint?.opacity(0.16) ?? .clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Liquid Glass circle — steppers, icon buttons.
    @ViewBuilder
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.resolvedGlass(tint: tint, interactive: interactive), in: .circle)
        } else {
            self.background(tint?.opacity(0.16) ?? .clear)
                .background(.ultraThinMaterial, in: Circle())
                .clipShape(Circle())
        }
    }

    @available(iOS 26, *)
    private static func resolvedGlass(tint: Color?, interactive: Bool) -> Glass {
        var g: Glass = .regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }

    /// Soft scroll-edge treatment under floating headers (no-op before iOS 26).
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// A button style that resolves to Liquid Glass on iOS 26 and a tinted capsule before.
struct AdaptiveGlassButton: ViewModifier {
    var prominent: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButton(prominent: prominent))
    }
}

// MARK: - Type helpers ("apple + a touch of grotesk")

extension View {
    /// Hero numerals: heavy, expanded, tabular — the 3h editorial voice on SF.
    func heroNumeral(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .heavy))
            .fontWidth(.expanded)
            .monospacedDigit()
            .kerning(-0.5)
    }

    /// The Momentum wordmark voice — big, heavy, expanded sans serif.
    func wordmark(_ size: CGFloat = 40) -> some View {
        font(.system(size: size, weight: .heavy, design: .default))
            .fontWidth(.expanded)
            .kerning(-1.0)
    }

    /// 11pt uppercase tracked caption (canvas caption row).
    func widgetCaption(_ color: Color) -> some View {
        font(.system(size: 11, weight: .semibold))
            .kerning(0.7)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Section label inside screens — same voice as widgetCaption, app-side name.
    func sectionLabel() -> some View {
        widgetCaption(Chrome.tertiary)
    }
}

// MARK: - Hex color plumbing

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
