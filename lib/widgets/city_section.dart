import 'package:flutter/material.dart';
import '../services/city_service.dart' show NearestCity;
import '../utils/formatting.dart';
import '../utils/text_fit.dart';
import 'dashboard_vm.dart';
import 'rel_bearing_arrow.dart';

enum CityVariant { portrait, landscape, compact }

/// Nearest city / port section. Tap cycles the city tier; long-press opens the
/// detail sheet. Three layouts share one widget: full (portrait), landscape, and
/// a one-line compact row (used while anchoring). Colours/data come from the VM.
class CitySection extends StatelessWidget {
  final NearestCity nc;
  final DashboardVm vm;
  final DashboardActions actions;
  final CityVariant variant;

  const CitySection({
    super.key,
    required this.nc,
    required this.vm,
    required this.actions,
    required this.variant,
  });

  Color get _color => vm.cityColor;
  Color get _subColor => vm.citySubColor;

  Widget _arrow(double size) => RelBearingArrow(
      bearingDeg: nc.bearingDeg, heading: vm.heading, color: _color,
      size: size, dayMode: vm.dayMode);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: actions.toggleCityMode,
        onLongPress: () => actions.showCityDetails(nc),
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
            LayoutBuilder(builder: (_, bc) {
              final fs = fitFontSize(nc.city.name, bc.maxWidth, maxSize: 32, minSize: 18);
              return Text(nc.city.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: _color));
            }),
            Row(children: [
              Text('${nc.bearingDeg.round()}°',
                  style: TextStyle(
                      fontSize: 22, color: _subColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 18),
              Text(formatDistanceUnit(nc.distKm, vm.speedUnit),
                  style: TextStyle(
                      fontSize: 22, color: _color, fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 14),
              Flexible(
                child: Text(nc.city.country,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: _subColor.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
            if (nc.city.vhf.isNotEmpty)
              GestureDetector(
                onTap: () => actions.copy('VHF ${nc.city.vhf}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.radio, size: 14, color: _subColor),
                  const SizedBox(width: 4),
                  Text('VHF ${nc.city.vhf}',
                      style: TextStyle(
                          fontSize: 16, color: _color,
                          fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                ]),
              ),
            if (nc.city.callSign.isNotEmpty)
              Text(nc.city.callSign,
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
                  final fs = fitFontSize(nc.city.name, bc.maxWidth, maxSize: 24, minSize: 10);
                  return Text(nc.city.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: _color));
                }),
              ),
              const SizedBox(width: 6),
              Text(nc.city.country,
                  style: TextStyle(fontSize: 12, color: _subColor.withValues(alpha: 0.7))),
            ]),
            Row(children: [
              Text('${nc.bearingDeg.round()}°',
                  style: TextStyle(
                      fontSize: 16, color: _subColor,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 10),
              Text(formatDistanceUnit(nc.distKm, vm.speedUnit),
                  style: TextStyle(
                      fontSize: 16, color: _color, fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
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
          Expanded(child: Text(nc.city.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _color, fontWeight: FontWeight.w600))),
          Text('${nc.bearingDeg.round()}°',
              style: TextStyle(fontSize: 12, color: _subColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(formatDistanceUnit(nc.distKm, vm.speedUnit),
              style: TextStyle(fontSize: 12, color: _color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}
