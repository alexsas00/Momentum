import SwiftUI

// MARK: - Shared input for every renderer

struct VizInput {
    var series: [DayValue]        // oldest → newest
    var palette: Palette
    var goal: Double              // daily goal (phases/rings)
    var cap: Double               // normalization cap (t = value/cap)
    var unit: String

    func t(_ v: Double) -> Double { min(1, max(0, v / max(cap, 0.0001))) }
    var today: DayValue? { series.last }
    var todayT: Double { t(today?.value ?? 0) }
}

/// Dispatch. Every renderer is pure SwiftUI/Canvas — shared by app + widget targets.
struct VizView: View {
    var style: VizStyle
    var input: VizInput

    var body: some View {
        switch style {
        case .grid: GridViz(input: input)
        case .spiral: SpiralViz(input: input)
        case .burst: BurstViz(input: input)
        case .pulse: PulseViz(input: input)
        case .phases: PhasesViz(input: input)
        case .doto: DotoViz(input: input)
        case .segments: SegmentsViz(input: input)
        case .ledger: LedgerViz(input: input)
        }
    }
}

// MARK: helpers

private extension VizInput {
    /// Color for one day; mono+red palettes mark the last day with the interrupt color.
    func dayColor(_ i: Int) -> Color {
        let d = series[i]
        if i == series.count - 1, let red = palette.interrupt { return red }
        return d.value > 0 ? palette.ramp(t(d.value)) : palette.empty
    }
    func weekdayLetter(_ dv: DayValue) -> String {
        let wd = Calendar.current.component(.weekday, from: Days.date(dv.day)) - 1
        return ["S", "M", "T", "W", "T", "F", "S"][wd]
    }
}

// MARK: - 1. Grid (canvas 1a / 3f) — cell 9pt, pitch 12pt

struct GridViz: View {
    var input: VizInput
    var body: some View {
        Canvas { ctx, size in
            let pitch: CGFloat = 12, cell: CGFloat = 9
            let n = input.series.count
            let weekday = Calendar.current.component(.weekday, from: Days.date(input.series.last?.day ?? "")) - 1
            let cols = Int(ceil(Double(n + (6 - weekday)) / 7.0))
            let x0 = (size.width - CGFloat(cols) * pitch + (pitch - cell)) / 2
            let y0 = (size.height - 7 * pitch + (pitch - cell)) / 2
            for i in 0..<n {
                let posFromEnd = (n - 1 - i) + (6 - weekday)
                let col = cols - 1 - posFromEnd / 7
                let row = i < n ? (7 - 1 - posFromEnd % 7) : 0
                guard col >= 0 else { continue }
                let r = CGRect(x: x0 + CGFloat(col) * pitch, y: y0 + CGFloat(row) * pitch, width: cell, height: cell)
                let radius: CGFloat = input.palette.interrupt != nil ? 1 : 2.5
                ctx.fill(Path(roundedRect: r, cornerRadius: radius), with: .color(input.dayColor(i)))
            }
        }
    }
}

// MARK: - 2. Spiral (canvas 1b) — 5.2 turns, r 12→62 scaled to fit

struct SpiralViz: View {
    var input: VizInput
    var body: some View {
        Canvas { ctx, size in
            let n = input.series.count
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rMax = min(size.width, size.height) / 2 - 8
            let rMin = rMax * 0.19
            for i in 0..<n {
                let f = Double(i) / Double(max(1, n - 1))
                let th = -Double.pi / 2 + f * 5.2 * 2 * .pi
                let r = rMin + (rMax - rMin) * f
                let d = input.series[i]
                let s: CGFloat = d.value > 0 ? 3.2 + input.t(d.value) * 2.4 : 2.2
                let p = CGPoint(x: c.x + r * cos(th), y: c.y + r * sin(th))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                         with: .color(input.dayColor(i)))
            }
        }
    }
}

// MARK: - 3. Burst (canvas 1c / 2a) — spokes around a hero number

struct BurstViz: View {
    var input: VizInput
    var showNumber: Bool = true
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let n = input.series.count
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let gap = min(size.width, size.height) * 0.29
                let maxLen = min(size.width, size.height) * 0.21
                for i in 0..<n {
                    let d = input.series[i]
                    let len: CGFloat = d.value > 0 ? maxLen * (0.25 + 0.75 * input.t(d.value)) : maxLen * 0.1
                    let th = -Double.pi / 2 + Double(i) * (2 * .pi / Double(n))
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + gap * cos(th), y: c.y + gap * sin(th)))
                    path.addLine(to: CGPoint(x: c.x + (gap + len) * cos(th), y: c.y + (gap + len) * sin(th)))
                    ctx.stroke(path, with: .color(input.dayColor(i)), style: .init(lineWidth: 3.5, lineCap: .round))
                }
            }
            if showNumber {
                VStack(spacing: 1) {
                    Text(input.today?.value ?? 0, format: .number.precision(.fractionLength(0)))
                        .heroNumeral(26)
                        .foregroundStyle(input.palette.primaryText)
                    Text(input.unit + " today")
                        .widgetCaption(input.palette.secondaryText)
                }
            }
        }
    }
}

// MARK: - 4. Pulse (canvas 1d / 3b) — waveform bars

struct PulseViz: View {
    var input: VizInput
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(input.series.enumerated()), id: \.offset) { i, d in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(input.dayColor(i))
                        .frame(width: 4, height: d.value > 0 ? max(10, geo.size.height * 0.9 * input.t(d.value)) : 4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

// MARK: - 5. Phases (canvas 1k / 2b) — goal-fill discs

struct PhasesViz: View {
    var input: VizInput
    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(input.series.enumerated()), id: \.offset) { _, d in
                let pct = min(1.12, d.value / max(input.goal, 0.001))
                VStack(spacing: 3) {
                    Circle()
                        .fill(input.palette.empty)
                        .overlay(alignment: .bottom) {
                            GeometryReader { g in
                                Rectangle()
                                    .fill(input.palette.ramp(min(1, pct)))
                                    .frame(height: g.size.height * min(1, pct))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .clipShape(Circle())
                        .overlay {
                            if pct >= 1 {
                                Circle().strokeBorder(input.palette.accent.opacity(0.75), lineWidth: 1.5)
                            }
                        }
                        .frame(width: 28, height: 28)
                    Text(input.weekdayLetter(d))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(input.palette.tertiaryText)
                }
            }
        }
    }
}

// MARK: - 6. Doto (canvas 3d) — dot-matrix numeral + 30-day dot row

/// 5×7 dot glyphs; drawn with Canvas so no font dependency.
enum DotFont {
    static let glyphs: [Character: [String]] = [
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11111","00010","00100","00010","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],
    ]
}

struct DotoViz: View {
    var input: VizInput
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Canvas { ctx, size in
                let text = String(Int(input.today?.value ?? 0))
                let pitch = min(size.height / 7, size.width / CGFloat(text.count * 6))
                let dot = pitch * 0.78
                for (gi, ch) in text.enumerated() {
                    guard let glyph = DotFont.glyphs[ch] else { continue }
                    for row in 0..<7 {
                        for col in 0..<5 where Array(glyph[row])[col] == "1" {
                            let r = CGRect(x: CGFloat(gi * 6 + col) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot)
                            ctx.fill(Path(ellipseIn: r), with: .color(input.palette.primaryText))
                        }
                    }
                }
            }
            .frame(maxHeight: 52)
            HStack(spacing: 4) {
                ForEach(Array(input.series.suffix(30).enumerated()), id: \.offset) { i, _ in
                    let idx = input.series.count - min(30, input.series.count) + i
                    RoundedRectangle(cornerRadius: 1)
                        .fill(input.dayColor(idx))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

// MARK: - 7. Segments (canvas 3e) — 7 rows × 10 LED cells

struct SegmentsViz: View {
    var input: VizInput
    var body: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            ForEach(Array(input.series.suffix(7).enumerated()), id: \.offset) { i, d in
                let lit = d.value > 0 ? max(1, Int((input.t(d.value) * 10).rounded())) : 0
                let isLast = i == min(7, input.series.count) - 1
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(isLast ? (input.palette.interrupt ?? input.palette.accent) : .clear)
                        .frame(width: 4, height: 4)
                    Text(input.weekdayLetter(d))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(input.palette.secondaryText)
                        .frame(width: 14, alignment: .leading)
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { s in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(s < lit ? input.palette.ramp(Double(s) / 9) : input.palette.empty)
                                .frame(width: 13, height: 7)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(d.value > 0 ? String(Int(d.value)) : "—")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(input.palette.primaryText)
                }
            }
        }
    }
}

// MARK: - 8. Ledger (canvas 3i) — dense table

struct LedgerViz: View {
    var input: VizInput
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(input.series.suffix(7).enumerated()), id: \.offset) { i, d in
                HStack(spacing: 8) {
                    Text(input.weekdayLetter(d))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(input.palette.tertiaryText)
                        .frame(width: 22, alignment: .leading)
                    Text(d.value > 0 ? String(Int(d.value)) : "—")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(input.palette.primaryText)
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(input.palette.empty.opacity(0.6)).frame(height: 3)
                            Capsule()
                                .fill(d.value > 0 ? input.palette.ramp(input.t(d.value)) : .clear)
                                .frame(width: g.size.width * input.t(d.value), height: 3)
                        }
                        .frame(height: g.size.height)
                    }
                }
                .frame(height: 19)
                if i < min(7, input.series.count) - 1 {
                    Divider().overlay(input.palette.primaryText.opacity(0.06))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("All styles, green dark") {
    let store = MomentumStore()
    let metric = store.metrics[0]
    return ScrollView {
        VStack(spacing: 16) {
            ForEach(VizStyle.allCases) { style in
                let input = VizInput(
                    series: store.series(metric, days: style.defaultSpan),
                    palette: .greenDark, goal: metric.goal,
                    cap: store.cap(for: metric), unit: metric.unit)
                VStack(alignment: .leading, spacing: 6) {
                    Text(style.label).widgetCaption(Chrome.tertiary)
                    VizView(style: style, input: input)
                        .frame(height: 126)
                        .padding(16)
                        .background(Palette.greenDark.widgetBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .padding(20)
    }
    .background(Chrome.background)
    .preferredColorScheme(.dark)
}
