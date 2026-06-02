import 'package:get_storage/get_storage.dart';
import '../models/waypoint.dart';
import '../utils/gpx_utils.dart';

/// Two independent tracking concepts:
///
///  emergency (MOB) — set by the MOB button; used for life-safety tracking.
///  active (navigation) — set from the Waypoints list; used for route guidance.
///
/// Both can be shown simultaneously in the UI.
class WaypointService {
  WaypointService._();
  static final instance = WaypointService._();

  static final _store = GetStorage();
  static const _listKey   = 'waypoints';
  static const _activeKey = 'active_waypoint';
  static const _emerKey   = 'emergency_waypoint';

  final List<Waypoint> _waypoints = [];
  String? _activeId;     // navigation waypoint (from list)
  String? _emergencyId;  // MOB / emergency waypoint

  List<Waypoint> get waypoints => List.unmodifiable(_waypoints);
  String? get activeId     => _activeId;
  String? get emergencyId  => _emergencyId;

  Waypoint? get active {
    if (_activeId == null) return null;
    for (final w in _waypoints) {
      if (w.id == _activeId) return w;
    }
    return null;
  }

  Waypoint? get emergency {
    if (_emergencyId == null) return null;
    for (final w in _waypoints) {
      if (w.id == _emergencyId) return w;
    }
    return null;
  }

  void load() {
    final raw = _store.read<List>(_listKey) ?? [];
    _waypoints.clear();
    for (final e in raw) {
      try {
        _waypoints.add(Waypoint.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {}
    }
    _activeId = _store.read<String>(_activeKey);
    _emergencyId = _store.read<String>(_emerKey);
    // Purge stale IDs
    if (_activeId != null && !_waypoints.any((w) => w.id == _activeId)) {
      _activeId = null;
      _store.remove(_activeKey);
    }
    if (_emergencyId != null && !_waypoints.any((w) => w.id == _emergencyId)) {
      _emergencyId = null;
      _store.remove(_emerKey);
    }
  }

  // ── Emergency / MOB ────────────────────────────────────────────────────────

  /// Called by the MOB button — creates an emergency waypoint and sets it as
  /// the active emergency target.  The waypoint is also added to the list so
  /// the user can rename / review it later.
  Waypoint addEmergency(double lat, double lon) {
    final w = Waypoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'MOB ${_waypoints.where((w) => w.isEmergency).length + 1}',
      lat: lat,
      lon: lon,
      timestamp: DateTime.now(),
      isEmergency: true,
    );
    _waypoints.insert(0, w);
    _emergencyId = w.id;
    _persist();
    _store.write(_emerKey, _emergencyId);
    return w;
  }

  void clearEmergency() {
    _emergencyId = null;
    _store.remove(_emerKey);
  }

  // ── Navigation (from list) ─────────────────────────────────────────────────

  /// Add a manually entered waypoint (waypoints screen +).
  Waypoint addManual(String name, double lat, double lon) {
    final w = Waypoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'WPT ${_waypoints.length + 1}' : name.trim(),
      lat: lat,
      lon: lon,
      timestamp: DateTime.now(),
    );
    _waypoints.insert(0, w);
    _persist();
    return w;
  }

  /// Set a navigation target from the waypoints list.
  /// Does NOT affect the emergency (MOB) tracking.
  void setActive(String id) {
    if (_waypoints.any((w) => w.id == id)) {
      _activeId = id;
      _store.write(_activeKey, id);
    }
  }

  void deactivate() {
    _activeId = null;
    _store.remove(_activeKey);
  }

  void rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    for (final w in _waypoints) {
      if (w.id == id) {
        w.name = trimmed;
        _persist();
        return;
      }
    }
  }

  void updateCoords(String id, double lat, double lon) {
    for (final w in _waypoints) {
      if (w.id == id) {
        w.lat = lat;
        w.lon = lon;
        _persist();
        return;
      }
    }
  }

  // ── Import highlighting & undo ────────────────────────────────────────────
  // IDs of the most recently imported batch — available for undo and highlight.
  final List<String> _lastImportIds    = [];
  final Set<String>  _highlightedIds   = {};

  Set<String> get highlightedImportIds => Set.unmodifiable(_highlightedIds);
  bool        get canUndoImport        => _lastImportIds.isNotEmpty;

  void clearImportHighlights() {
    _highlightedIds.clear();
    _lastImportIds.clear();
  }

  /// Remove every waypoint that was added in the last import batch.
  void undoLastImport() {
    for (final id in List.of(_lastImportIds)) {
      remove(id);
    }
    _lastImportIds.clear();
    _highlightedIds.clear();
  }

  // ── Shared ─────────────────────────────────────────────────────────────────

  void remove(String id) {
    _waypoints.removeWhere((w) => w.id == id);
    if (_activeId == id) {
      _activeId = null;
      _store.remove(_activeKey);
    }
    if (_emergencyId == id) {
      _emergencyId = null;
      _store.remove(_emerKey);
    }
    _lastImportIds.remove(id);
    _highlightedIds.remove(id);
    _persist();
  }

  // Called by ReorderableListView.onReorderItem — index is already adjusted.
  void reorder(int oldIndex, int newIndex) {
    final w = _waypoints.removeAt(oldIndex);
    _waypoints.insert(newIndex, w);
    _persist();
  }

  /// Import parsed GPX waypoints.
  ///
  /// Duplicate rules (applied in order):
  ///   1. Position duplicate: any existing point within ~10 m → skip.
  ///      This prevents re-importing "MOB 1" after it was already saved as
  ///      "MOB 1 (2)" at the same position.
  ///   2. Name conflict: same name, distinct position → rename "Name (2)",
  ///      "Name (3)", …  The existing waypoint is never modified.
  ///   3. New point → imported as-is.
  ///
  /// Returns counts: added / skipped (position dup) / renamed (name conflict).
  ({int added, int skipped, int renamed}) importWaypoints(List<GpxWaypoint> items) {
    // New import batch replaces any previous highlight.
    _lastImportIds.clear();
    _highlightedIds.clear();

    int added = 0, skipped = 0, renamed = 0;
    final baseMs = DateTime.now().millisecondsSinceEpoch;
    const tol = 0.0001; // ~10 m in degrees

    for (final item in items) {
      // 1. Position duplicate — skip regardless of name.
      if (_waypoints.any((e) =>
          (e.lat - item.lat).abs() < tol &&
          (e.lon - item.lon).abs() < tol)) {
        skipped++;
        continue;
      }

      // 2. Name conflict — rename the incoming point.
      String name = item.name;
      if (_waypoints.any((e) => e.name == name)) {
        int n = 2;
        while (_waypoints.any((e) => e.name == '$name ($n)')) n++;
        name = '$name ($n)';
        renamed++;
      }

      final id = '${baseMs + added}';
      _waypoints.add(Waypoint(
        id: id,
        name: name,
        lat: item.lat,
        lon: item.lon,
        timestamp: item.time,
      ));
      _lastImportIds.add(id);
      _highlightedIds.add(id);
      added++;
    }
    if (added > 0) _persist();
    return (added: added, skipped: skipped, renamed: renamed);
  }

  void _persist() {
    _store.write(_listKey, _waypoints.map((w) => w.toJson()).toList());
  }
}
