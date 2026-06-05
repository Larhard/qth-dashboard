# QTH Dashboard — Project Constitution

> **Vibe-coded.** This project was built interactively with AI assistance.
> No formal testing, safety audit, or regulatory review has been performed.
> Never rely on this app as your sole means of navigation.

---

## 1. Project Vision

QTH Dashboard is a high-reliability Android navigation dashboard for people who
need precise, glanceable positional awareness in demanding conditions — aboard a
vessel at night, on a mountain summit with wet gloves, driving in an emergency,
or operating in the field as the last radio link.

The design philosophy can be summarised in three words: **fast, safe, honest**.

* **Fast** — every critical value is readable in under one second without
  interaction. No menus before the bearing to your MOB waypoint.
* **Safe** — the night mode never emits blue or green light that destroys
  night-adapted vision. The interface is operable one-handed in rough conditions.
  No feature that could cause a driver to look away from the road for more than
  a glance is accessible while driving.
* **Honest** — the heading display shows `---` rather than a plausible-looking
  MAG reading when the user is in GPS/TRK mode and data has not yet arrived.
  Alarms are as loud and disturbing as the hardware permits regardless of
  silent/mute/DND settings.

---

## 2. Use Cases

### 2.1 Ham Radio (SOTA · POTA · IOTA · EMCOM)

| Need | Feature |
|---|---|
| Grid-square for logging | IARU/Maidenhead 8-char display, live |
| Bearing and distance to designated spot | Waypoint navigation card |
| Emergency locator for rescue relay | MOB one-tap, coordinatesinstantly visible |
| Night operating with red-only lighting | Night mode (pure red palette) |
| Battery saving on summit | Screen-off GPS pause; compass/timer halt |
| EMCOM rendezvous at grid | Named waypoints, GPX import/export |

EMCOM deployments often rely on the phone as the only navigation device.
All critical data (coordinates, locator, bearing, distance) must be visible
simultaneously on a single screen without scrolling.

### 2.2 Marine / Sailing

| Need | Feature |
|---|---|
| Night watch — no white light | Night mode: only wavelengths >600 nm |
| Port/VHF data | Port mode city layer with VHF channel |
| Bearing/distance to anchorage | Waypoint card with relative ring |
| Anchor dragging alarm | Anchor alarm with two levels + GPS-loss escalation |
| MOB at sea | Instant MOB button, always visible at bottom |
| Pocket the phone safely | Proximity-based screen dim with charger bypass |
| Wake from lock on alarm | Screen wake-lock + `setShowWhenLocked` |

Night-sailing imposes a hard rule: **no white, green, blue, or amber at any
brightness**. The night palette is a single red hue family varying only in
brightness — exactly as the rod cells at the edge of the retina respond to
long-wavelength light without losing dark adaptation.

**Anchor alarm requirements:**
- Level 1 (Warning): gentle double vibration + audible beep, every ~8 s.
  Sounds at any volume level including silent mode.
- Level 2 (Alarm): maximum-volume dissonant siren, continuous vibration,
  flashlight strobe, full-screen blink. Sounds regardless of mute/DND/lock state.
- GPS loss: 60 s → Level 1, 180 s → Level 2. Stationary GPS keep-alive every 20 s.

### 2.3 Driving (including Emergency Services)

**Prime directive: the driver must never be distracted.**

Rules enforced by the design:
- The anchor alarm setup requires long-press in the Waypoints screen — it cannot
  be triggered while a thumb is resting on the main screen.
- No setup dialogs are surfaced from the primary navigation display.
- MOB tapping is intentional (single tap), but the 3-second clear hold prevents
  accidental clear while driving.
- Font hierarchy ensures heading, speed, and coordinates are readable at a glance
  without head movement.
- Wind-rose and arrow mode both work at a glance without reading a label.

In driving use the heading source auto-switches: GPS at ≥5.4 km/h, TRK while
in motion below that threshold, and — **critically** — shows `---` with TRK
colour before any track data exists, never silently using MAG.

### 2.4 Hiking (battery saving · rugged)

- GPS stream is **cancelled** when the screen turns off (SAVE mode, default).
- Compass, stale timer, city lookups are **paused** on screen-off.
- GPS-on-lock mode allows optional background GPS (foreground service) for
  real-time tracking, with explicit user opt-in.
- Proximity sensor pocket lock prevents accidental button presses when the phone
  is stored without activating the keyguard (biometrics still work instantly).
- 0.5° compass threshold gate: no unnecessary redraws when standing still.
- City lookup threshold: 100 m movement before recalculating.
- All timers resume within one frame of screen-on; no stale data.

---

## 3. Supported Resolutions & Layout Rules

### Mandatory resolutions

| Device | Resolution | Logical pixels (approx) |
|---|---|---|
| Ulefone Armor Mini 20T Pro | 720 × 1600 px | 360 × 800 dp |
| Google Pixel 6a | 1080 × 2400 px | 411 × 914 dp |

Both portrait and landscape orientations must be supported at both resolutions.

### The no-scroll layout contract (CRITICAL)

The main dashboard **never scrolls and never overflows** — it must be fully
glanceable while driving. This is guaranteed by a three-zone structure, used
identically in portrait (vertical Column) and landscape (right column):

```
FIXED top     →  heading + coordinates   (always full size, always visible)
ADAPTIVE mid  →  city + nav + anchor      (shrinks uniformly to fit leftover space)
FIXED bottom  →  MOB                       (always full size, always reachable)
```

- The adaptive middle is wrapped by **`_adaptiveSecondary()`** —
  `Expanded → LayoutBuilder → FittedBox(scaleDown) → SizedBox(width) → Column`.
  It renders at natural size when there's room and **shrinks uniformly** (never
  enlarges, never scrolls, never overlaps) when crowded. **Any widget added to
  the middle automatically participates** in shrink-to-fit, so new sections
  cannot break the layout.
- **Only the secondary block shrinks.** Heading, coordinates and MOB keep their
  full size in every scenario (product decision — those are the safety-critical,
  glance-while-driving elements).

### Rules

1. **Nothing cropped, nothing scrolled, nothing overlapped** — for ANY content:
   long 2-line city name + VHF + call sign + country + nav waypoint + anchor card
   + MOB, in either orientation, on the smallest mandatory screen.
2. **Fixed sections must fit the smallest viewport.** heading + coordinates + MOB
   + dividers must sum to **less than the usable height of 360 × 800 dp portrait
   and 800 × 360 dp landscape** so the adaptive middle always has ≥ 0 px. Adding
   to a FIXED zone requires re-checking this budget; prefer adding to the middle.
3. **All variable-width text degrades gracefully** — every name/label that can be
   arbitrarily long uses `_fitFontSize()` (width + max-lines) AND/OR `Flexible`/
   `Expanded` + `TextOverflow.ellipsis`. Never place an unconstrained `Text` in a
   `Row`. (The middle's FittedBox is the height backstop; this is the width backstop.)
4. **MOB always at the bottom**, fixed, in both orientations.
5. **Anchor mode priority** — when anchoring, the city collapses to a compact
   one-line row and the nav waypoint to a compact bearing row, leaving the anchor
   card the most prominent secondary element.
6. **Font hierarchy** — heading degrees largest; speed/coords/locator/time
   secondary; labels/metadata tertiary.
7. **Landscape compact sizes** — landscape card/font sizes are stepped down from
   portrait so the left (heading+coords) and right (middle+MOB) columns each fit
   the ~336 dp landscape height.

### How to verify a layout change

Before merging any change touching the dashboard, mentally (or in an emulator)
run the **worst-case matrix** at 360 × 800 dp AND 800 × 360 dp:

| City name | VHF/call sign | Nav waypoint | Anchor | MOB |
|---|---|---|---|---|
| 2-line long | both present | active (long name) | active | active |

If everything is visible (middle may be visibly smaller) with no scroll bar and
no overflow stripe, the change is safe.

---

## 4. Colour System

### Philosophy

The app has **two palettes built on two different principles**, both defined in
`lib/theme/palette.dart`:

- **Night (`kN*`) is a pure-red brightness RAMP.** Every value has green = `0x00`
  and blue = `0x00`; prominence is brightness alone (kN0 brightest … kN4 dimmest).
- **Day (`kD*`) is SEMANTIC.** Hue encodes data type (green = GPS, amber = MGRS,
  cyan = port, red = emergency, orange = nav).

Because the two principles differ, the day→night mapping is **contextual**: the
same day hue maps to whichever ramp brightness fits its prominence in that spot.

**Two rules make this maintainable and safe:**

1. **No raw hex literals outside `lib/theme/palette.dart`.** Enforced by a test
   (`test/palette_test.dart` checks no `Color(0x…)` leaks; `flutter analyze`
   would also flag an undefined constant). All colours are named constants.
2. **Resolve colours through `Palette`, not scattered `dayMode ? .. : ..`.**
   `Palette` (in `palette.dart`) is the SINGLE place the day/night decision for
   each semantic role lives:

   ```dart
   final p = Palette.of(_dayMode);     // const singleton — never allocates
   Text(name, style: TextStyle(color: p.textPrimary));   // role, not a ternary
   color: p.emergency,                  // day kDEmg / night kN0, defined once
   color: p.pick(kDPort, kN2),          // escape hatch for a genuine one-off
   ```

   Every colour a `Palette` returns in night mode is a `kN*` (or `Colors.black` /
   `Colors.transparent`), so the pure-red rule is **enforced by construction** —
   a call site physically cannot pick a non-red night colour through a role, and
   `test/palette_test.dart` asserts every night role has g = 0, b = 0.

This ensures that:
- A single edit to one role propagates to every screen instantly.
- Night mode is provably pure-red (verified by test, not just convention).
- Day mode keeps its semantic meaning.

Painters and small sub-widgets that already receive a `dayMode` flag may resolve
colours inline (`dayMode ? kDx : kNy`) — they are hot, localized, and pass the
flag explicitly; constructing a `Palette` there is unnecessary. Everywhere else,
use a `Palette`.

### Night palette (`kN*`) — STRICT PURE RED

**HARD RULE: every night-mode colour has green = `0x00` and blue = `0x00`.**
All night values lie exactly on the line `#000000` → `#FF0000`; only the red
channel varies. This is non-negotiable — any green or blue light destroys rod
(night-adapted) vision, which is the entire point of night mode for marine and
field use. A night colour of the form `#RRGGBB` is a bug unless `GG == 00` and
`BB == 00`.

| Constant | Value | Semantic role |
|---|---|---|
| `kN0` | `#FF0000` | Emergency / North indicator arc / brightest accent |
| `kN1` | `#CC0000` | Primary text, active icon |
| `kN2` | `#9A0000` | Secondary text, sub-label |
| `kN3` | `#770000` | Metadata, captions |
| `kN4` | `#4A0000` | Hints, disabled, very dim |
| `kNBg` | `#1A0000` | Tile / card background |
| `kNDiv` | `#250000` | Dividers, borders |
| `kNSheet` | `#0A0000` | Modal / bottom-sheet background |
| `kNEmgRing` / `kNEmgRingDim` / `kNEmgArc` | `#2A0000` / `#1A0000` / `#AA0000` | Hold-to-clear ring animation |

**Night mode rules:**
- No white, grey, blue, green, amber, cyan — **and no desaturated red** (no
  `#FFxxyy` with non-zero green/blue). Pure red channel only.
- This applies to EVERYTHING in dark mode: text, icons, borders, backgrounds,
  splashes/highlights, tooltips, snackbars, **slider tracks AND tick marks**,
  tab-bar overlays, progress rings, the strobe overlay, and any `CustomPainter`.
- Widgets with framework default colours (Slider tick marks, ripples, dividers,
  Material surface tints) MUST have their night colours pinned to `kN*` — the
  Material defaults are grey and will leak through otherwise.
- `Colors.black` and `Colors.transparent` are the only non-`kN*` values allowed
  in night mode (both are within the rule).
- Screen strobe during anchor alarm alternates black ↔ `kN0`.
- Snackbars: `kNBg` background, `kN2` text. Tooltips: `kNBg` background, `kN1` text.

### Day palette (`kD*`) — semantic colours

| Group | Constants | Semantic role |
|---|---|---|
| Text | `kDFg0–kDFg4` | White → dark-grey scale |
| GPS / heading | `kDGps`, `kDGpsL`, `kDTrk` | Green (GPS), yellow (TRK) |
| Emergency / MOB | `kDEmg`, `kDEmgS`, `kDEmgBg` | Red family |
| Stale / warning | `kDStale` | Orange-red |
| Nav waypoint | `kDNav`, `kDNavL` | Deep orange |
| MGRS / amber | `kDAmb`, `kDAmbs` | Amber-orange family |
| City tiers | `kDCityL`, `kDCityP`, `kDCityD`, `kDCityDS` | Orange → lime |
| Port / cyan | `kDPort`, `kDPortL` | Cyan |
| UI chrome | `kDDiv`, `kDBrd`, `kDFoc`, `kDSheetBg`, `kDSnackBg` | Dark surfaces |
| Animation rings | `kDEmgRing`, `kDEmgRingDim`, `kNEmgRing`, `kNEmgRingDim`, `kDEmgArc`, `kNEmgArc` | Hold-to-clear animation |
| Debug precision | `kDGpsM6`, `kDGpsM4` | Maidenhead tier colours |

**Day mode rules:**
- All text must be readable in direct sunlight on a 720×1600 phone.
- Contrast ratio ≥ 4.5:1 for primary text against black background.
- Tooltips: `kDSnackBg` background, `kDFg1` text.

### Theme-level colours (dynamic, in `main.dart`)

`QthHelperApp` is a `StatefulWidget` that listens to `GetStorage('day_mode')`
and rebuilds the `MaterialApp` theme on every day↔night toggle. It resolves theme
colours through a `Palette` like everywhere else. This ensures tooltips, ripples,
and tab bars always use the correct palette regardless of Material 3 surface-tint
defaults.

### Dart and native (Kotlin) colours — one source of truth

Dart and Kotlin cannot share a compile-time colour constant, but they don't need
to: **the native side has no colour palette of its own.** The only place Kotlin
draws coloured pixels is the floating overlay, and it receives every colour as an
ARGB int **pushed from Dart** (resolved from `Palette` — see §9). So `palette.dart`
remains the single source of truth at runtime; the native view is a dumb renderer.

The sole exception is a handful of hard-coded fallback defaults in `OverlayView`
used only in the brief window before Dart has pushed its first frame (or if the
Flutter engine is dead). Those defaults MUST still obey the pure-red night rule.
This is why full Dart↔Kotlin colour "unification" is unnecessary rather than
infeasible: colours flow one way, Dart → native, at runtime.

---

## 5. Coding Practices

### 5.0 Architecture & design patterns (the patterns to maintain)

The codebase follows a small set of deliberate, conventional patterns. New work
should fit one of these rather than invent a new structure:

- **Layered architecture with a one-way dependency rule** (§6). `models → utils →
  services → screens`; `config/theme/settings` are leaf modules everyone may read.
  A lower layer never imports a higher one. This keeps logic testable and the UI
  thin.
- **Pure core, tested in isolation.** Deterministic logic (formatting, geo math,
  GPX dedup, alarm-level spec) is extracted into `utils/` as pure functions/classes
  with no I/O or platform channels, and unit-tested. Prefer extracting a pure
  function over testing through a widget.
- **Service singletons as the data/state layer.** Each `*Service` is a plain Dart
  singleton (no `BuildContext`) owning one concern (waypoints, cities, anchor
  presenter, overlay). Screens are the only layer touching `setState`/`Navigator`.
- **Single authority for hardware & shared state** (§7.1). Exactly one component
  computes a given piece of state and one drives a given piece of hardware, per
  process. The native `AnchorController` is the alarm authority; Dart only presents.
- **Native presenter/authority split for platform features.** Kotlin owns hardware
  and survival (services, `AudioTrack`, wake locks); Dart presents via thin
  `MethodChannel` bridges named `qth_helper/<feature>`. No Android SDK types leak
  into Dart.
- **Semantic resolver for theming** (§4). One `Palette` maps roles → colours for
  the current mode; call sites name a role, not a `dayMode ?` ternary.
- **Centralized tunables, guarded across the boundary** (§5.9, §5.10). Tuning knobs
  in `config/tuning.dart` and `Tuning.kt`; cross-language shared values pinned by a
  test.
- **Opt-in background work only** (§5.5). No sensor/CPU/network cost unless the user
  enabled a feature that needs it.

Known debt: `home_screen.dart` is a large `StatefulWidget` (a "god widget"). It is
the one place that does not yet fit the above cleanly — see §10 for the planned
extraction. Do not add unrelated concerns to it; new sections belong in their own
widget/file.

### 5.1 General

- **Flutter 3.x / Dart 3.x** for all UI and business logic.
- **Kotlin** for Android-only hardware features (vibration, audio, flashlight,
  wake lock, proximity sensor, GNSS status).
- **Pure Dart** service classes for platform-independent logic (waypoints, cities,
  anchor state). No Android SDK references outside `*.kt` files and MethodChannels.
- All `MethodChannel` / `EventChannel` identifiers follow the format
  `qth_helper/<feature>` (e.g. `qth_helper/anchor_alarm`).

### 5.2 Colours: named constants, resolved through `Palette`

```dart
// ✓ correct — semantic role, day/night rule defined once in palette.dart
color: p.gps,
color: p.pick(kDPort, kN2),   // one-off the named roles don't cover

// ✗ wrong — raw hex literal (breaks the single palette; fails palette_test)
color: const Color(0xFF55DD55),

// ✗ avoid — scattered day/night ternary in widget code (use a Palette role)
color: _dayMode ? kDGps : kN1,
```

`Colors.black` and `Colors.transparent` are the only non-palette colours allowed
(both satisfy the pure-red night rule). Raw hex anywhere but `palette.dart` is a
bug caught by `test/palette_test.dart`.

### 5.3 No unnecessary abstractions

Three similar lines are better than a premature abstraction. Do not extract a
helper unless it is called from ≥ 3 distinct locations or contains non-trivial
logic that would be tested independently.

### 5.4 No silent fallbacks that mislead the user

If GPS/TRK data is unavailable in auto mode, the heading display shows `---`
with the correct source colour. It never silently falls back to MAG and pretends
GPS is active.

### 5.5 Battery budget

When the screen is off:
- GPS stream **cancelled** (SAVE mode) or foreground-service (LIVE mode, explicit opt-in).
- Compass stream **paused**.
- Stale timer **cancelled**.
- City calculations **skipped**.
- No `setState` calls from any background path.

When the screen turns on, all streams resume within one frame.

New features must not add any background CPU, sensor, or network work unless the
user has explicitly opted in (e.g. anchor mode GPS keep-alive is only active when
the anchor is deployed).

### 5.6 Screen-size safety

Every new widget that displays dynamic text must either:
(a) use `_fitFontSize()` to auto-scale, or
(b) use `overflow: TextOverflow.ellipsis`, or
(c) be wrapped in a `Flexible`/`Expanded` that prevents unconstrained growth.

Static layout testing against both mandatory resolutions (360×800 dp and
411×914 dp) in portrait and landscape is required before merging any layout
change.

### 5.7 XML and structured data

Never use regex to parse XML or any structured format. Use the `xml` package
(`XmlDocument.parse()`) for GPX import/export. Entity references, CDATA sections,
comments, and namespaces are handled correctly only by a proper parser.

### 5.8 Anti-misclick for safety-critical actions

Any action that:
- Activates an alarm system (anchor alarm)
- Clears a safety marker (MOB)
- Changes GPS mode

must require a deliberate gesture (long-press or 3-second hold) that cannot
be triggered by casual contact with the screen during driving or sailing.

### 5.9 Tunable constants live in one config per language

Values a developer or field operator might **adjust to tune behaviour** — GPS
cadence, alarm thresholds, debounce windows, audio parameters, display
thresholds — are named constants in a dedicated, feature-namespaced config:

- Dart: `lib/config/tuning.dart` (`GpsTuning`, `DisplayTuning`).
- Kotlin: `Tuning.kt` (`Tuning.Anchor`, `Tuning.Gps`, `Tuning.Audio`).

This is the "design-tokens / app-config" pattern: tuning knobs are *discoverable
and adjustable in one place* instead of buried as magic numbers in logic. The
rule of thumb:

- **Tunable knob an operator/dev would turn** → the config file.
- **Implementation-internal constant** (only meaningful to one class, not a knob)
  → keep it co-located with that class as a `private const` for cohesion.

Never inline a magic number for a tunable value; reference the named constant.

**`config/` vs `settings/` — two different kinds of value, deliberately split:**

| | `lib/config/` | `lib/settings/` |
|---|---|---|
| What | Developer tuning constants | User-facing preferences |
| Who changes it | A developer, in code | The end user, in the app |
| When | Compile time (rebuild to change) | Runtime |
| Persisted? | No — it's source | Yes — via `GetStorage` |
| Example | GPS interval, alarm debounce | speed unit, coordinate format, day/night |

They are separate because they have different audiences, lifecycles, and storage.
Mixing them would put "things only a developer edits" next to "things the user
toggles," which is the low-cohesion grouping the layering rules exist to prevent.
The split also makes adding code intuitive: a new threshold goes to `config/`, a
new user toggle goes to `settings/` — no judgement call. (Unit *types* such as
`SpeedUnit` stay with their domain in `utils/formatting.dart`; `settings/` holds
the user's persisted *choice* of display modes.)

### 5.10 Cross-language constants must be guarded, not trusted

Dart and Kotlin cannot share a compile-time constant. Where a value MUST agree
across the boundary (the anchor GPS-loss timings live in both the Dart spec
`anchor_math.dart` and the native authority `Tuning.kt`), do **not** rely on
humans keeping them in sync — add a **guard test** that reads the other
language's source and asserts equality (`test/tuning_sync_test.dart`). Prefer
designing the duplication away entirely: the native side is the single runtime
authority for the alarm, and Dart reads results from it (the snapshot) rather
than recomputing, so the only shared values are the spec thresholds the guard
test pins.

---

## 6. Module Structure

```
lib/
├── main.dart                    # App root; stateful theme (day/night aware)
├── config/
│   └── tuning.dart              # Dart tunables: GPS cadence, display thresholds (§5.9)
├── controllers/
│   └── sensor_lifecycle.dart    # Owns GPS/compass/tick subscriptions + lifecycle (no BuildContext)
├── theme/
│   └── palette.dart             # ALL colour constants (kD*/kN*) + Palette resolver (§4)
├── settings/
│   └── display_settings.dart    # Persisted display prefs (clock, coord/locator/heading modes)
├── models/
│   ├── city.dart                # City + port data model (immutable fields)
│   └── waypoint.dart            # Waypoint (mutable name/lat/lon, persistent ID)
├── screens/
│   ├── home_screen.dart         # Primary dashboard (large; see §10 for split plan)
│   ├── waypoints_screen.dart    # Waypoint list + GPX import/export + anchor setup
│   ├── about_screen.dart        # Legal notices + open-source licences
│   └── debug_screen.dart        # 4-tab sensor/GPS/heading/locator debug view
├── services/
│   ├── anchor_service.dart      # Anchor presenter: config + polled snapshot (see §7.1)
│   ├── city_service.dart        # Spatial grid lookup (city and port datasets)
│   ├── declination_service.dart # WMM magnetic declination via Android GeomagneticField
│   ├── environment_service.dart # EventChannel wrapper for sensor stream
│   ├── overlay_service.dart     # Floating-compass overlay controller (see §9)
│   └── waypoint_service.dart    # MOB + nav waypoints; GPX import with dedup + undo
└── utils/
    ├── anchor_math.dart         # Pure anchor alarm level SPEC (unit-tested; native is authority)
    ├── coordinate_utils.dart    # DDM / DD / DMS + Maidenhead encode/decode
    ├── formatting.dart          # Speed / distance / altitude / elapsed formatting (unit-tested)
    ├── geo_utils.dart           # Haversine distance + bearing
    ├── gpx_utils.dart           # GPX 1.1 parse (xml package) + build (XmlBuilder)
    ├── mgrs_utils.dart          # MGRS encode/decode
    ├── track_bearing.dart       # Smoothed track bearing from spatial point buffer
    ├── units.dart               # Barrel: re-exports palette + formatting + display_settings
    └── waypoint_import.dart     # Pure GPX import dedup/rename planner (unit-tested)

android/app/src/main/kotlin/.../
    ├── MainActivity.kt          # Flutter channels (thin bridges)
    ├── Tuning.kt                # Native tunables: anchor thresholds, GPS cadence, audio (§5.9)
    ├── AnchorController.kt      # Single authority: level logic + latching state machine (object)
    ├── AnchorAlarmManager.kt    # Process-singleton hardware driver (MODE_STATIC seamless audio)
    ├── AnchorMonitorService.kt  # Foreground service: GPS feed + notification
    ├── BootReceiver.kt          # Restarts anchor monitor after reboot
    ├── OverlayService.kt        # Foreground service hosting the floating overlay
    └── OverlayView.kt           # Native custom-View compass for the overlay
```

`units.dart` is a backwards-compatible **barrel** — its contents were split by
concern into `theme/palette.dart`, `utils/formatting.dart`, and
`settings/display_settings.dart`. Prefer importing the specific file in new code.

### Module boundaries

| Module | May depend on | Must not depend on |
|---|---|---|
| `config/`, `theme/`, `settings/` | Dart core, `flutter` (Color/GetStorage) | Services, screens, widgets |
| `models/` | Dart core only | Services, screens, widgets |
| `utils/` | Dart core, `xml`, `config/`/`theme/`/`settings/` | Services, models, screens |
| `services/` | `models/`, `utils/`, `flutter/services` | Screens, widgets |
| `controllers/` | `config/`/`utils/`, platform plugins | Screens, widgets, `BuildContext` |
| `screens/` | All of the above | Nothing outside `lib/` |

Services are plain Dart singletons with no Flutter widget dependencies. A
`controller` is instance-scoped (owned by one widget) and may hold platform
subscriptions/timers, but — like a service — has **no `BuildContext`** and does no
layout; the owning screen passes it callbacks. Screens are the only layer that
touches `BuildContext`, `setState`, and `Navigator`.

---

## 7. Alarm & Safety Systems

### 7.1 Single-authority rule (CRITICAL)

There must be exactly **one** component that computes the anchor alarm level and
**one** that drives the hardware, per process.  Field testing exposed a class of
bug — audio "breakup" (rapid start/stop) — caused by two `AnchorAlarmManager`
instances (one in `MainActivity`, one in `AnchorMonitorService`) each requesting
`AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE` and evicting the other.

The architecture that prevents this:

| Component | Role |
|---|---|
| `AnchorAlarmManager` (Kotlin) | **Process singleton** (`getInstance`). The only object that touches `AudioTrack`, the vibrator, the torch, and the wake lock. |
| `AnchorController` (Kotlin `object`) | The single authority for level computation + state. Owns the one alarm manager. Both the service and `MainActivity` delegate here. |
| `AnchorMonitorService` (Kotlin) | Foreground service: GPS feeder + notification owner. Feeds positions/ticks into `AnchorController`. Launches the activity on alarm escalation. |
| `AnchorService` (Dart) | **Pure presenter.** Holds persisted config, polls `getAnchorSnapshot` once per second for display, drives the strobe overlay. Never calls alarm hardware directly. |

The Dart side NEVER drives the alarm hardware. If it did, it would be a second
authority and the dual-instance conflict would return.

### 7.2 Anchor alarm guarantee

The alarm must be audible in all of these states:
- silent / muted, Do Not Disturb, screen locked, **screen on with another app
  in focus** (this was the regression), volume at 0.

Implementation in `AnchorAlarmManager`:
- `AudioTrack` (never `ToneGenerator` — it skips when the screen is on or another
  stream holds focus).
- `STREAM_ALARM` forced to max before play; `USAGE_ALARM` bypasses DND priority-only.
- Exclusive audio focus is **held until stop()**; the focus-change listener is a
  no-op so transient focus loss never self-silences the alarm.
- **Speaker only, single source.** Exactly one `AudioTrack`, forced to the
  built-in speaker (`setPreferredDevice(TYPE_BUILTIN_SPEAKER)`). The alarm must
  sound in the physical space regardless of any connected headphones/BT/USB —
  routing it (or a copy) to headphones is pointless and a source of conflicts, so
  we never do. (An earlier dual-output design was removed for this reason.)

### 7.3 Alarm audio design

- **Playback engine: `AudioTrack` in `MODE_STATIC`, pre-loaded and hardware-looped
  (`setLoopPoints`).** The siren is a 2 s buffer rendered ONCE and cached; `play()`
  starts it immediately (no warm-up lag) and there is no feeder thread that could
  underrun (no glitches/break-up). The loop is amplitude-enveloped to zero over its
  first/last 6 ms so the seam is click-free. The one-shot warning ping uses the
  same pre-loaded `MODE_STATIC` path — a `MODE_STREAM` play-then-write dropped the
  short ping to a cold-track warm-up race.
- **Warning:** a single soft 880 Hz ping (250 ms, faded), played ONCE every 8 s —
  a gentle one-shot nudge, not a continuous tone. Audible at volume 0.
- **Alarm:** continuous siren — two tones a **tritone (√2 ≈ 1.414) apart**
  wailing 400 → 1200 → 400 Hz across the loop, summed and hard-clipped. The
  tritone is the most dissonant Western interval; the result is deliberately harsh.
  Max volume, continuous.
- **Test:** the same alarm timbre at 10 % volume from the speaker, toggled on/off
  by the setup-sheet button (auto-stops after 60 s).
- All audio parameters (frequencies, loop length, volumes, intervals) are named
  constants in `Tuning.Audio` — never inline them (§5.9).

### 7.4 Persistence & survival

- Config (lat/lon/radius/warnFrac) is persisted in both GetStorage (Dart) and the
  service's SharedPreferences (Kotlin). On `START_STICKY` restart the service
  restores from prefs and resumes with zero Flutter involvement.
- On app relaunch, `AnchorService.loadFromStorage()` restores config and the home
  screen re-syncs the live snapshot via `refresh()`, so an in-progress alarm shows
  its overlay immediately.
- On alarm escalation while only the background service is alive, the service
  launches `MainActivity` (full-screen intent) so the silence UI appears.

### 7.5 GPS reliability when stationary (CRITICAL — false alarms make it unusable)

The hard requirement: a **stationary boat with a working GPS must never raise a
false "GPS lost" alarm**, while a genuine loss still escalates. The design that
guarantees this:

- **Liveness is decoupled from precision.** *Any* fix, at *any* accuracy, proves
  the receiver is alive and resets the loss timer. A working GPS keeps delivering
  fixes when stationary (measurement noise alone yields a new fix each epoch); it
  only goes silent when the fix is genuinely lost. So "GPS lost" is decided purely
  by liveness — no fix at all for a sustained time. (An earlier design wrongly
  required *accurate* fixes for liveness, so an obstructed phone whose accuracy
  drifted looked "lost" while GPS worked — the false-alarm bug.)
- **Distance vs. liveness are separate.** Distance updates only from a fix accurate
  to within `max(radius, 50 m)` — lenient so a real drag is never missed, but
  clearly-broken fixes can't move it. Liveness ignores accuracy.
- **Debounce + hysteresis.** A position level must persist (warn 4 s, alarm 8 s)
  before escalating, so a lone spurious fix can't raise — or, since ALARM latches,
  lock in — a false alarm.
- **Two feeds, GPS only.** The native service runs `GPS_PROVIDER` at 1 Hz / 0 m
  under a `PARTIAL_WAKE_LOCK` (defeats Doze); the foreground also forwards fused
  geolocator fixes via `forwardPosition`. No `NETWORK_PROVIDER` (its coarse fixes
  add only noise). Escalation: 60 s → warning, 180 s → alarm.
- All thresholds are named constants in `Tuning.Anchor` (§5.9).

### 7.6 The native AnchorController is the single level authority

Level computation lives natively in `AnchorController.kt` (latching state machine
with hysteresis, debounce, liveness-based GPS loss, low-battery escalation). It is
the **only** runtime authority — the Dart side reads the computed level from the
1 Hz snapshot (`getAnchorSnapshot`) and never recomputes.

`lib/utils/anchor_math.dart` (`AnchorMath`) is the pure, unit-tested **spec** of
the core contract (position/GPS/battery → level, highest wins); the native side
implements a superset of it. The only values shared across the language boundary
are the GPS-loss timings, duplicated in `AnchorMath` and `Tuning.Anchor`. They are
kept honest by `test/tuning_sync_test.dart`, which reads `Tuning.kt` and asserts
equality (§5.10) — divergence fails the build, so it can never drift silently.

### 7.7 Battery budget for alarms

- The background service is started **only** when an anchor is deployed and
  stopped the moment it is lifted (or on `START_STICKY` restart when prefs show
  no active anchor → immediate `stopSelf`).
- Battery monitoring, GPS keep-alive, and snapshot polling run **only** inside the
  `if (AnchorService.instance.isActive)` branch of the 1 Hz stale timer — zero
  added cost when not anchoring.
- When not anchoring the app's baseline budget (§5.5) is unchanged.

---

## 8. Testing

Tests should **assert real behaviour and invariants** and give a clear failure
message — not chase a coverage number. The bar: a test should fail loudly if a
change breaks something a user would notice or a safety rule the constitution
sets. Pure, deterministic logic lives in `lib/utils/` (and `theme/`) and is tested
with no I/O, no platform channels, no `GetStorage`. This is why pure logic is
extracted (e.g. `WaypointImporter`, `AnchorMath`, `formatting`).

The test suite (`test/`) MUST stay green before any release build:
- `anchor_math_test.dart` — every alarm threshold + "highest level wins" (safety-critical).
- `geo_utils_test.dart` — haversine + bearing against known values.
- `gpx_utils_test.dart` — track-point exclusion, entity decoding, round-trip.
- `waypoint_import_test.dart` — duplicate/rename rules incl. the worked example.
- `palette_test.dart` — **enforces the pure-red night rule** (every night constant
  and every `Palette` night role has g = 0, b = 0) + `Palette` resolver behaviour.
- `formatting_test.dart` — speed/distance/altitude/elapsed unit conversions & rounding.
- `tuning_sync_test.dart` — guards the Dart↔Kotlin shared thresholds (§5.10).

New safety-relevant logic must ship with tests. Prefer extracting a pure function
over testing through a widget or platform channel. When a rule in this document is
machine-checkable (the night palette, the threshold sync), back it with a test so
the rule is enforced, not just documented.

---

## 9. Floating compass overlay

A small always-on-top compass shown over other apps (maps, messaging) so heading
and the nearest city / anchor status stay glanceable without switching back.

**Architecture (native, no second Flutter engine):**
- `OverlayView` (Kotlin custom `View`) draws a compact compass + numeric heading
  + one coloured info line per active POI (city / waypoint / MOB / anchor), each as
  a croppable label plus an always-visible heading+distance value. It is rendered
  natively — a second `FlutterEngine` would cost ~30–50 MB and significant battery,
  which violates §5.5.
- `OverlayService` (foreground service, `specialUse` type) hosts the window via
  `WindowManager` + `TYPE_APPLICATION_OVERLAY`, draggable, tap-to-open-app. The
  FGS keeps the process (and the data-pushing Flutter engine) alive in background.
- `OverlayController` (Dart) handles the `SYSTEM_ALERT_WINDOW` permission flow,
  persists the user's enable intent, and pushes one data frame per update.

**Rules:**
- **Colours are pushed as ARGB ints from Dart** — the overlay never hard-codes a
  semantic colour, so the §4 palette (incl. the pure-red night rule) stays the
  single source of truth.
- **Shown only in the background.** The home screen shows it on `paused` and hides
  it on `resumed` — never drawn on top of the full dashboard.
- **Opt-in and battery-bounded.** Sensors are kept alive in the background ONLY
  when the overlay is enabled, an anchor is active, or GPS-on-lock is on
  (`keepAlive` in the lifecycle handler). When none apply, the baseline §5.5
  budget is unchanged (compass paused, GPS cancelled, timer stopped).
- Content adapts: anchor status when anchoring, else nearest city name + bearing
  + distance. Heading honours the in-app arrow/wind-rose mode.

---

## 10. Version history & refactoring direction

The app started as a proof-of-concept GPS heading display and grew iteratively
through field testing into a full maritime/radio/hiking dashboard. The architecture
reflects this history.

**Done:** colours/units/preferences split out of the old `units.dart` god-file
into `theme/palette.dart` + `utils/formatting.dart` + `settings/display_settings.dart`
(barrel kept for compatibility); a `Palette` semantic resolver replaced scattered
`dayMode ?` colour ternaries across the screens; tunables centralized into
`config/tuning.dart` + `Tuning.kt`; the anchor alarm consolidated to a single
native authority with liveness-based GPS-loss and `MODE_STATIC` audio; machine-
checkable rules (night-palette purity, cross-language threshold sync) backed by
tests.

**Decomposing `home_screen.dart` — in progress.** It is still a large
`StatefulWidget` managing a unified state machine for all navigation sensors. The
extraction is deliberately incremental (behind the existing tests, one concern at a
time, never a big-bang):

1. **Pull pure helpers into `utils/` so they can be unit-tested — DONE (first pass).**
   heading-source selection (`utils/heading_source.dart`, `heading_source_test.dart`);
   the `fitFontSize` layout helper (`utils/text_fit.dart`, `text_fit_test.dart`);
   date/time/stale/population formatters (`utils/formatting.dart`,
   `formatting_test.dart`). (Note: `_bearingMarkers` is view-model assembly that
   mixes services + `Palette`, not pure geometry — its math already lives in the
   tested `geo_utils.bearing`, so it stays in the widget.)
2. **Move self-contained classes/widgets to their own files — DONE (first pass).**
   The four `CustomPainter`s → `widgets/compass_painters.dart` (now public); the
   city/port detail bottom sheet → `widgets/city_detail_sheet.dart`
   (`CityDetailSheet`); the full-screen alarm splash → `widgets/anchor_alarm_overlay.dart`
   (`AnchorAlarmOverlay`, parameterised by the two animation controllers + `dayMode`).
   Each took its data via constructor (or the global `AnchorService`), so the moves
   were mechanical and behaviour-preserving. Also extracted the reusable
   `RelBearingArrow` (arrow + relative-direction ring, used by 4 cards) to
   `widgets/rel_bearing_arrow.dart`, and the GPS-cadence selection to a pure tested
   `GpsTuning.profile()` (`gps_profile_test.dart`). `home_screen.dart` shrank ~3360 →
   ~2340 lines; the suite is now 98 tests.

   **Guiding line for what's safe to extract now:** presentational widgets and pure
   functions whose correctness is verifiable by a quick feature check. The lifecycle
   pieces below are deferred precisely because their regressions surface only over a
   long run / real driving, which is expensive to verify.
3. **Extract the sensor lifecycle into a controller — DONE.** `SensorLifecycle`
   (`controllers/sensor_lifecycle.dart`) owns the GPS position stream, compass
   subscription, and 1 Hz tick timer plus their start/stop/pause/resume lifecycle.
   It holds NO sensor state and does NO orchestration — the widget passes its event
   handlers + a `buildSettings` callback, so the data flow and ordering are identical
   to the old inline subscriptions (deliberately the safe form: it moves the
   *plumbing*, not the order-sensitive handler bodies). Verify with the lifecycle
   manual checks (screen-off release, resume, GPS-on-lock, anchor across lifecycle).
4. **Display view-model + per-section widgets — IN PROGRESS.** Introduced the
   view-model (`widgets/dashboard_vm.dart`): `DashboardVm` is an immutable per-frame
   snapshot of the display state (built by `_buildVm`), and `DashboardActions`
   bundles the action callbacks (built once). Sections take `(vm, actions)` instead
   of a dozen parameters. Extracted so far: `AnchorCard`, `CoordsSection`
   (portrait/landscape + locator/alt/clock rows), `CitySection` (portrait/landscape/
   compact). Sections derive trivial palette colours from `vm.dayMode`; the VM
   carries only colours needing screen-side logic (heading source, city tier).
   `home_screen.dart` is now ~1970 lines (from ~3360).

   **Remaining:** heading (move its `ValueListenableBuilder`s + `_lockModeWidget`
   into the widget), nav waypoint, and MOB. Nav/MOB use the hold-to-clear gesture,
   so `DashboardActions` needs `startClear(WptHoldTarget)`/`cancelClear` and the VM
   needs `holdTarget`/`clearProgress` (then retire the screen-private `_WptHoldTarget`
   in favour of the public one in `dashboard_vm.dart`). Each section is verifiable by
   a quick visual check in portrait + landscape on the small screen.

Do not add unrelated concerns to `home_screen.dart` in the meantime; new sections
belong in their own widget/file, and new pure logic in a tested `utils/` module.
