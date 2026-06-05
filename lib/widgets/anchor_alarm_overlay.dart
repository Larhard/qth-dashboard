import 'package:flutter/material.dart';
import '../services/anchor_service.dart';
import '../theme/palette.dart';

/// Full-screen anchor-alarm splash: a black↔red strobe with the alarm reason and
/// a hold-to-mute control. Shown on top of the dashboard while an un-muted alarm
/// is active. Stateless — the parent owns the two animation controllers and the
/// global [AnchorService] holds the live alarm data.
class AnchorAlarmOverlay extends StatelessWidget {
  final bool dayMode;

  /// Drives the black↔red blink (read-only here).
  final Animation<double> strobe;

  /// Hold-to-mute progress; driven forward while the user presses and reversed on
  /// release. A full sweep (its status listener, owned by the parent) mutes.
  final AnimationController muteController;

  const AnchorAlarmOverlay({
    super.key,
    required this.dayMode,
    required this.strobe,
    required this.muteController,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(dayMode);
    return AnimatedBuilder(
      animation: strobe,
      builder: (_, __) {
        final bright = strobe.value > 0.5;
        final fg = bright ? pal.emergency : pal.pick(Colors.white, Colors.black);
        final bg = bright
            ? pal.pick(Colors.white, Colors.black)
            : pal.pick(kDEmg.withValues(alpha: 0.9), kN0);
        final svc = AnchorService.instance;
        return Positioned.fill(
          child: Container(
            color: bg,
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.anchor, size: 72, color: fg),
                  const SizedBox(height: 16),
                  Text('ANCHOR ALARM',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: fg,
                        letterSpacing: 4,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    svc.gpsLost
                        ? 'GPS signal lost ${svc.gpsLossSeconds}s'
                        : 'Outside anchor radius!\n'
                            '${svc.distanceM?.round() ?? 0} m from anchor point',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: fg),
                  ),
                  const SizedBox(height: 48),
                  // Mute — must HOLD for 3 s (a tap won't dismiss it).
                  _muteHoldButton(pal, bright),
                  const SizedBox(height: 16),
                  // SAFETY: lifting the anchor is only available from the Waypoints
                  // screen. This splash only allows muting.
                  Text('Open Waypoints screen to lift anchor.',
                      style: TextStyle(
                          fontSize: 12,
                          color: bright
                              ? pal.pick(kDEmg.withValues(alpha: 0.55), kN3)
                              : pal.pick(Colors.white38, kN4))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Hold-to-mute control with a MOB-style progress bar. A tap does nothing; the
  /// alarm is muted only after a continuous 3-second hold.
  Widget _muteHoldButton(Palette pal, bool bright) {
    final fg = bright ? pal.emergency : pal.pick(Colors.white, Colors.black);
    return Listener(
      onPointerDown: (_) => muteController.forward(from: muteController.value),
      onPointerUp: (_) => muteController.reverse(),
      onPointerCancel: (_) => muteController.reverse(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: muteController,
        builder: (_, __) => Container(
          width: 240,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: fg, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(muteController.value > 0 ? 'KEEP HOLDING…' : 'HOLD 3s TO MUTE',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: fg)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: muteController.value,
                  minHeight: 6,
                  backgroundColor: fg.withValues(alpha: 0.20),
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
