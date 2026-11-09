import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../config/tuning.dart';
import '../models/poi_category.dart';
import '../models/poi_hit.dart';
import '../services/poi_service.dart';
import '../services/reference_service.dart';
import '../services/waypoint_service.dart';
import '../settings/display_settings.dart';
import '../theme/palette.dart';
import '../utils/formatting.dart';
import '../widgets/arrow_widget.dart';
import '../widgets/city_detail_sheet.dart';
import '../widgets/poi_widgets.dart';
import '../widgets/ref_detail_sheet.dart';

/// Every nearby point of interest, nearest first, across the categories the
/// user picks (cities, ports, SOTA, POTA…). Reached from the Waypoints screen
/// menu — not from the dashboard. Tap a row to copy its coordinates; ⓘ for the
/// detail sheet; the navigate button makes the POI the active waypoint (saved
/// to the waypoint list, like any other) and returns to the dashboard.
///
/// Pops with `true` when a navigation target was set, so the Waypoints screen
/// can close too.
class NearbyPoiScreen extends StatefulWidget {
  final Position? position;
  final bool dayMode;
  final SpeedUnit speedUnit;
  final CoordFormat coordFormat;
  final LocatorType locatorType;

  const NearbyPoiScreen({
    super.key,
    required this.position,
    required this.dayMode,
    required this.speedUnit,
    required this.coordFormat,
    required this.locatorType,
  });

  @override
  State<NearbyPoiScreen> createState() => _NearbyPoiScreenState();
}

class _NearbyPoiScreenState extends State<NearbyPoiScreen> {
  Palette get _pal => Palette.of(widget.dayMode);
  late Set<PoiCategory> _selected;
  Position? _pos;
  Future<List<PoiHit>>? _items;

  @override
  void initState() {
    super.initState();
    _pos = widget.position;
    final avail = _available;
    _selected = PoiService.instance.listSelection.where(avail.contains).toSet();
    if (_selected.isEmpty) _selected = PoiService.instance.active.toSet();
    _reload();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    // The list may have loaded many tables; keep only the dashboard's one.
    ReferenceService.instance.retainOnly({PoiService.instance.current});
    super.dispose();
  }

  List<PoiCategory> get _available =>
      [for (final c in PoiCategory.values) if (PoiService.instance.hasData(c)) c];

  void _reload() {
    final p = _pos;
    setState(() {
      _items = p == null
          ? Future.value(const [])
          : PoiService.instance.nearby(p.latitude, p.longitude, _selected,
              perCategory: PoiTuning.listPerCategory, maxItems: PoiTuning.listMaxItems);
    });
  }

  Future<void> _refreshPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));
      _pos = p;
    } catch (_) {}
    _reload();
  }

  void _toggle(PoiCategory c, bool on) {
    on ? _selected.add(c) : _selected.remove(c);
    PoiService.instance.setListSelection(_selected);
    _reload();
  }

  void _copy(PoiHit h) {
    Clipboard.setData(ClipboardData(text: h.coordsText));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Copied ${h.coordsText}', style: TextStyle(color: _pal.textSecondary, fontSize: 13)),
        backgroundColor: _pal.snackBg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ));
  }

  void _navigate(PoiHit h) {
    HapticFeedback.mediumImpact();
    WaypointService.instance.navigateTo(h.label, h.lat, h.lon);
    Navigator.pop(context, true);
  }

  void _details(PoiHit h) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _pal.sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => h.isRef
          ? RefDetailSheet(
              hit: h, dayMode: widget.dayMode, position: _pos, speedUnit: widget.speedUnit,
              coordFormat: widget.coordFormat, locatorType: widget.locatorType)
          : CityDetailSheet(
              nc: (city: h.city!, distKm: h.distKm, bearingDeg: h.bearingDeg),
              dayMode: widget.dayMode, position: _pos, speedUnit: widget.speedUnit,
              coordFormat: widget.coordFormat, locatorType: widget.locatorType),
    );
  }

  Widget _filters() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in _available)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(c.tag,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _selected.contains(c) ? Colors.black : _pal.poi(c))),
                  selected: _selected.contains(c),
                  onSelected: (v) => _toggle(c, v),
                  showCheckmark: false,
                  selectedColor: _pal.poi(c),
                  backgroundColor: _pal.tileBg,
                  side: BorderSide(color: _pal.poi(c).withValues(alpha: 0.7)),
                ),
              ),
          ],
        ),
      );

  Widget _row(PoiHit h) {
    final color = _pal.poi(h.category);
    final sub = _pal.poiSub(h.category);
    return InkWell(
      onTap: () => _copy(h),
      onLongPress: () => _details(h),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: color, width: 3),
            bottom: BorderSide(color: _pal.divider),
          ),
        ),
        child: Row(children: [
          ArrowWidget(bearingDeg: h.bearingDeg, color: color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PoiTag(h.category, dayMode: widget.dayMode, fontSize: 9),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(h.isRef ? h.ref!.ref : h.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                ),
              ]),
              if (h.isRef)
                Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: sub))
              else if (h.city!.country.isNotEmpty)
                Text(h.city!.country, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: sub)),
              if (h.isRef)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RefRuleChips(hit: h, dayMode: widget.dayMode, fontSize: 11, position: _pos),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatDistanceUnit(h.distKm, widget.speedUnit),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${h.bearingDeg.round()}°',
                style: TextStyle(fontSize: 12, color: sub,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          IconButton(
            tooltip: 'Navigate here (set as waypoint)',
            icon: Icon(Icons.navigation_outlined, size: 22, color: color),
            onPressed: () => _navigate(h),
          ),
          IconButton(
            tooltip: 'Details',
            icon: Icon(Icons.info_outline, size: 20, color: sub),
            onPressed: () => _details(h),
          ),
        ]),
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _pal.textDim, height: 1.5)),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: _pal.textDim),
          title: Text('Nearby POIs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _pal.textDim)),
          actions: [
            IconButton(
              tooltip: 'Refresh position',
              icon: Icon(Icons.my_location, color: _pal.textDim),
              onPressed: _refreshPosition,
            ),
          ],
        ),
        body: Column(children: [
          _filters(),
          Divider(color: _pal.divider, height: 1),
          Expanded(
            child: _pos == null
                ? _message('Waiting for a GPS fix…\nTap ⌖ to retry.')
                : _selected.isEmpty
                    ? _message('Select one or more categories above.')
                    : FutureBuilder<List<PoiHit>>(
                        future: _items,
                        builder: (_, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return Center(child: CircularProgressIndicator(color: _pal.textDim));
                          }
                          final items = snap.data ?? const [];
                          if (items.isEmpty) return _message('Nothing found for these categories.');
                          return ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, i) => _row(items[i]),
                          );
                        },
                      ),
          ),
        ]),
      );
}
