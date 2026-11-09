/// Every category of point of interest the dashboard can show as "nearby".
///
/// Pure Dart (no Flutter) — shared with the `tool/fetch_refs.dart` build tool.
/// Colours live in `theme/palette.dart` (the colour source of truth); activation
/// rules in `refdata/activation_rules.dart`; download URLs in
/// `config/ref_sources.dart`.
library;

enum PoiKind { city, port, reference }

enum PoiCategory {
  // ── Places ─────────────────────────────────────────────────────────────────
  cityLarge('city_large', 'Cities — large', 'METRO', PoiKind.city),
  cityRegional('city_regional', 'Cities — regional', 'CITY', PoiKind.city),
  cityLocal('city_local', 'Towns — local', 'TOWN', PoiKind.city),
  port('port', 'Ports & marinas', 'PORT', PoiKind.port),

  // ── Amateur-radio "on the air" programs ────────────────────────────────────
  sota('sota', 'SOTA — Summits', 'SOTA', PoiKind.reference),
  gma('gma', 'GMA — Global Mountain Activity', 'GMA', PoiKind.reference),
  hema('hema', 'HEMA — Hills (HuMPs)', 'HEMA', PoiKind.reference),
  sbw('sbw', 'SBW — Saxony summits', 'SBW', PoiKind.reference),
  pota('pota', 'POTA — Parks', 'POTA', PoiKind.reference),
  wwff('wwff', 'WWFF — Flora & Fauna', 'WWFF', PoiKind.reference),
  zlota('zlota', 'ZLOTA — New Zealand', 'ZLOTA', PoiKind.reference),
  iota('iota', 'IOTA — Islands', 'IOTA', PoiKind.reference),
  gia('gia', 'GIA — GMA Islands', 'GIA', PoiKind.reference),
  llota('llota', 'LLOTA — Lakes & Lagoons', 'LLOTA', PoiKind.reference),
  bota('bota', 'BOTA — Bunkers', 'BOTA', PoiKind.reference),
  tota('tota', 'TOTA — Towers', 'TOTA', PoiKind.reference),
  wca('wca', 'COTA — Castles (WCA)', 'WCA', PoiKind.reference),
  mota('mota', 'MOTA — Mills', 'MOTA', PoiKind.reference),
  siota('siota', 'SiOTA — Silos (VK)', 'SIOTA', PoiKind.reference),
  arlhs('arlhs', 'ARLHS — Lighthouses', 'ARLHS', PoiKind.reference),
  wlota('wlota', 'WLOTA — Lighthouses', 'WLOTA', PoiKind.reference);

  /// Stable id — used for persistence, asset file names, and the build tool.
  final String id;
  final String label;
  /// Short tag shown next to an entry (list view, overlay, dashboard).
  final String tag;
  final PoiKind kind;

  const PoiCategory(this.id, this.label, this.tag, this.kind);

  bool get isReference => kind == PoiKind.reference;

  static PoiCategory? byId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }

  static List<PoiCategory> get references =>
      values.where((c) => c.isReference).toList(growable: false);
}
