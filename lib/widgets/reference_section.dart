import 'package:flutter/material.dart';

import '../models/poi_hit.dart';
import '../utils/formatting.dart';
import '../utils/text_fit.dart';
import 'city_section.dart' show CityVariant;
import 'dashboard_vm.dart';
import 'poi_widgets.dart';
import 'rel_bearing_arrow.dart';

/// Nearest amateur-radio reference (SOTA, POTA, WWFF…) on the dashboard.
///
/// Gestures (same for every POI category): TAP copies the reference's
/// coordinates (paste into Google Maps / a hiking map), LONG-PRESS cycles the
/// active categories, the ⓘ button opens the detail sheet with the full rules.
class ReferenceSection extends StatelessWidget {
  final PoiHit hit;
  final DashboardVm vm;
  final DashboardActions actions;
  final CityVariant variant;

  const ReferenceSection({
    super.key,
    required this.hit,
    required this.vm,
    required this.actions,
    required this.variant,
  });

  Color get _color => vm.poiColor;
  Color get _subColor => vm.poiSubColor;

  Widget _arrow(double size) => RelBearingArrow(
      bearingDeg: hit.bearingDeg, heading: vm.heading, color: _color,
      size: size, dayMode: vm.dayMode);

  Widget _info(double size) => GestureDetector(
        onTap: () => actions.showPoiDetails(hit),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.info_outline, size: size, color: _subColor),
        ),
      );

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

  Widget _refLine(double maxSize, double minSize) => LayoutBuilder(builder: (_, bc) {
        final ref = hit.ref!.ref;
        final fs = fitFontSize(ref, bc.maxWidth, maxSize: maxSize, minSize: minSize, maxLines: 1);
        return Text(ref,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: fs, fontWeight: FontWeight.w800, color: _color, letterSpacing: 0.5));
      });

  Widget _distRow(double fs) => Row(children: [
        Text('${hit.bearingDeg.round()}°',
            style: TextStyle(fontSize: fs, color: _subColor,
                fontFeatures: const [FontFeature.tabularFigures()])),
        SizedBox(width: fs * 0.8),
        Text(formatDistanceUnit(hit.distKm, vm.speedUnit),
            style: TextStyle(fontSize: fs, color: _color, fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (hit.ref!.altM > 0) ...[
          SizedBox(width: fs * 0.8),
          Flexible(
            child: Text(formatAlt(hit.ref!.altM.toDouble(), vm.speedUnit),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fs * 0.75, color: _subColor)),
          ),
        ],
      ]);

  Widget _portrait() => Row(children: [
        _arrow(60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PoiTag(hit.category, dayMode: vm.dayMode, fontSize: 11),
              const SizedBox(width: 8),
              Expanded(child: _refLine(30, 16)),
              _info(20),
            ]),
            Text(hit.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _subColor)),
            _distRow(20),
            const SizedBox(height: 2),
            RefRuleChips(hit: hit, dayMode: vm.dayMode, fontSize: 14, position: vm.position),
          ]),
        ),
      ]);

  Widget _landscape() => Row(children: [
        _arrow(44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PoiTag(hit.category, dayMode: vm.dayMode, fontSize: 9),
              const SizedBox(width: 6),
              Expanded(child: _refLine(20, 10)),
              _info(16),
            ]),
            Text(hit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _subColor)),
            _distRow(15),
            RefRuleChips(hit: hit, dayMode: vm.dayMode, fontSize: 11, position: vm.position),
          ]),
        ),
      ]);

  // One-line row used while anchoring.
  Widget _compact() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          _arrow(22),
          const SizedBox(width: 6),
          PoiTag(hit.category, dayMode: vm.dayMode, fontSize: 8),
          const SizedBox(width: 6),
          Expanded(
            child: Text(hit.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _color, fontWeight: FontWeight.w600)),
          ),
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
