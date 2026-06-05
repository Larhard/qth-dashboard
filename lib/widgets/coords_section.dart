import 'package:flutter/material.dart';
import '../settings/display_settings.dart';
import '../theme/palette.dart';
import '../utils/formatting.dart';
import 'dashboard_vm.dart';

/// Coordinates block: lat/lon (tap to copy, long-press to cycle format), the
/// IARU/MGRS locator row, altitude/accuracy, and the GPS-calibrated clock.
/// Presentational — all data + callbacks come from [DashboardVm]/[DashboardActions].
class CoordsSection extends StatelessWidget {
  final DashboardVm vm;
  final DashboardActions actions;
  final bool landscape;

  const CoordsSection({
    super.key,
    required this.vm,
    required this.actions,
    required this.landscape,
  });

  @override
  Widget build(BuildContext context) {
    final coordStyle = TextStyle(
      fontSize: 22,
      color: Palette.of(vm.dayMode).textPrimary,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => actions.copy('${vm.latStr}\n${vm.lonStr}'),
        onLongPress: actions.toggleCoordFormat,
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vm.latStr, style: coordStyle),
          const SizedBox(height: 2),
          Text(vm.lonStr, style: coordStyle),
        ]),
      ),
      SizedBox(height: landscape ? 6 : 8),
      _locatorRow(
          fontSize: landscape ? 24 : 32, letterSpacing: landscape ? 2.5 : 4.0),
      SizedBox(height: landscape ? 4 : 6),
      _altAccuracyRow(),
      const SizedBox(height: 3),
      _timeRow(fontSize: landscape ? 15.0 : 18.0),
    ]);
  }

  // IARU (green) vs MGRS (amber) — colour + label make the type obvious.
  // Long-press toggles the type; tap copies the value.
  Widget _locatorRow({required double fontSize, required double letterSpacing}) {
    final pal = Palette.of(vm.dayMode);
    final isMaidenhead = vm.locatorType == LocatorType.maidenhead;
    final locColor = isMaidenhead ? pal.pick(kDGps, kN2) : pal.amber;
    final labelColor = isMaidenhead ? pal.gpsLabel : pal.amberLabel;
    final locFontSize = isMaidenhead ? fontSize : fontSize * 0.72;
    final locLetterSpacing = isMaidenhead ? letterSpacing : 0.5;
    final label = isMaidenhead ? 'IARU' : 'MGRS';

    return GestureDetector(
      onTap: () => actions.copy(vm.locStr),
      onLongPress: actions.toggleLocatorType,
      behavior: HitTestBehavior.opaque,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(vm.locStr,
                style: TextStyle(
                    fontSize: locFontSize,
                    color: locColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: locLetterSpacing,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 1.5)),
          ]),
    );
  }

  Widget _altAccuracyRow() {
    final pal = Palette.of(vm.dayMode);
    final cAltAcc = pal.textTertiary;
    final stale = vm.gpsStaleSeconds > 10;
    final altStr = formatAlt(vm.altMeters, vm.speedUnit);
    final accStr = '±${vm.accuracyMeters.round()} m';
    final staleStr =
        stale ? '  GPS ${formatStaleDuration(vm.gpsStaleSeconds)}' : '';
    return Row(children: [
      Text('alt $altStr',
          style: TextStyle(
              fontSize: 14,
              color: cAltAcc,
              fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(width: 12),
      Text('$accStr$staleStr',
          style: TextStyle(
              fontSize: 14,
              color: stale ? pal.stale : cAltAcc,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  Widget _timeRow({required double fontSize}) {
    // GPS-calibrated time: the offset is updated on each fix; between fixes the
    // system clock advances, so this ticks every second as the screen rebuilds.
    final now = DateTime.now().add(vm.gpsClockOffset);
    final dateStr = formatDateYmd(now, utc: vm.timeUtc);
    final timeStr = formatTimeHms(now, utc: vm.timeUtc);
    final color = vm.dayMode ? (vm.timeUtc ? kDGps : kDAmb) : kN2;
    final labelColor = vm.dayMode ? (vm.timeUtc ? kDGpsL : kDAmbs) : kN3;
    final label = vm.timeUtc ? 'UTC' : 'LCL';
    final labelSize = fontSize >= 16 ? 12.0 : 11.0;
    return GestureDetector(
      onLongPress: actions.toggleTimeZone,
      behavior: HitTestBehavior.opaque,
      child: Row(children: [
        Text(dateStr,
            style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Text(timeStr,
            style: TextStyle(
                fontSize: fontSize,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                color: labelColor,
                letterSpacing: 1.5)),
      ]),
    );
  }
}
