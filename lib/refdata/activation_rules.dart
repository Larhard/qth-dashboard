/// Activation essentials per program + the summit activation-zone estimate.
/// Pure Dart.
///
/// These are SHORT REMINDERS for use in the field, not the full rules — every
/// program's own rules page is authoritative (linked from the detail sheet).
/// Entries whose numbers could not be confirmed from an official page carry
/// `verified: false` and are shown with a "check rules" hint instead of a number.
library;

import '../config/tuning.dart';
import '../models/poi_category.dart';

enum ZoneKind {
  /// Within N metres vertically of the summit (SOTA, GMA).
  vertical,

  /// Within N metres horizontally of the object (bunker, castle, tower).
  radius,

  /// Inside the reference's boundary (parks, reserves, lakes).
  insideArea,

  /// On an island of the group (IOTA).
  onIsland,

  /// Unknown / not confirmed.
  unknown,
}

class ActivationRule {
  final ZoneKind zone;

  /// Metres for [ZoneKind.vertical] / [ZoneKind.radius]; 0 otherwise.
  final int zoneMeters;

  /// Minimum QSOs for a valid activation; null = no fixed minimum / unknown.
  final int? minQsos;

  /// QSOs may be accumulated over several sessions (WWFF).
  final bool cumulative;

  /// References carry award points (SOTA).
  final bool hasPoints;

  /// One-line reminder shown in the detail sheet.
  final String note;

  /// Official rules page.
  final String rulesUrl;

  /// False when the numbers above could not be confirmed from an official page.
  final bool verified;

  /// [ZoneKind.radius] only: the radius is measured from the reference POINT
  /// (bunker, tower, castle), so distance alone decides it. False when it is
  /// measured from something we don't have (LLOTA: the water's edge).
  final bool zoneFromPoint;

  const ActivationRule({
    required this.zone,
    this.zoneMeters = 0,
    this.minQsos,
    this.cumulative = false,
    this.hasPoints = false,
    required this.note,
    required this.rulesUrl,
    this.verified = true,
    this.zoneFromPoint = true,
  });
}

/// Rules for each reference program. Keep in sync with the official pages.
const activationRules = <PoiCategory, ActivationRule>{
  PoiCategory.sota: ActivationRule(
    zone: ZoneKind.vertical,
    zoneMeters: 25,
    minQsos: 4,
    hasPoints: true,
    note: 'Operate within 25 m (vertical) of the summit, portable power, no vehicle. '
        '1 QSO makes the activation valid; 4 QSOs to score activator points.',
    rulesUrl: 'https://www.sota.org.uk/Joining-In/Rules-and-Guidelines',
  ),
  PoiCategory.pota: ActivationRule(
    zone: ZoneKind.insideArea,
    minQsos: 10,
    note: 'Operate from inside the park boundary. 10 QSOs in one UTC day for a valid activation.',
    rulesUrl: 'https://docs.pota.app/docs/rules.html',
  ),
  PoiCategory.wwff: ActivationRule(
    zone: ZoneKind.insideArea,
    minQsos: 44,
    cumulative: true,
    note: 'Operate from inside the area. 44 QSOs for a valid activation '
        '(may be accumulated over several activations).',
    rulesUrl: 'https://wwff.co/rules-faq/',
  ),
  PoiCategory.iota: ActivationRule(
    zone: ZoneKind.onIsland,
    note: 'Operate from an island of the group. Each QSO credits chasers; '
        '100 QSOs for the activator to claim the group.',
    rulesUrl: 'https://www.iota-world.org/info/rules.html',
  ),
  PoiCategory.gma: ActivationRule(
    zone: ZoneKind.vertical,
    zoneMeters: 25,
    minQsos: 4,
    hasPoints: true,
    note: 'Operate within 25 m (vertical) of the summit. 4 QSOs for a valid '
        'activation. SOTA summits also count for GMA.',
    rulesUrl: 'https://www.gma.rocks',
  ),
  PoiCategory.llota: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 200,
    minQsos: 10,
    zoneFromPoint: false,
    note: "Operate within 200 m of the water's edge. "
        '10 QSOs for a valid activation.',
    rulesUrl: 'https://llota.app',
  ),
  PoiCategory.bota: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 1000,
    minQsos: 25,
    note: 'Operate within 1 km of the bunker (some national schemes differ). '
        '25 QSOs on HF, or 5 if VHF/UHF only.',
    rulesUrl: 'https://wwbota.org',
  ),
  PoiCategory.tota: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 200,
    minQsos: 13,
    note: 'Operate within 200 m of the tower (or from it). 13 QSOs on HF, '
        '3 on VHF/UHF; points are scored per QSO.',
    rulesUrl: 'https://www.rozhledny.eu',
  ),
  PoiCategory.wca: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 1000,
    minQsos: 50,
    note: 'Operate within 1 km of the castle. 50 QSOs for activator credit. '
        'Only castles with known coordinates are listed.',
    rulesUrl: 'https://wcagroup.org',
  ),
  PoiCategory.hema: ActivationRule(
    zone: ZoneKind.vertical,
    zoneMeters: 25,
    minQsos: 4,
    note: 'Operate within 25 m (vertical) of the summit. 4 QSOs with different '
        'operators; 1 point per qualifying activation.',
    rulesUrl: 'https://www.hema.org.uk/rulesWebsite.jsp',
  ),
  PoiCategory.sbw: ActivationRule(
    zone: ZoneKind.unknown,
    hasPoints: true,
    note: 'Saxony mountain contest (DARC Sachsen). Check the SBW rules for the '
        'activation zone and QSO minimum.',
    rulesUrl: 'https://www.dl2lto.de',
    verified: false,
  ),
  PoiCategory.zlota: ActivationRule(
    zone: ZoneKind.unknown,
    note: 'Rules depend on the asset type (hut, lake, island, park, volcano, lighthouse).',
    rulesUrl: 'https://ontheair.nz',
    verified: false,
  ),
  PoiCategory.gia: ActivationRule(
    zone: ZoneKind.onIsland,
    minQsos: 4,
    note: 'Operate from the island. 4 QSOs with different calls when portable '
        '(25 with mains power, generator, building or car); 1 point per island.',
    rulesUrl: 'https://www.gma.rocks/doc/GI-EN-2018%20v1.00.pdf',
  ),
  PoiCategory.mota: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 1000,
    minQsos: 4,
    note: 'Within 1 km of the mill and in line of sight. 4 QSOs portable/battery '
        '(33 with mains or vehicle power); 10 GMA Triathlon points.',
    rulesUrl: 'https://www.gma.rocks/doc/MOTA_Rules.pdf',
  ),
  PoiCategory.siota: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 1000,
    minQsos: 3,
    cumulative: true,
    note: 'Within 1 km of the silo. 3 QSOs incl. at least one on HF '
        '(may be accumulated over several activations).',
    rulesUrl: 'https://www.silosontheair.com/rules.html',
  ),
  PoiCategory.arlhs: ActivationRule(
    zone: ZoneKind.radius,
    zoneMeters: 1000,
    note: 'Within 1 km of the light (or within sight of it where that is '
        'impractical). No fixed QSO minimum.',
    rulesUrl: 'https://arlhs.com/faq/what-is-meant-by-activating-a-light/',
  ),
  PoiCategory.wlota: ActivationRule(
    zone: ZoneKind.onIsland,
    note: 'Operate from the same island as the lighthouse (no /MM). No fixed QSO '
        'minimum; 100 QSOs to validate a new reference.',
    rulesUrl: 'https://wlota.com/index.php/awards/rules-award',
  ),
};

/// ZLOTA rules per asset type, keyed by reference prefix. Derived from
/// ontheair.nz asset-type settings (min QSOs, distance buffer, boundary),
/// not from a rules page — hence `verified: false`.
const _zlotaRules = <String, ActivationRule>{
  'ZLH/': ActivationRule(
      zone: ZoneKind.radius, zoneMeters: 100, minQsos: 1,
      note: 'Hut: within 100 m of the hut. 1 QSO.',
      rulesUrl: 'https://ontheair.nz', verified: false),
  'ZLL/': ActivationRule(
      zone: ZoneKind.radius, zoneMeters: 500, minQsos: 2, zoneFromPoint: false,
      note: "Lake: within 500 m of the lake's boundary. 2 QSOs.",
      rulesUrl: 'https://ontheair.nz', verified: false),
  'ZLI/': ActivationRule(
      zone: ZoneKind.onIsland, minQsos: 5,
      note: 'Island: operate on the island. 5 QSOs.',
      rulesUrl: 'https://ontheair.nz', verified: false),
  'ZLP/': ActivationRule(
      zone: ZoneKind.insideArea, minQsos: 4,
      note: 'Park: operate inside the park boundary. 4 QSOs.',
      rulesUrl: 'https://ontheair.nz', verified: false),
  'ZLV/': ActivationRule(
      zone: ZoneKind.unknown, minQsos: 4,
      note: 'Volcano: 4 QSOs; check the rules for the activation zone.',
      rulesUrl: 'https://ontheair.nz', verified: false),
  'ZLB/': ActivationRule(
      zone: ZoneKind.unknown, minQsos: 4,
      note: 'Lighthouse: within sight of the light. 4 QSOs.',
      rulesUrl: 'https://ontheair.nz', verified: false),
};

/// The rule that applies to [ref] of category [c]. Programs whose rules vary
/// by reference type (ZLOTA) are resolved per reference; others per program.
ActivationRule? ruleFor(PoiCategory c, [String? ref]) {
  if (c == PoiCategory.zlota && ref != null && ref.length >= 4) {
    return _zlotaRules[ref.substring(0, 4)] ?? activationRules[c];
  }
  return activationRules[c];
}

/// Radius-zone check for point objects (bunker, tower, castle): true when the
/// GPS position is within the zone. Null when not applicable. GPS horizontal
/// error (±5–10 m) is small next to these radii, but it is still a reminder.
bool? inRadiusZone(ActivationRule rule, double distKm) =>
    rule.zone == ZoneKind.radius && rule.zoneFromPoint && rule.zoneMeters > 0
        ? distKm * 1000 <= rule.zoneMeters
        : null;

/// Activation-zone estimate for vertical-zone programs (SOTA): how far the user
/// is above/below the summit, from GPS MSL altitude.
///
/// Returns null when not applicable (no summit altitude, no GPS altitude, or
/// farther than [maxDistKm] — being "high enough" on another hill means nothing).
/// [likelyInZone] is only an estimate: GPS altitude is typically ±10–20 m, so the
/// UI labels it as approximate.
({double deltaM, bool likelyInZone})? estimateVerticalZone({
  required int summitAltM,
  required double gpsAltM,
  required double distKm,
  required int zoneMeters,
  double maxDistKm = PoiTuning.summitZoneMaxDistKm,
}) {
  if (summitAltM <= 0 || zoneMeters <= 0 || distKm > maxDistKm) return null;
  if (!gpsAltM.isFinite || gpsAltM == 0) return null; // 0 = no altitude reported
  final delta = gpsAltM - summitAltM;
  return (deltaM: delta, likelyInZone: delta >= -zoneMeters);
}
