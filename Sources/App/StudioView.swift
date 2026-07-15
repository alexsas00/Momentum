import SwiftUI
import WidgetKit

/// Widget Studio — the flagship surface.
/// Top: a live preview of the design being edited, in all three sizes.
/// Middle: every control — style, palette, appearance, data.
/// Bottom: the library — unlimited saved designs, organized into collections.
/// Placed widgets pick any saved design via long-press → Edit Widget → Design.
struct StudioView: View {
    @Environment(MomentumStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The canvas
    @State private var draft: WidgetPreset = PresetStore.defaultLook()
    // The library
    @State private var presets: [WidgetPreset] = PresetStore.load()
    @State private var collections: [PresetCollection] = PresetStore.loadCollections()
    @State private var selectedCollectionID: UUID? = nil      // nil = All
    // UI state
    @State private var previewFamily: PreviewFamily = .medium
    @State private var customColor: Color = Palette.greenDark.accent
    @State private var renaming: WidgetPreset?
    @State private var renameText = ""
    @State private var newCollectionPrompt = false
    @State private var newCollectionName = ""
    @State private var pendingCollectionMove: WidgetPreset?   // "New collection…" from Move menu
    @State private var selectTick = 0
    @State private var saveTick = 0

    enum PreviewFamily: String, CaseIterable, Identifiable {
        case small = "Small", medium = "Medium", large = "Large"
        var id: String { rawValue }
        var size: CGSize {
            switch self {
            case .small: return CGSize(width: 158, height: 158)
            case .medium: return CGSize(width: 338, height: 158)
            case .large: return CGSize(width: 338, height: 354)
            }
        }
    }

    private var savedOriginal: WidgetPreset? { presets.first { $0.id == draft.id } }
    private var isSaved: Bool { savedOriginal != nil }
    private var isDirty: Bool { savedOriginal.map { $0 != draft } ?? true }
    private var isDefault: Bool { PresetStore.defaultPresetID == draft.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    previewPedestal
                    saveBar
                    styleSection
                    paletteSection
                    appearanceSection
                    dataSection
                    librarySection
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .softTopEdge()
            .background(Chrome.background)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: selectTick)
            .sensoryFeedback(.success, trigger: saveTick)
            .animation(Motion.respect(Motion.snap, reduceMotion: reduceMotion), value: draft)
            .animation(Motion.respect(Motion.snap, reduceMotion: reduceMotion), value: previewFamily)
            .alert("Rename design", isPresented: renamingBinding) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { commitRename() }
            }
            .alert("New collection", isPresented: $newCollectionPrompt) {
                TextField("Name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { pendingCollectionMove = nil }
                Button("Create") { commitNewCollection() }
            }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Studio")
                .font(.system(size: 34, weight: .heavy))
                .fontWidth(.expanded)
                .kerning(-0.8)
                .foregroundStyle(.white)
            Text("Design your widgets")
                .widgetCaption(Chrome.tertiary)
        }
        .padding(.top, 8)
    }

    // MARK: live preview

    private var previewPedestal: some View {
        VStack(spacing: 16) {
            let data = PresetRenderData.make(preset: draft, store: store)
            PresetCardView(data: data,
                           isCompact: previewFamily == .small,
                           showsShadow: true)
                .frame(width: previewFamily.size.width, height: previewFamily.size.height)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background {
                    RadialGradient(colors: [Color.white.opacity(0.04), .clear],
                                   center: .center, startRadius: 10, endRadius: 260)
                }
                .id(draft.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            sizeSwitcher
        }
    }

    private var sizeSwitcher: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(PreviewFamily.allCases) { fam in
                    let selected = previewFamily == fam
                    Button {
                        selectTick += 1
                        previewFamily = fam
                    } label: {
                        Text(fam.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? Chrome.accent : Chrome.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                    }
                    .glassCapsule(tint: selected ? Chrome.accent.opacity(0.3) : nil,
                                  interactive: true)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: save bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button {
                saveDraft(asNew: !isSaved)
            } label: {
                Label(isSaved ? (isDirty ? "Save changes" : "Saved") : "Save design",
                      systemImage: isSaved && !isDirty ? "checkmark" : "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .tint(Chrome.accent)
            .adaptiveGlassButton(prominent: true)
            .disabled(isSaved && !isDirty)

            Menu {
                Button { saveDraft(asNew: true) } label: {
                    Label("Save as new design", systemImage: "plus.square.on.square")
                }
                if isSaved {
                    Button { setDraftAsDefault() } label: {
                        Label(isDefault ? "Default design" : "Set as default",
                              systemImage: isDefault ? "star.fill" : "star")
                    }.disabled(isDefault)
                    Button { if let o = savedOriginal { draft = o } } label: {
                        Label("Revert changes", systemImage: "arrow.uturn.backward")
                    }.disabled(!isDirty)
                }
                Button { startFresh() } label: {
                    Label("New blank design", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
            }
            .glassCircle(interactive: true)
            .accessibilityLabel("More design actions")
        }
    }

    // MARK: style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style").sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(VizStyle.allCases) { style in
                        styleCell(style)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func styleCell(_ style: VizStyle) -> some View {
        let selected = draft.style == style
        let palette = draft.resolvedPalette()
        return Button {
            selectTick += 1
            draft.style = style
        } label: {
            VStack(spacing: 8) {
                VizView(style: style, input: sampleInput(for: style, palette: palette))
                    .frame(width: 92, height: 60)
                    .padding(8)
                    .background(palette.widgetBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(style.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Chrome.accent : Chrome.secondary)
            }
            .padding(8)
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Chrome.accent : Chrome.hairline,
                                  lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("\(style.label) style")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sampleInput(for style: VizStyle, palette: Palette) -> VizInput {
        guard let metric = draftMetric else {
            return VizInput(series: [], palette: palette, goal: 1, cap: 1, unit: "")
        }
        return VizInput(series: store.series(metric, days: style.defaultSpan),
                        palette: palette, goal: metric.goal,
                        cap: store.cap(for: metric), unit: metric.unit)
    }

    // MARK: palette

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Palette").sectionLabel()
            HStack(spacing: 12) {
                ForEach(Palette.curated) { p in
                    let selected = draft.paletteID == p.id
                    Button {
                        selectTick += 1
                        draft.paletteID = p.id
                    } label: {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(hex: p.rampLowHex), Color(hex: p.rampHighHex)],
                                startPoint: .bottomLeading, endPoint: .topTrailing))
                            .frame(width: 38, height: 38)
                            .overlay {
                                if let red = p.interrupt {
                                    Circle().fill(red).frame(width: 8, height: 8)
                                        .offset(x: 11, y: -11)
                                }
                            }
                            .overlay {
                                Circle().strokeBorder(
                                    .white.opacity(selected ? 0.9 : 0.12),
                                    lineWidth: selected ? 2 : 1)
                            }
                            .scaleEffect(selected ? 1.08 : 1)
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel(p.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 38, height: 38)
                    .onChange(of: customColor) { _, new in
                        draft.paletteID = "custom"
                        draft.customAccentHex = UIColor(new).hexString
                    }
                    .accessibilityLabel("Custom palette color")
            }
        }
    }

    // MARK: appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance").sectionLabel()

            // Background
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(WidgetAppearance.Background.allCases) { bg in
                        let selected = draft.appearance.background == bg
                        Button {
                            selectTick += 1
                            draft.appearance.background = bg
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: bg.symbol).font(.system(size: 11, weight: .semibold))
                                Text(bg.label).font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(selected ? Chrome.accent : Chrome.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                        }
                        .glassCapsule(tint: selected ? Chrome.accent.opacity(0.3) : nil,
                                      interactive: true)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            // Corner radius
            VStack(spacing: 10) {
                HStack {
                    Text("Corner radius")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(draft.appearance.resolvedRadius(for: draft.resolvedPalette())))")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Chrome.secondary)
                    Button("Auto") { draft.appearance.cornerRadius = nil }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(draft.appearance.cornerRadius == nil
                                         ? Chrome.tertiary : Chrome.accent)
                        .disabled(draft.appearance.cornerRadius == nil)
                }
                Slider(value: radiusBinding, in: 8...32, step: 1)
                    .tint(Chrome.accent)
                    .accessibilityLabel("Corner radius")
            }
            .padding(14)
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Chrome.hairline, lineWidth: 1)
            }

            // Header + streak toggles
            VStack(spacing: 0) {
                toggleRow("Metric name", isOn: $draft.appearance.showsHeader)
                Divider().overlay(Chrome.hairline)
                toggleRow("Streak", isOn: $draft.appearance.showsStreak)
                    .opacity(draft.appearance.showsHeader ? 1 : 0.4)
                    .disabled(!draft.appearance.showsHeader)
            }
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Chrome.hairline, lineWidth: 1)
            }
        }
    }

    private var radiusBinding: Binding<Double> {
        Binding(
            get: { Double(draft.appearance.resolvedRadius(for: draft.resolvedPalette())) },
            set: { draft.appearance.cornerRadius = CGFloat($0) })
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .tint(Chrome.accent)
            .padding(.horizontal, 14)
            .frame(height: 48)
    }

    // MARK: data

    private var draftMetric: Metric? {
        draft.metricID.flatMap { id in store.metrics.first { $0.id == id } }
            ?? store.selectedMetric
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data").sectionLabel()

            Menu {
                ForEach(store.metrics.filter { !$0.isArchived }) { m in
                    Button {
                        selectTick += 1
                        draft.metricID = m.id
                    } label: {
                        if m.id == draftMetric?.id {
                            Label(m.name, systemImage: "checkmark")
                        } else {
                            Text(m.name)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Metric").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Text(draftMetric?.name ?? "—")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Chrome.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Chrome.tertiary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Chrome.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Chrome.hairline, lineWidth: 1)
                }
            }

            // Time span
            HStack(spacing: 8) {
                spanChip(nil, label: "Auto")
                ForEach([7, 14, 30, 168], id: \.self) { d in
                    spanChip(d, label: d == 168 ? "24 wk" : "\(d)d")
                }
            }
        }
    }

    private func spanChip(_ value: Int?, label: String) -> some View {
        let selected = draft.span == value
        return Button {
            selectTick += 1
            draft.span = value
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? Chrome.accent : Chrome.secondary)
                .padding(.horizontal, 14)
                .frame(height: 36)
        }
        .glassCapsule(tint: selected ? Chrome.accent.opacity(0.3) : nil, interactive: true)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: library

    private var visiblePresets: [WidgetPreset] {
        guard let cid = selectedCollectionID else { return presets }
        return presets.filter { $0.collectionID == cid }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library").sectionLabel()
                Spacer()
                Text("\(presets.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Chrome.tertiary)
            }

            collectionsRow

            if visiblePresets.isEmpty {
                emptyLibrary
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(visiblePresets) { preset in
                        presetCell(preset)
                    }
                }
            }
        }
    }

    private var collectionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    collectionChip(nil, name: "All")
                    ForEach(collections) { c in
                        collectionChip(c.id, name: c.name)
                            .contextMenu {
                                Button(role: .destructive) {
                                    PresetStore.deleteCollection(id: c.id)
                                    reloadLibrary()
                                    if selectedCollectionID == c.id { selectedCollectionID = nil }
                                } label: { Label("Delete collection", systemImage: "trash") }
                            }
                    }
                    Button {
                        newCollectionName = ""
                        newCollectionPrompt = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Chrome.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .glassCircle(interactive: true)
                    .accessibilityLabel("New collection")
                }
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
    }

    private func collectionChip(_ id: UUID?, name: String) -> some View {
        let selected = selectedCollectionID == id
        return Button {
            selectTick += 1
            selectedCollectionID = id
        } label: {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Chrome.accent : Chrome.secondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
        }
        .glassCapsule(tint: selected ? Chrome.accent.opacity(0.3) : nil, interactive: true)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func presetCell(_ preset: WidgetPreset) -> some View {
        let data = PresetRenderData.make(preset: preset, store: store)
        let editing = preset.id == draft.id
        let isDefaultPreset = PresetStore.defaultPresetID == preset.id
        return Button {
            selectTick += 1
            draft = preset
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                PresetCardView(data: data, isCompact: true)
                    .frame(height: 108)
                    .allowsHitTesting(false)
                HStack(spacing: 5) {
                    if isDefaultPreset {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Chrome.accent)
                    }
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .background(Chrome.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(editing ? Chrome.accent : Chrome.hairline,
                                  lineWidth: editing ? 1.5 : 1)
            }
        }
        .buttonStyle(.pressScale)
        .contextMenu { presetMenu(preset, isDefaultPreset: isDefaultPreset) }
        .accessibilityLabel("\(preset.name) design\(isDefaultPreset ? ", default" : "")")
    }

    @ViewBuilder
    private func presetMenu(_ preset: WidgetPreset, isDefaultPreset: Bool) -> some View {
        Button {
            PresetStore.defaultPresetID = preset.id
            preset.asConfig.save()
            reloadLibrary()
        } label: { Label("Set as default", systemImage: "star") }
            .disabled(isDefaultPreset)

        Button {
            renameText = preset.name
            renaming = preset
        } label: { Label("Rename", systemImage: "pencil") }

        Button {
            let copy = PresetStore.duplicate(preset)
            reloadLibrary()
            draft = copy
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }

        Menu {
            Button("None") { move(preset, to: nil) }
            ForEach(collections) { c in
                Button(c.name) { move(preset, to: c.id) }
            }
            Divider()
            Button {
                pendingCollectionMove = preset
                newCollectionName = ""
                newCollectionPrompt = true
            } label: { Label("New collection…", systemImage: "plus") }
        } label: { Label("Move to collection", systemImage: "folder") }

        Divider()
        Button(role: .destructive) {
            presets = PresetStore.delete(id: preset.id)
            if draft.id == preset.id { draft = PresetStore.defaultLook() }
        } label: { Label("Delete", systemImage: "trash") }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Chrome.tertiary)
            Text("No designs yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Chrome.secondary)
            Text("Style a widget above, then save it here.\nEvery Home Screen widget can show a different design.")
                .font(.system(size: 13))
                .foregroundStyle(Chrome.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Chrome.card.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .foregroundStyle(Chrome.hairline)
        }
    }

    // MARK: actions

    private func saveDraft(asNew: Bool) {
        if asNew {
            draft.id = UUID()
            draft.createdAt = .now
            if draft.name.isEmpty || presets.contains(where: { $0.name == draft.name }) {
                draft.name = PresetStore.suggestedName(for: draft)
            }
            if let cid = selectedCollectionID { draft.collectionID = cid }
        }
        if draft.name.isEmpty { draft.name = PresetStore.suggestedName(for: draft) }
        let firstEver = presets.isEmpty
        presets = PresetStore.upsert(draft)
        if firstEver || isDefault { setDraftAsDefault(silent: true) }
        saveTick += 1
    }

    private func setDraftAsDefault(silent: Bool = false) {
        PresetStore.defaultPresetID = draft.id
        draft.asConfig.save()               // keep legacy config in step
        if !silent { saveTick += 1 }
        reloadLibrary()
    }

    private func startFresh() {
        var fresh = WidgetPreset(name: "")
        fresh.metricID = store.selectedMetric?.id
        fresh.collectionID = selectedCollectionID
        draft = fresh
    }

    private func move(_ preset: WidgetPreset, to collectionID: UUID?) {
        var p = preset
        p.collectionID = collectionID
        presets = PresetStore.upsert(p)
        if draft.id == p.id { draft.collectionID = collectionID }
    }

    private func commitRename() {
        guard let target = renaming else { return }
        var p = target
        p.name = renameText.trimmingCharacters(in: .whitespaces)
        if p.name.isEmpty { p.name = target.name }
        presets = PresetStore.upsert(p)
        if draft.id == p.id { draft.name = p.name }
        renaming = nil
    }

    private func commitNewCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { pendingCollectionMove = nil; return }
        let c = PresetStore.addCollection(named: name)
        collections = PresetStore.loadCollections()
        if let preset = pendingCollectionMove {
            move(preset, to: c.id)
            pendingCollectionMove = nil
        } else {
            selectedCollectionID = c.id
        }
    }

    private func reloadLibrary() {
        presets = PresetStore.load()
        collections = PresetStore.loadCollections()
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
