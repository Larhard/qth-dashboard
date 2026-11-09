import 'package:get_storage/get_storage.dart';

import '../models/poi_category.dart';
import '../models/poi_hit.dart';
import 'city_service.dart';
import 'reference_service.dart';

/// Which nearby-POI categories exist, which the user enabled, which one the
/// dashboard shows, and nearest / k-nearest lookups across all of them.
///
/// Cities and ports keep living in [CityService]; amateur-radio references in
/// [ReferenceService]. This is the single facade the UI talks to.
class PoiService {
  PoiService._();
  static final instance = PoiService._();

  static final _store = GetStorage();
  // Stores the DISABLED set, so categories added in a later version start enabled.
  static const _disabledKey = 'poi_disabled';
  static const _currentKey = 'poi_current';
  static const _listKey = 'poi_list_selection';

  static CityMode? cityModeOf(PoiCategory c) => switch (c) {
        PoiCategory.cityLarge => CityMode.large,
        PoiCategory.cityRegional => CityMode.precise,
        PoiCategory.cityLocal => CityMode.detailed,
        PoiCategory.port => CityMode.port,
        _ => null,
      };

  late Set<PoiCategory> _enabled;
  late PoiCategory _current;

  void init() {
    final disabled = {...?_store.read<List>(_disabledKey)?.map((e) => '$e')};
    // Default: everything (that has data) is on.
    _enabled = {for (final c in PoiCategory.values) if (!disabled.contains(c.id)) c};

    final cur = PoiCategory.byId(_store.read<String>(_currentKey) ?? '');
    _current = cur ??
        // First run after the upgrade: carry over the old city-tier choice.
        switch (CityService.instance.mode) {
          CityMode.large => PoiCategory.cityLarge,
          CityMode.precise => PoiCategory.cityRegional,
          CityMode.detailed => PoiCategory.cityLocal,
          CityMode.port => PoiCategory.port,
        };
    // Warm up the shown category so the dashboard isn't empty on start.
    if (_current.isReference) ReferenceService.instance.load(_current);
  }

  // ── Availability ───────────────────────────────────────────────────────────

  /// True when the category has data in this build (or was downloaded).
  bool hasData(PoiCategory c) {
    final mode = cityModeOf(c);
    if (mode != null) return CityService.instance.availableModes.contains(mode);
    return ReferenceService.instance.hasData(c);
  }

  bool isEnabled(PoiCategory c) => _enabled.contains(c);

  Future<void> setEnabled(PoiCategory c, bool on) async {
    on ? _enabled.add(c) : _enabled.remove(c);
    await _store.write(_disabledKey, [for (final e in PoiCategory.values) if (!_enabled.contains(e)) e.id]);
    if (!on && c.isReference && c != _current) ReferenceService.instance.unload(c);
    if (!on && c == _current) _current = current; // re-snap via getter
    ReferenceService.instance.revision.value++; // let listeners refresh
  }

  /// Enabled categories that have data, in a stable order. These are what the
  /// dashboard cycles through.
  List<PoiCategory> get active =>
      [for (final c in PoiCategory.values) if (_enabled.contains(c) && hasData(c)) c];

  /// The category the dashboard shows; snaps to the first active one if the
  /// saved choice was disabled or has no data. Null if nothing is active.
  PoiCategory? get currentOrNull {
    final a = active;
    if (a.isEmpty) return null;
    if (!a.contains(_current)) _current = a.first;
    return _current;
  }

  PoiCategory get current => currentOrNull ?? PoiCategory.cityLarge;

  /// Long-press on the POI section: next active category.
  PoiCategory? cycle() {
    final next = nextActive(active, _current);
    if (next == null) return null;
    _current = next;
    _store.write(_currentKey, next.id);
    ReferenceService.instance.retainOnly({next}); // free the table cycled away from
    if (next.isReference) ReferenceService.instance.load(next);
    return next;
  }

  /// Pure cycling rule (unit-tested): the entry after [current] in [active],
  /// wrapping; the first entry if [current] isn't active.
  static PoiCategory? nextActive(List<PoiCategory> active, PoiCategory current) {
    if (active.isEmpty) return null;
    final i = active.indexOf(current);
    return active[(i + 1) % active.length]; // i == -1 → first
  }

  // ── Lookups ──────────────────────────────────────────────────────────────

  /// Nearest POI of the current category. Null while a reference table is still
  /// loading (the load is started here; [ReferenceService.revision] fires when
  /// it's ready) or when nothing is active.
  PoiHit? nearest(double lat, double lon) {
    final c = currentOrNull;
    if (c == null) return null;
    return nearestIn(c, lat, lon);
  }

  PoiHit? nearestIn(PoiCategory c, double lat, double lon) {
    final mode = cityModeOf(c);
    if (mode != null) {
      final nc = CityService.instance.nearestForMode(lat, lon, mode);
      return nc == null ? null : PoiHit.city(c, nc.city, lat, lon, distKm: nc.distKm);
    }
    final t = ReferenceService.instance.table(c);
    if (t == null) {
      ReferenceService.instance.load(c);
      return null;
    }
    final h = t.nearest(lat, lon);
    return h == null ? null : PoiHit.ref(c, t.row(h.index), lat, lon, distKm: h.distKm);
  }

  /// Merged list of the nearest POIs across [cats], nearest first. Loads any
  /// reference tables that aren't in memory yet.
  Future<List<PoiHit>> nearby(double lat, double lon, Iterable<PoiCategory> cats,
      {required int perCategory, required int maxItems}) async {
    final out = <PoiHit>[];
    for (final c in cats) {
      final mode = cityModeOf(c);
      if (mode != null) {
        for (final nc in CityService.instance.nearestKForMode(lat, lon, mode, perCategory)) {
          out.add(PoiHit.city(c, nc.city, lat, lon, distKm: nc.distKm));
        }
        continue;
      }
      final t = await ReferenceService.instance.load(c);
      if (t == null) continue;
      for (final h in t.nearestK(lat, lon, perCategory)) {
        out.add(PoiHit.ref(c, t.row(h.index), lat, lon, distKm: h.distKm));
      }
    }
    out.sort((a, b) => a.distKm.compareTo(b.distKm));
    return out.length > maxItems ? out.sublist(0, maxItems) : out;
  }

  // ── List-view filter (persisted separately from the dashboard selection) ──

  Set<PoiCategory> get listSelection {
    final saved = _store.read<List>(_listKey);
    if (saved == null) return active.toSet();
    return saved.map((e) => PoiCategory.byId('$e')).whereType<PoiCategory>().toSet();
  }

  Future<void> setListSelection(Set<PoiCategory> s) =>
      _store.write(_listKey, [for (final c in PoiCategory.values) if (s.contains(c)) c.id]);
}
