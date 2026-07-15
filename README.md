# Handoff: Momentum — iOS burn & habit widget app

## Overview
Momentum is an iOS app that visualizes daily effort — calories burned, km run, or any manual habit ("days without sugar", "glasses of water") — as glanceable home-screen widgets. The core idea: **rethink the contribution chart**. The app ships 8 visualization styles (grid, spiral, burst, pulse, phases, doto, segments, ledger), user-selectable color palettes (6 curated + custom picker), automatic HealthKit metrics and manual metrics with calendar backfill.

## About the Design Files
`design/Widget Concepts.dc.html` is a **design reference created in HTML** — a canvas of widget explorations (turns 1–3), not production code. The Swift files in `Sources/` are a **reference implementation** written blind (no Xcode): treat them as a strong starting point to be assembled, compiled and fixed inside a real Xcode project (see `CLAUDE.md`). Recreate the HTML designs' look faithfully; where HTML and Swift disagree, the HTML canvas is the visual source of truth.

## Fidelity
**High-fidelity.** The HTML canvas shows final colors, type scale, spacing and data-mapping for every widget style. App chrome (tabs, sheets, lists) is specified below at spec level; follow iOS-native patterns for anything unspecified.

## Design Language
- **Base:** Apple-native, dark mode first. Backgrounds `#0C0D0F` (app) / `#1C1D22` (cards, widgets). Translucent materials (`.ultraThinMaterial`) for bars/sheets.
- **Type:** SF Pro. Hero numerals use SF with `fontWidth(.expanded)` + heavy weight (the "grotesk editorial" touch from canvas option 3h); data numerals always `.monospacedDigit()`. Captions: 11pt semibold, `+0.06em` tracking, uppercase, 55% white.
- **Dot-matrix style ("Doto"):** rendered with Canvas dots (5×7 glyph font in `VizRenderers.swift`) — no font dependency.
- **Motion:** springs only (`.spring(response: 0.35, dampingFraction: 1.0)`); add bounce (0.8) only after user-driven gestures. Respect Reduce Motion.
- **No emoji, no gradients in chrome, one accent per screen.**

## Screens / Views
1. **Onboarding** (`OnboardingView.swift`) — 3 pages: promise ("Your effort, on your home screen"), Health permission request, first metric creation. Skippable.
2. **Today** (`TodayView.swift`) — Purpose: log + glance. Layout: metric switcher (horizontal chips, 44pt), hero card (selected viz style at medium-widget proportions, 16pt padding, 24pt radius), quick-log row: binary metrics get a large check button (min 44pt), quantity metrics get −/＋ steppers with big monospaced value; Health metrics show "synced" state instead.
3. **History** (`HistoryView.swift`) — Purpose: backfill + insights. Month calendar grid (7 cols, 40pt cells, intensity-tinted like the Grid style; tap any past day to toggle/edit via sheet), month pager, insights row: streak, total, best day (3 stat blocks, monospaced).
4. **Widget Studio** (`StudioView.swift`) — Purpose: configure widgets. Live preview card at top (renders exact WidgetKit view for small/medium sizes), then pickers: Size (segmented), Style (horizontal gallery of 8 mini-previews), Palette (swatch row: 6 curated + "Custom…" opening `ColorPicker`), Metric, Time span (7/14/30/168 days). Selections persist to the shared App Group so widgets update live (`WidgetCenter.reloadAllTimelines()`).
5. **Metrics** (`MetricsView.swift`) — Purpose: manage data sources. List of metrics (icon-free rows: name, kind badge, goal); add sheet: name, kind (Health kcal / Health km / Health steps / Manual yes-no / Manual quantity), daily goal + unit; swipe to archive.
6. **Root** (`RootView.swift`) — TabView: Today · History · Studio · Metrics.

## Widget Styles (shared renderers, app + WidgetKit)
All take `[DayValue] + Palette + goal` and normalize `t = min(1, value/goal-cap)`. Exact geometry ported from the HTML canvas:
- **Grid** (1a/3f): columns = weeks, 7 rows, cell = 9pt, pitch 12pt, radius 2.5 (1 in mono palette), empty = `surfaceDim`.
- **Spiral** (1b): 365 dots, 5.2 turns, r 12→62, dot 2.2–5.6pt by t.
- **Burst** (1c): 30 spokes, 12° step, inner gap 36pt, length 10+30·t, rounded caps.
- **Pulse** (1d): 30 bars, 4pt wide, 3pt gap, h 10+86·t, radius 2.
- **Phases** (1k): 14 discs 28pt, bottom-fill = value/goal, ring glow at ≥100%.
- **Doto hero** (3d): dot-matrix numeral (5×7 glyphs, 6pt pitch) + 30-day dot row; in Mono palette today's dot is `#D71921`.
- **Segments** (3e): 7 rows × 10 segments 13×7pt, lit = round(10·t), mono labels.
- **Ledger** (3i): 7 rows: DOW / kcal / km / 3pt intensity bar, hairline dividers.

## Interactions & Behavior
- Logging writes immediately (no save button), spring-animates the hero viz, reloads widget timelines.
- Calendar: tap day → binary toggles instantly; quantity opens stepper sheet. Future days disabled.
- Health metrics: read-only; pull-to-refresh triggers re-query.
- Widgets: `AppIntentConfiguration` — user long-presses widget to pick metric/style/palette/span. Lock-screen accessory: inline (streak) + circular (goal %).
- All animations interruptible; no input lockouts.

## State Management
- `MomentumStore` (`Models.swift`): `@Observable`, single source of truth. Metrics + day values persisted as JSON in the App Group container; `WidgetCenter.reloadAllTimelines()` after every mutation.
- `HealthKitService`: daily-summed queries (active energy, distance, steps) merged into the store cache so widgets can render without querying HealthKit directly.
- Studio config (style/palette/span per metric) stored in shared `UserDefaults(suiteName: appGroup)`.

## Design Tokens
- **Chrome (dark):** bg `#0C0D0F`, card `#1C1D22`, hairline `rgba(255,255,255,0.08)`, text `#FFFFFF` / 62% / 40%.
- **Palettes** (`Theme.swift`), each = empty + low→high ramp + accent:
  - 3x Green (dark): empty `#282B31`, ramp `#1D4527 → #8EE887`, accent `#8EE887`
  - 3x Green (light): empty `#E7E9EC`, ramp `#C4E7BB → #0A7736`, accent `#0A7736`
  - Mono + Red (Nothing): empty `rgba(255,255,255,0.07)`, ramp `white 14% → 100%`, interrupt `#D71921` (today only)
  - Ember: empty `#2B2420`, ramp `#4A2A18 → #FFB86B`, accent `#FFB86B`
  - Ocean: empty `#20262E`, ramp `#173A54 → #7FD4FF`, accent `#7FD4FF`
  - Paper (light mono): empty `#E8E6DF`, ramp `#C9C5B8 → #1A1A1A`, accent `#1A1A1A`
  - Custom: user accent → ramp generated in HSB (low = accent at 35% brightness/60% sat, high = accent).
- **Spacing:** 4/8/12/16/24/32. **Radii:** widgets 24 (16 in Mono palette), cards 24, chips 999. **Type scale:** hero 34–64 heavy expanded, title 17/600, body 15/400, caption 11/600 caps.

## Assets
None required. Dot-matrix digits are code-drawn; no custom fonts bundled (SF only). The 3x logo greens are encoded in the palettes.

## Files
- `design/Widget Concepts.dc.html` — visual source of truth (open in a browser)
- `CLAUDE.md` — step-by-step build instructions for Claude Code
- `Sources/App/…` — app target reference code
- `Sources/Widgets/…` — widget extension reference code
