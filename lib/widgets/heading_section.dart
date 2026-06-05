import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../utils/formatting.dart';
import 'arrow_widget.dart';
import 'compass_painters.dart';
import 'dashboard_vm.dart';

/// The heading block: bearing arrow + relative POI ring (arrow or wind-rose mode),
/// the large degree readout, speed, and the GPS-lock / pocket-lock indicator row.
/// Long-press gestures cycle arrow mode, heading source, and speed unit.
/// Presentational — all data + callbacks come from [DashboardVm]/[DashboardActions].
class HeadingSection extends StatelessWidget {
  final DashboardVm vm;
  final DashboardActions actions;
  final bool landscape;

  const HeadingSection({
    super.key,
    required this.vm,
    required this.actions,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(vm.dayMode);
    final headingText = vm.headingValid ? '${vm.heading.round()}°' : '---';
    final degFont = landscape ? 52.0 : 64.0;
    final speedFont = landscape ? 20.0 : 26.0;
    final lockFont = landscape ? 12.0 : 14.0;

    final degrees = GestureDetector(
      onLongPress: actions.toggleHeadingSource,
      behavior: HitTestBehavior.opaque,
      child: Text(headingText,
          textAlign: TextAlign.start,
          style: TextStyle(
              fontSize: degFont, fontWeight: FontWeight.w900,
              color: vm.headingColor, height: 1.0)),
    );

    final speed = GestureDetector(
      onLongPress: actions.cycleSpeedUnit,
      child: Text(formatSpeed(vm.position.speed, vm.speedUnit),
          style: TextStyle(
              fontSize: speedFont, fontWeight: FontWeight.w600,
              color: pal.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _compass(),
        SizedBox(width: landscape ? 14 : 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: landscape ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Landscape pins the degrees to a fixed width so the row doesn't
            // shift as the digit count changes (9° → 10° → 359°).
            landscape ? SizedBox(width: 120, child: degrees) : degrees,
            speed,
            _lockMode(pal, sourceFontSize: lockFont, trkFontSize: lockFont),
          ],
        ),
      ],
    );
  }

  // Bearing arrow + relative POI ring. Identical in both orientations.
  Widget _compass() {
    return GestureDetector(
      onLongPress: actions.toggleHeadingArrowMode,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(alignment: Alignment.center, children: [
          // Wind-rose: live ring via ValueListenableBuilder so the secondary dash
          // repaints at compass rate even when GPS is the primary source.
          // Arrow mode: static ring (driven by GPS setState).
          if (vm.windRose)
            ValueListenableBuilder<double>(
              valueListenable: vm.compassNotifier,
              builder: (_, compassBearing, __) {
                final sec = vm.sourceAuto
                    ? compassBearing
                    : (vm.trackBearing ?? vm.lastValidGpsHeading);
                return Positioned.fill(child: CustomPaint(
                  painter: BearingRingPainter(
                    primaryHeading: vm.heading, markers: vm.markers, dayMode: vm.dayMode,
                    windRoseMode: true, secondaryBearing: sec,
                    secondaryColor: vm.secondaryHeadingColor,
                  ),
                ));
              },
            )
          else
            Positioned.fill(child: CustomPaint(
              painter: BearingRingPainter(
                primaryHeading: vm.heading, markers: vm.markers, dayMode: vm.dayMode),
            )),
          // Arrow mode only — both arrows. Wind-rose shows no arrows.
          if (!vm.windRose) ...[
            ValueListenableBuilder<double>(
              valueListenable: vm.compassNotifier,
              builder: (_, compassBearing, __) {
                final sb = vm.sourceAuto
                    ? compassBearing
                    : (vm.trackBearing ?? vm.lastValidGpsHeading);
                if (sb == null) return const SizedBox.shrink();
                // Always dim the secondary arrow so it's distinguishable from the
                // primary, including in night mode.
                return Opacity(opacity: 0.38,
                    child: ArrowWidget(bearingDeg: sb, color: vm.secondaryHeadingColor, size: 80));
              },
            ),
            ArrowWidget(bearingDeg: vm.heading, color: vm.headingColor, size: 80),
          ],
        ]),
      ),
    );
  }

  // GPS-lock + pocket-lock indicators (long-press each to toggle) and TRK row.
  Widget _lockMode(Palette pal, {required double sourceFontSize, required double trkFontSize}) {
    final cText2 = pal.textSecondary;
    final cText3 = pal.pick(kDFg2, kN3);
    final live = pal.port;
    final save = pal.pick(kDAmb, kN3);
    final modeColor = vm.gpsOnLock ? live : save;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onLongPress: actions.toggleGpsLock,
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(vm.sourceLabel,
                  style: TextStyle(fontSize: sourceFontSize, color: cText2, letterSpacing: 2.5)),
              const SizedBox(width: 6),
              Icon(vm.gpsOnLock ? Icons.gps_fixed : Icons.gps_off,
                  size: sourceFontSize - 1, color: modeColor),
              Text('@', style: TextStyle(fontSize: sourceFontSize - 2, color: modeColor, height: 1.0)),
              Icon(Icons.lock, size: sourceFontSize - 1, color: modeColor),
            ]),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onLongPress: actions.togglePocketLock,
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.smartphone, size: sourceFontSize,
                  color: vm.pocketLockEnabled ? live : cText3),
              Icon(vm.pocketLockEnabled ? Icons.lock : Icons.lock_open,
                  size: sourceFontSize - 1, color: vm.pocketLockEnabled ? live : cText3),
              Text('@', style: TextStyle(
                  fontSize: sourceFontSize - 2,
                  color: vm.pocketLockEnabled ? live : cText3, height: 1.0)),
              Icon(Icons.sensors, size: sourceFontSize - 1,
                  color: vm.pocketLockEnabled ? live : cText3),
            ]),
          ),
        ]),
        Text(
          vm.trackBearing != null ? 'TRK ${vm.trackBearing!.round()}°' : 'TRK ---',
          style: TextStyle(fontSize: trkFontSize, color: cText3, letterSpacing: 1.5),
        ),
      ],
    );
  }
}
