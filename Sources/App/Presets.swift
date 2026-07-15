import Foundation
import SwiftUI
import WidgetKit

// MARK: - Widget presets — the flagship customization system
//
// A preset is a complete, named widget design: metric + style + palette + span
// + appearance (background, radius, header). Users create unlimited presets in
// the Studio, organize them into collections, and assign any preset to any
// widget instance on the Home Screen (long-press → Edit Widget → Design).
// Every placed widget is independently configurable.
//
// ⚠️ Target membership: add this file to BOTH the app and MomentumWidgets
// targets (like Models.swift / Theme.swift) — the widget intent reads presets
// directly from the App Group.

// MARK: Appearance

/// Visual options that sit on top of a palette: how the card itself is dressed.
struct WidgetAppearance: Codable, Hashable {
    enum Background: String, Codable, CaseIterable, Identifiable {
        case palette      // the palette's designed surface
        case gradient     // subtle wash toward the ramp's low end
        case black        // pure black — great on OLED / dark wallpapers
        case transparent  // no background; content floats on the wallpaper

        var id: String { rawValue }
        var label: String {
            switch self {
            case .palette: return "Palette"
            case .gradient: return "Gradient"
            case .black: return "Black"
            case .transparent: return "Clear"
            }
        }
        var symbol: String {
            switch self {
            case .palette: return "square.fill"
            case .gradient: return "square.bottomhalf.filled"
            case .black: return "moon.fill"
            case .transparent: return "square.dashed"
            }
        }
    }

    var background: Background = .palette
    /// Corner radius for in-app cards & previews. `nil` → palette default.
    /// (Placed widgets are masked by the system; this shapes previews and the Today card.)
    var cornerRadius: CGFloat? = nil
    var showsHeader: Bool = true   // caption row: metric name
    var showsStreak: Bool = true   // streak readout in the header

    static let standard = WidgetAppearance()

    // Tolerant decoding so the model can grow without breaking saved presets.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = (try? c.decode(Background.self, forKey: .background)) ?? .palette
        cornerRadius = try? c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
        showsHeader = (try? c.decode(Bool.self, forKey: .showsHeader)) ?? true
        showsStreak = (try? c.decode(Bool.self, forKey: .showsStreak)) ?? true
    }
    enum CodingKeys: String, CodingKey { case background, cornerRadius, showsHeader, showsStreak }

    func resolvedRadius(for palette: Palette) -> CGFloat {
        cornerRadius ?? palette.cornerRadius
    }
}

// MARK: Preset

struct WidgetPreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var metricID: UUID?
    var style: VizStyle = .burst
    var paletteID: String = Palette.greenDark.id
    var customAccentHex: String? = nil
    var span: Int? = nil                       // nil → style.defaultSpan
    var appearance: WidgetAppearance = .standard
    var collectionID: UUID? = nil
    var createdAt: Date = .now

    init(id: UUID = UUID(), name: String, metricID: UUID? = nil,
         style: VizStyle = .burst, paletteID: String = Palette.greenDark.id,
         customAccentHex: String? = nil, span: Int? = nil,
         appearance: WidgetAppearance = .standard,
         collectionID: UUID? = nil, createdAt: Date = .now) {
        self.id = id; self.name = name; self.metricID = metricID
        self.style = style; self.paletteID = paletteID
        self.customAccentHex = customAccentHex; self.span = span
        self.appearance = appearance; self.collectionID = collectionID
        self.createdAt = createdAt
    }

    // Tolerant decoding (appearance/collection were added after v1 presets).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        metricID = try? c.decodeIfPresent(UUID.self, forKey: .metricID)
        style = (try? c.decode(VizStyle.self, forKey: .style)) ?? .burst
        paletteID = (try? c.decode(String.self, forKey: .paletteID)) ?? Palette.greenDark.id
        customAccentHex = try? c.decodeIfPresent(String.self, forKey: .customAccentHex)
        span = try? c.decodeIfPresent(Int.self, forKey: .span)
        appearance = (try? c.decode(WidgetAppearance.self, forKey: .appearance)) ?? .standard
        collectionID = try? c.decodeIfPresent(UUID.self, forKey: .collectionID)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
    }

    func resolvedPalette() -> Palette {
        if paletteID == "custom", let hex = customAccentHex {
            return .custom(from: .init(hex: hex))
        }
        return Palette.curated.first { $0.id == paletteID } ?? .greenDark
    }

    func resolvedSpan() -> Int { span ?? style.defaultSpan }

    /// Bridge to the legacy single-widget config (kept for migration + Today fallback).
    var asConfig: WidgetConfig {
        WidgetConfig(metricID: metricID, style: style, paletteID: paletteID,
                     customAccentHex: customAccentHex, span: span)
    }

    static func from(_ config: WidgetConfig, name: String) -> WidgetPreset {
        WidgetPreset(name: name, metricID: config.metricID, style: config.style,
                     paletteID: config.paletteID, customAccentHex: config.customAccentHex,
                     span: config.span)
    }
}

// MARK: Collections

struct PresetCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = .now
}

// MARK: Store

enum PresetStore {
    static let presetsKey = "momentum.widgetPresets"
    static let collectionsKey = "momentum.presetCollections"
    static let defaultKey = "momentum.defaultPresetID"

    // — presets

    static func load() -> [WidgetPreset] {
        guard let data = AppGroup.defaults.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([WidgetPreset].self, from: data)
        else { return [] }
        return presets.sorted { $0.createdAt < $1.createdAt }
    }

    static func save(_ presets: [WidgetPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            AppGroup.defaults.set(data, forKey: presetsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @discardableResult
    static func upsert(_ preset: WidgetPreset) -> [WidgetPreset] {
        var all = load()
        if let i = all.firstIndex(where: { $0.id == preset.id }) { all[i] = preset }
        else { all.append(preset) }
        save(all)
        return all
    }

    @discardableResult
    static func delete(id: UUID) -> [WidgetPreset] {
        var all = load()
        all.removeAll { $0.id == id }
        if defaultPresetID == id { defaultPresetID = all.first?.id }
        save(all)
        return all
    }

    static func preset(id: UUID) -> WidgetPreset? { load().first { $0.id == id } }

    /// A fresh copy the user can immediately edit.
    static func duplicate(_ preset: WidgetPreset) -> WidgetPreset {
        var copy = preset
        copy.id = UUID()
        copy.createdAt = .now
        copy.name = uniqueName(from: preset.name + " copy")
        upsert(copy)
        return copy
    }

    // — default (what un-configured widgets and the Today card show)

    static var defaultPresetID: UUID? {
        get { AppGroup.defaults.string(forKey: defaultKey).flatMap(UUID.init) }
        set {
            AppGroup.defaults.set(newValue?.uuidString, forKey: defaultKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The look every un-configured surface uses: the default preset if one is
    /// set, otherwise the legacy Studio config wrapped as a preset.
    static func defaultLook() -> WidgetPreset {
        if let id = defaultPresetID, let p = preset(id: id) { return p }
        if let first = load().first { return first }
        return .from(WidgetConfig.load(), name: "Momentum")
    }

    // — collections

    static func loadCollections() -> [PresetCollection] {
        guard let data = AppGroup.defaults.data(forKey: collectionsKey),
              let cols = try? JSONDecoder().decode([PresetCollection].self, from: data)
        else { return [] }
        return cols.sorted { $0.createdAt < $1.createdAt }
    }

    static func saveCollections(_ collections: [PresetCollection]) {
        if let data = try? JSONEncoder().encode(collections) {
            AppGroup.defaults.set(data, forKey: collectionsKey)
        }
    }

    @discardableResult
    static func addCollection(named name: String) -> PresetCollection {
        var all = loadCollections()
        let c = PresetCollection(name: name)
        all.append(c)
        saveCollections(all)
        return c
    }

    static func deleteCollection(id: UUID) {
        saveCollections(loadCollections().filter { $0.id != id })
        // Orphan the presets rather than deleting the work inside them.
        save(load().map { p in
            var p = p
            if p.collectionID == id { p.collectionID = nil }
            return p
        })
    }

    // — naming

    static func uniqueName(from base: String) -> String {
        let existing = Set(load().map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    static func suggestedName(for preset: WidgetPreset) -> String {
        uniqueName(from: "\(preset.style.label) · \(preset.resolvedPalette().name)")
    }
}
