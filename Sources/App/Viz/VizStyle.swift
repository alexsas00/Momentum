import Foundation

// MARK: - Viz style registry

/// The 8 visualization styles. Raw values are stable — persisted in widget config.
enum VizStyle: String, Codable, CaseIterable, Identifiable {
    case grid       // 1a/3f — contribution grid, weeks × 7
    case spiral     // 1b — 365-day coil
    case burst      // 1c/2a — radial spokes around a number
    case pulse      // 1d/3b — waveform bars
    case phases     // 1k/2b — goal-fill discs
    case doto       // 3d — dot-matrix numeral + day row
    case segments   // 3e — 7-day LED segment rows
    case ledger     // 3i — dense table rows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .spiral: return "Spiral"
        case .burst: return "Burst"
        case .pulse: return "Pulse"
        case .phases: return "Phases"
        case .doto: return "Doto"
        case .segments: return "Segments"
        case .ledger: return "Ledger"
        }
    }

    /// Days of data each style wants by default (Studio can override where sensible).
    var defaultSpan: Int {
        switch self {
        case .grid: return 168      // 24 weeks
        case .spiral: return 365
        case .burst, .pulse: return 30
        case .phases: return 14
        case .doto: return 30
        case .segments, .ledger: return 7
        }
    }

    /// Styles that read well at each widget family.
    var supportsSmall: Bool {
        switch self {
        case .grid, .ledger, .segments: return false
        default: return true
        }
    }
}

// MARK: - Widget configuration (persisted to App Group)

struct WidgetConfig: Codable, Equatable {
    var metricID: UUID?
    var style: VizStyle = .burst
    var paletteID: String = Palette.greenDark.id
    var customAccentHex: String? = nil   // set when paletteID == "custom"
    var span: Int? = nil                 // nil → style.defaultSpan

    static let key = "momentum.widgetConfig"

    static func load() -> WidgetConfig {
        guard let data = AppGroup.defaults.data(forKey: key),
              let cfg = try? JSONDecoder().decode(WidgetConfig.self, from: data) else {
            return WidgetConfig()
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }

    func resolvedPalette() -> Palette {
        if paletteID == "custom", let hex = customAccentHex {
            return .custom(from: .init(hex: hex))
        }
        return Palette.curated.first { $0.id == paletteID } ?? .greenDark
    }
}
