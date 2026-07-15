# Momentum — build instructions for Claude Code

You are assembling a real iOS app from the reference sources in `Sources/`. Read `README.md` first (design spec), and treat `design/Widget Concepts.dc.html` as the visual source of truth for the 8 widget styles.

## Ground rules
- Target **iOS 17+**, Swift 5.9+, SwiftUI, WidgetKit with `AppIntentConfiguration`.
- The files in `Sources/` were written without a compiler. Expect small fixes (imports, availability, API drift). Keep the architecture and visual constants; fix mechanics.
- Dark mode first. No third-party dependencies.

## Project setup
1. Create Xcode project **Momentum** (SwiftUI App, bundle id e.g. `com.<you>.momentum`), minimum iOS 17.
2. Add a **Widget Extension** target **MomentumWidgets** (include Configuration App Intent template, then replace its files with `Sources/Widgets/`).
3. **App Groups** capability on BOTH targets: `group.momentum.shared` — must match `AppGroup.id` in `Models.swift` (change both together).
4. **HealthKit** capability on the app target. Info.plist: `NSHealthShareUsageDescription` = "Momentum reads your workouts, energy burned, distance and steps to draw your widgets." (read-only; no update usage string needed).
5. File → add `Sources/App/*` to the app target; `Sources/Widgets/*` to the widget target. Add `Viz/`, `Theme.swift`, `Models.swift` to **both** targets (shared renderers/models — use target membership, not duplication).

## Build order (compile after each step)
1. `Theme.swift` + `Models.swift` (palettes, metrics, store, sample data).
2. `Viz/VizStyle.swift` + `Viz/VizRenderers.swift` — 8 renderers. Verify each in the `#Preview` blocks against the HTML canvas.
3. `HealthKitService.swift` — daily-summed queries; simulator has no data, use the store's `seedSampleData()` for previews/dev.
4. Screens: `RootView`, `TodayView`, `HistoryView`, `StudioView`, `MetricsView`, `OnboardingView`; entry `MomentumApp.swift`.
5. Widget target: `MomentumWidgets.swift` (+ intents). Run the widget scheme; add widgets in all sizes + lock-screen accessories.

## Acceptance checklist
- [ ] Manual binary metric: one-tap log on Today; calendar backfill on History (tap past day toggles; future disabled).
- [ ] Manual quantity metric: steppers + value editing, goal normalization.
- [ ] Health metric rows show synced daily kcal/km/steps (device test).
- [ ] Studio: changing style/palette/span updates the live preview AND the placed widget (App Group + `WidgetCenter.reloadAllTimelines()`).
- [ ] Custom palette: ColorPicker accent generates a coherent ramp (HSB derivation in `Theme.swift`).
- [ ] All 8 styles render correctly in small + medium widgets; Doto + Grid also in large; circular + inline lock-screen accessories work.
- [ ] Mono+Red palette: monochrome ramp, red used ONLY for today (it's an interrupt, not a theme color).
- [ ] Reduce Motion honored (no springs → crossfades).
- [ ] Every number that changes uses `.monospacedDigit()`.

## Visual QA against the canvas
Open `design/Widget Concepts.dc.html`. Match: option 1a/3f (grid), 1b (spiral), 1c/2a (burst), 1d/3b (pulse), 1k/2b (phases), 3d (doto), 3e (segments), 3i (ledger). Spacing/geometry constants are in the README's "Widget Styles" section — do not eyeball-drift them.
