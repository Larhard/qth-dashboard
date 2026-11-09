import 'package:flutter/material.dart';
import '../models/city.dart';
import '../models/poi_hit.dart';
import '../utils/formatting.dart';
import '../utils/text_fit.dart';
import 'dashboard_vm.dart';
import 'poi_widgets.dart';
import 'rel_bearing_arrow.dart';

enum CityVariant { portrait, landscape, compact }

/// Nearest city / port section. Gestures match every POI category: TAP copies
/// the coordinates, LONG-PRESS cycles the active categories, ⓘ opens the detail
/// sheet. Three layouts share one widget: full (portrait), landscape, and a
/// one-line compact row (used while anchoring). Colours/data come from the VM.
class CitySection extends StatelessWidget {
  final PoiHit hit;
  final DashboardVm vm;
  final DashboardActions actions;
  final CityVariant variant;

  const CitySection({
    super.key,
    required this.hit,
    required this.vm,
    required this.actions,
    required this.variant,
  });

  Color get _color => vm.poiColor;
  Color get _subColor => vm.poiSubColor;
  City get _city => hit.city!;

  Widget _info(double size) => GestureDetector(
        onTap: () => actions.showPoiDetails(hit),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.info_outline, size: size, color: _subColor),
        ),
      );

  Widget _arrow(double size) => RelBearingArrow(
      bearingDeg: hit.bearingDeg, heading: vm.heading, color: _color,
      size: size, dayMode: vm.dayMode);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => actions.copy(hit.coordsText),
        onLongPress: actions.cyclePoi,
        behavior: HitTestBehavior.opaque,
        child: switch (variant) {
          CityVariant.portrait => _portrait(),
          CityVariant.landscape => _landscape(),
          CityVariant.compact => _compact(),
        },
      );

  Widget _portrait() => Row(children: [
        _arrow(60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: LayoutBuilder(builder: (_, bc) {
                  final fs = fitFontSize(_city.name, bc.maxWidth, maxSize: 32, minSize: 18);
                  return Text(_city.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: _color));
                }),
              ),
              _info(20),
            ]),
            Row(children: [
              Text('${hit.bearingDeg.round()}°',
                  style: TextStyle(
                      fontSize: 22, color: _subColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 18),
              Text(formatDistanceUnit(hit.distKm, vm.speedUnit),
                  style: TextStyle(
                      fontSize: 22, color: _color, fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 14),
              PoiTag(hit.category, dayMode: vm.dayMode, fontSize: 10),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_city.country,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: _subColor.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
            if (_city.vhf.isNotEmpty)
              GestureDetector(
                onTap: () => actions.copy('VHF ${_city.vhf}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.radio, size: 14, color: _subColor),
                  const SizedBox(width: 4),
                  Text('VHF ${_city.vhf}',
                      style: TextStyle(
                          fontSize: 16, color: _color,
                          fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                ]),
              ),
            if (_city.callSign.isNotEmpty)
              Text(_city.callSign,
                  style: TextStyle(
                      fontSize: 14, color: _subColor.withValues(alpha: 0.8),
                      letterSpacing: 2.0)),
          ]),
        ),
      ]);

  Widget _landscape() => Row(children: [
        _arrow(44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: LayoutBuilder(builder: (_, bc) {
                  final fs = fitFontSize(_city.name, bc.maxWidth, maxSize: 24, minSize: 10);
                  return Text(_city.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: _color));
                }),
              ),
              const SizedBox(width: 6),
              Text(_city.country,
                  style: TextStyle(fontSize: 12, color: _subColor.withValues(alpha: 0.7))),
              _info(16),
            ]),
            Row(children: [
              Text('${hit.bearingDeg.round()}°',
                  style: TextStyle(
                      fontSize: 16, color: _subColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              Text(formatDistanceUnit(hit.distKm, vm.speedUnit),
                  style: TextStyle(
                      fontSize: 16, color: _color, fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              PoiTag(hit.category, dayMode: vm.dayMode, fontSize: 9),
            ]),
          ]),
        ),
      ]);

  // One-line row used while anchoring; mirrors the nav-waypoint compact row.
  Widget _compact() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          _arrow(22),
          const SizedBox(width: 6),
          Expanded(child: Text(_city.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _color, fontWeight: FontWeight.w600))),
          Text('${hit.bearingDeg.round()}°',
              style: TextStyle(fontSize: 12, color: _subColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(formatDistanceUnit(hit.distKm, vm.speedUnit),
              style: TextStyle(fontSize: 12, color: _color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}
