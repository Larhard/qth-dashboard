import 'package:flutter/material.dart';
import '../services/waypoint_service.dart';
import '../settings/display_settings.dart';
import '../theme/palette.dart';
import '../utils/coordinate_utils.dart';
import '../utils/formatting.dart';
import '../utils/geo_utils.dart';
import '../utils/mgrs_utils.dart';
import 'compass_painters.dart';
import 'dashboard_vm.dart';
import 'rel_bearing_arrow.dart';

String _locStr(double lat, double lon, LocatorType t) =>
    t == LocatorType.maidenhead ? maidenhead(lat, lon) : mgrs(lat, lon);

/// Compact one-line nav-waypoint row (shown while anchoring): arrow + name +
/// bearing + distance. Long-press opens the Waypoints screen.
class NavWaypointCompact extends StatelessWidget {
  final DashboardVm vm;
  final DashboardActions actions;
  const NavWaypointCompact({super.key, required this.vm, required this.actions});

  @override
  Widget build(BuildContext context) {
    final nav = WaypointService.instance.active;
    if (nav == null) return const SizedBox.shrink();
    final pos = vm.position;
    final b = bearing(pos.latitude, pos.longitude, nav.lat, nav.lon);
    final d = haversineKm(pos.latitude, pos.longitude, nav.lat, nav.lon);
    final navColor = Palette.of(vm.dayMode).nav;
    return GestureDetector(
      onLongPress: actions.openWaypoints,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          RelBearingArrow(bearingDeg: b, heading: vm.heading, color: navColor, size: 22, dayMode: vm.dayMode),
          const SizedBox(width: 6),
          Expanded(child: Text(nav.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: navColor, fontWeight: FontWeight.w600))),
          Text('${b.round()}°',
              style: TextStyle(fontSize: 12, color: navColor.withValues(alpha: 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(formatDistanceUnit(d, vm.speedUnit),
              style: TextStyle(fontSize: 12, color: navColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// Full nav-waypoint card with the hold-to-deactivate border ring (targets nav).
class NavWaypointCard extends StatelessWidget {
  final DashboardVm vm;
  final DashboardActions actions;
  final bool landscape;
  const NavWaypointCard({super.key, required this.vm, required this.actions, required this.landscape});

  @override
  Widget build(BuildContext context) {
    final wp = WaypointService.instance.active;
    if (wp == null) return const SizedBox.shrink();
    final pal = Palette.of(vm.dayMode);
    final pos = vm.position;
    final b = bearing(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final d = haversineKm(pos.latitude, pos.longitude, wp.lat, wp.lon);
    final navColor = pal.nav;
    final navSub = pal.navLabel;
    final arrowSz = landscape ? 36.0 : 50.0;
    final dataFz = landscape ? 16.0 : 22.0;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Listener(
        onPointerDown: (_) => actions.startClear(WptHoldTarget.nav),
        onPointerUp: (_) => actions.cancelClear(),
        onPointerCancel: (_) => actions.cancelClear(),
        child: CustomPaint(
          painter: WptBorderPainter(
              vm.holdTarget == WptHoldTarget.nav ? vm.clearProgress : 0.0,
              dayMode: vm.dayMode),
          child: Padding(
            padding: landscape
                ? const EdgeInsets.fromLTRB(10, 5, 10, 5)
                : const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              RelBearingArrow(bearingDeg: b, heading: vm.heading, color: navColor, size: arrowSz, dayMode: vm.dayMode),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wp.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: navSub, letterSpacing: 1.2)),
                  Row(children: [
                    Text('${b.round()}°',
                        style: TextStyle(fontSize: dataFz, color: navSub,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: 12),
                    Text(formatDistanceUnit(d, vm.speedUnit),
                        style: TextStyle(fontSize: dataFz, color: navColor,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// MOB section pinned to the bottom: the emergency-waypoint card (with
/// hold-to-clear) when one is set, otherwise the big MOB drop button.
class MobSection extends StatelessWidget {
  final DashboardVm vm;
  final DashboardActions actions;
  final bool portrait;
  const MobSection({super.key, required this.vm, required this.actions, required this.portrait});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(vm.dayMode);
    final mob = WaypointService.instance.emergency;
    if (mob == null) {
      return SizedBox(
        width: double.infinity,
        height: portrait ? 80 : 62,
        child: ElevatedButton(
          onPressed: actions.addMob,
          style: ElevatedButton.styleFrom(
            backgroundColor: pal.pick(kDEmgBg, kN3),
            foregroundColor: pal.textPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            elevation: 0,
          ),
          child: Text('MOB',
              style: TextStyle(
                  fontSize: portrait ? 38 : 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: portrait ? 5 : 4)),
        ),
      );
    }

    final pos = vm.position;
    final b = bearing(pos.latitude, pos.longitude, mob.lat, mob.lon);
    final d = haversineKm(pos.latitude, pos.longitude, mob.lat, mob.lon);
    final cName = pal.pick(kDEmg, kN1);
    final cData = pal.pick(kDEmg, kN2);
    final cCoords = pal.pick(kDEmgS, kN2);
    final arrowSize = portrait ? 60.0 : 46.0;
    final nameFontSize = portrait ? 20.0 : 14.0;
    final dataFontSize = portrait ? 22.0 : 17.0;
    final coordFontSize = portrait ? 14.0 : 11.0;

    Widget dataRow(String left, String right) {
      final style = TextStyle(
          fontSize: coordFontSize, color: cCoords,
          fontFeatures: const [FontFeature.tabularFigures()]);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [Text(left, style: style), Text(right, style: style)],
      );
    }

    // Outer Padding ensures the border ring is never clipped by parent bounds.
    return Padding(
      padding: EdgeInsets.all(portrait ? 3 : 2),
      child: Listener(
        onPointerDown: (_) => actions.startClear(WptHoldTarget.emergency),
        onPointerUp: (_) => actions.cancelClear(),
        onPointerCancel: (_) => actions.cancelClear(),
        child: CustomPaint(
          painter: WptBorderPainter(
              vm.holdTarget == WptHoldTarget.emergency ? vm.clearProgress : 0.0,
              dayMode: vm.dayMode),
          child: Padding(
            padding: portrait
                ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
                : const EdgeInsets.fromLTRB(10, 5, 10, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RelBearingArrow(bearingDeg: b, heading: vm.heading, color: cName, size: arrowSize, dayMode: vm.dayMode),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(mob.name,
                                style: TextStyle(
                                    fontSize: nameFontSize, fontWeight: FontWeight.w900,
                                    color: cName, letterSpacing: 1.5)),
                          ),
                          Row(children: [
                            Text('${b.round()}°',
                                style: TextStyle(
                                    fontSize: dataFontSize, color: cData,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                            const SizedBox(width: 14),
                            Text(formatDistanceUnit(d, vm.speedUnit),
                                style: TextStyle(
                                    fontSize: dataFontSize, color: cName,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: portrait ? 6 : 2),
                dataRow(formatLatF(mob.lat, vm.coordFormat),
                    formatDateYmd(mob.timestamp, utc: vm.timeUtc)),
                dataRow(formatLonF(mob.lon, vm.coordFormat),
                    '${formatTimeHms(mob.timestamp, utc: vm.timeUtc)} ${vm.timeUtc ? 'UTC' : 'LCL'}'),
                const SizedBox(height: 2),
                dataRow(_locStr(mob.lat, mob.lon, vm.locatorType),
                    formatElapsed(DateTime.now().difference(mob.timestamp))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
