import 'package:flutter/material.dart' show Color, Colors;
import '../models/poi_category.dart';

/// The app's single colour source of truth.
///
/// Two palettes, two different design principles:
///   • NIGHT (`kN*`) is a pure-red BRIGHTNESS RAMP — every value has green = 0x00
///     and blue = 0x00 (it lies on #000000 → #FF0000).  This is non-negotiable:
///     any green/blue light destroys night-adapted (rod) vision.  Prominence is
///     expressed by brightness alone (kN0 brightest … kN4 dimmest).
///   • DAY (`kD*`) is SEMANTIC — hue encodes data type (green = GPS, amber = MGRS,
///     cyan = port, red = emergency, orange = nav …).
///
/// Because the two principles differ, the day→night mapping is CONTEXTUAL: the
/// same day hue maps to whichever ramp brightness fits its prominence in that
/// spot.  [Palette] centralizes those decisions as named semantic roles so the
/// rules live in ONE place instead of scattered `dayMode ? kD.. : kN..` ternaries.
///
/// RULES:
///   • No raw `Color(0x…)` literals anywhere outside this file.
///   • Resolve colours through a [Palette] (`Palette.of(dayMode).textPrimary`).
///     Use [Palette.pick] only for a genuine one-off the named roles don't cover.
///   • Every value a [Palette] returns in night mode is a `kN*` (or Colors.black /
///     Colors.transparent) — so night-vision safety is enforced by construction.

// ── Night-mode palette (STRICT pure red — G=00, B=00) ───────────────────────
const kN0     = Color(0xFFFF0000); // brightest  — emergency / destructive / north
const kN1     = Color(0xFFCC0000); // primary    — main text, active icons
const kN2     = Color(0xFF9A0000); // secondary  — labels, sub-icons
const kN3     = Color(0xFF770000); // tertiary   — metadata, captions
const kN4     = Color(0xFF4A0000); // very dim   — hints, disabled
const kNBg    = Color(0xFF1A0000); // tile / card background
const kNDiv   = Color(0xFF250000); // dividers, borders
const kNSheet = Color(0xFF0A0000); // modal / bottom-sheet background

// ── Day-mode palette (semantic — hue = data type) ───────────────────────────
// Neutral text hierarchy (on dark panel surfaces)
const kDFg0 = Color(0xFFFFFFFF); // primary   — headings, primary values
const kDFg1 = Color(0xFFEEEEEE); // secondary — sub-values
const kDFg2 = Color(0xFFCCCCCC); // tertiary  — speed, altitude, accuracy
const kDFg3 = Color(0xFF888888); // dim       — labels, inactive icons
const kDFg4 = Color(0xFF666666); // very dim  — hints, disabled text

// Heading / GPS — green family (also: IARU locator, UTC clock, north marker)
const kDGps  = Color(0xFF55DD55); // GPS heading · IARU locator · UTC time
const kDGpsL = Color(0xFF3DBF3D); // GPS / locator sub-label

// TRK (smoothed track bearing) — clear golden yellow, distinct from GPS green
const kDTrk  = Color(0xFFDDCC00);

// Emergency / MOB — red family
const kDEmg  = Color(0xFFFF3333); // MOB name, arrow, highlight
const kDEmgS = Color(0xFFDD3333); // MOB coordinates (softer red)
const kDEmgBg= Color(0xFFB71C1C); // MOB card background

// Stale / warning indicator — orange-red
const kDStale= Color(0xFFFF7043);

// Navigation waypoint — deep-orange family
const kDNav  = Color(0xFFFF6E40); // nav waypoint name / arrow
const kDNavL = Color(0xFFFF8F00); // nav waypoint sub-text / label

// MGRS · local time · amber accents — orange-amber family
const kDAmb  = Color(0xFFFFA726); // MGRS value, local time, save-lock
const kDAmbs = Color(0xFFE65100); // MGRS label, local-time label, large-city sub

// City location tiers
const kDCityL = Color(0xFFFF9800); // large city — orange
const kDCityP = Color(0xFFFFD740); // precise city — amber (also: warnings)
const kDCityD = Color(0xFFC6FF00); // detailed city — lime
const kDCityDS= Color(0xFFAEEA00); // detailed city sub — lime-dark

// Port / water features — cyan family
const kDPort  = Color(0xFF00E5FF); // port name, live-lock badge
const kDPortL = Color(0xFF00ACC1); // port sub-text, live-lock label

// UI chrome (on the app's dark-panel surface)
const kDDiv    = Color(0xFF1A1A1A); // dividers, separators
const kDBrd    = Color(0xFF333333); // input / tile borders
const kDFoc    = Color(0xFF555555); // focused input border
const kDSheetBg= Color(0xFF111111); // modal / bottom-sheet background
const kDSnackBg= Color(0xFF1C1C1C); // floating snackbar background

// Amateur-radio "on the air" programs — one distinct hue per program so the
// nearby-POI list reads at a glance (the text tag still names the category).
const kDSota  = Color(0xFFB388FF); // violet          — summits
const kDGma   = Color(0xFFEA80FC); // magenta         — GMA mountains
const kDPota  = Color(0xFF1DE9B6); // teal            — parks
const kDWwff  = Color(0xFF82B1FF); // periwinkle      — flora & fauna
const kDIota  = Color(0xFFF48FB1); // pink            — islands
const kDLlota = Color(0xFF448AFF); // royal blue      — lakes & lagoons
const kDBota  = Color(0xFFBCAAA4); // concrete tan    — bunkers
const kDTota  = Color(0xFFB0BEC5); // blue-grey       — towers
const kDWca   = Color(0xFFD7A86E); // castle stone    — castles
const kDHema  = Color(0xFFD1C4E9); // pale violet     — hills (summit family)
const kDSbw   = Color(0xFFCE93D8); // orchid          — Saxony summits (summit family)
const kDZlota = Color(0xFF69F0AE); // fern green      — New Zealand
const kDGia   = Color(0xFFF8BBD0); // pale pink       — GMA islands (island family)
const kDMota  = Color(0xFFFFAB91); // brick           — mills
const kDSiota = Color(0xFFC5E1A5); // grain green     — silos
const kDArlhs = Color(0xFFFFF176); // beacon yellow   — lighthouses (ARLHS)
const kDWlota = Color(0xFFE6EE9C); // pale lime       — lighthouses (WLOTA)

// Shelter-quality "good" tier — mid green between kDGps and kDTrk (port info)
const kDShelterGood = Color(0xFF9CCC65);

// Debug-screen surfaces (4-tab sensor view only)
const kDDebugPanel  = Color(0xFF0A0A0A); // near-black tab panel background
const kDDebugDotOld = Color(0xFF2A3A2A); // faded "old" track dot

// Day-only tinted form surfaces (waypoint editor)
const kDFormBg = Color(0xFF1A2A1A); // green-tinted text-field background
const kDSaveBg = Color(0xFF1A3A1A); // green-tinted save-button background

// Maidenhead locator precision tiers (debug / locator display only)
const kDGpsM6  = Color(0xFF69F0AE); // 6-char Maidenhead (~12 km)
const kDGpsM4  = Color(0xFF80CBC4); // 4-char Maidenhead (field)

// Emergency card border ring — shown during hold-to-clear animation
const kDEmgRing    = Color(0xFF4A1515); // day: active progress ring
const kDEmgRingDim = Color(0xFF3D1212); // day: idle ring
const kNEmgRing    = Color(0xFF2A0000); // night: active progress ring (pure red)
const kNEmgRingDim = Color(0xFF1A0000); // night: idle ring (pure red)
const kDEmgArc     = Color(0xFFFF6666); // day: arc animation end colour
const kNEmgArc     = Color(0xFFAA0000); // night: arc animation end colour (pure red)

/// Resolves a semantic colour role to a concrete colour for the current mode.
///
/// Construct cheaply per build: `final p = Palette.of(_dayMode);`.  Each getter
/// is the SINGLE definition of that role's day and night colour — change it here
/// and every screen follows.  Night values are always `kN*` (or black), so the
/// pure-red rule cannot be violated by a call site.
class Palette {
  final bool day;
  const Palette(this.day);

  // Two const singletons → resolving a Palette never allocates, so it is free to
  // call `Palette.of(dayMode)` (or a `_pal` getter) anywhere, including per build.
  static const _day = Palette(true);
  static const _night = Palette(false);
  factory Palette.of(bool day) => day ? _day : _night;

  /// Escape hatch for a genuine one-off the named roles don't cover.  The night
  /// colour MUST be a `kN*`/black/transparent value (pure-red rule).  Prefer a
  /// named role; reach for this only when a role would be arbitrary.
  Color pick(Color dayColor, Color nightColor) => day ? dayColor : nightColor;

  // Neutral text hierarchy
  Color get textPrimary   => day ? kDFg0 : kN1;
  Color get textSecondary => day ? kDFg1 : kN2;
  Color get textTertiary  => day ? kDFg2 : kN2;
  Color get textDim       => day ? kDFg3 : kN3;
  Color get textFaint     => day ? kDFg4 : kN4;

  // Semantic data colours (day = hue, night = position on the red brightness ramp)
  Color get gps        => day ? kDGps   : kN1;
  Color get gpsLabel   => day ? kDGpsL  : kN3;
  Color get trk        => day ? kDTrk   : kN2;
  Color get emergency  => day ? kDEmg   : kN0;
  Color get nav        => day ? kDNav   : kN1;
  Color get navLabel   => day ? kDNavL  : kN3;
  Color get stale      => day ? kDStale : kN1;
  Color get amber      => day ? kDAmb   : kN2;
  Color get amberLabel => day ? kDAmbs  : kN3;
  Color get port       => day ? kDPort  : kN1;
  Color get portLabel  => day ? kDPortL : kN2;

  // Surfaces & chrome
  Color get tileBg  => day ? Colors.black : kNBg;
  Color get cardBg  => day ? kDSheetBg : kNBg;
  Color get sheetBg => day ? kDSheetBg : kNSheet;
  Color get snackBg => day ? kDSnackBg : kNBg;
  Color get divider => day ? kDDiv : kNDiv;
  Color get border  => day ? kDBrd : kNDiv;
  Color get focus   => day ? kDFoc : kN4;

  // Ink ripple / tap highlight (kept subtle; night stays on the red ramp)
  Color get rippleMuted => day ? kDFg3 : kN2;

  // Nearby-POI categories (cities, ports, ham-radio programs). Night collapses to
  // the red ramp like every other role; the category tag carries the identity.
  Color poi(PoiCategory c) => day ? _poiDay(c) : kN2;
  Color poiSub(PoiCategory c) => day ? _poiSubDay(c) : kN3;

  static Color _poiDay(PoiCategory c) => switch (c) {
        PoiCategory.cityLarge    => kDCityL,
        PoiCategory.cityRegional => kDCityP,
        PoiCategory.cityLocal    => kDCityD,
        PoiCategory.port         => kDPort,
        PoiCategory.sota         => kDSota,
        PoiCategory.gma          => kDGma,
        PoiCategory.pota         => kDPota,
        PoiCategory.wwff         => kDWwff,
        PoiCategory.iota         => kDIota,
        PoiCategory.llota        => kDLlota,
        PoiCategory.bota         => kDBota,
        PoiCategory.tota         => kDTota,
        PoiCategory.wca          => kDWca,
        PoiCategory.hema         => kDHema,
        PoiCategory.sbw          => kDSbw,
        PoiCategory.zlota        => kDZlota,
        PoiCategory.gia          => kDGia,
        PoiCategory.mota         => kDMota,
        PoiCategory.siota        => kDSiota,
        PoiCategory.arlhs        => kDArlhs,
        PoiCategory.wlota        => kDWlota,
      };

  // Sub-text keeps each city tier's established companion colour; ham programs
  // use a dimmed version of their hue.
  static Color _poiSubDay(PoiCategory c) => switch (c) {
        PoiCategory.cityLarge    => kDAmbs,
        PoiCategory.cityRegional => kDAmb,
        PoiCategory.cityLocal    => kDCityDS,
        PoiCategory.port         => kDPortL,
        _                        => _poiDay(c).withValues(alpha: 0.75),
      };

  // Hold-to-clear / progress ring animation endpoints
  Color get ringIdle   => day ? kDEmgRingDim : kNEmgRingDim;
  Color get ringActive => day ? kDEmgRing : kNEmgRing;
  Color get ringArc    => day ? kDEmgArc : kNEmgArc;
}
