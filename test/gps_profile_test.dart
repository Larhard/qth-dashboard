import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/config/tuning.dart';

/// The GPS cadence profile encodes the project's two priorities (constitution
/// §7.5, §5.9): anchoring is bulletproof (never throttled), navigation saves power
/// off-charger. These pin that selection so a future tuning edit can't silently
/// flip, e.g., anchoring to a power-saving cadence.
void main() {
  group('GpsTuning.profile', () {
    test('anchoring is full robustness regardless of charger', () {
      final onCharger = GpsTuning.profile(anchoring: true, charging: true);
      final offCharger = GpsTuning.profile(anchoring: true, charging: false);
      expect(onCharger, offCharger, reason: 'anchoring must not depend on charger');
      expect(onCharger.distanceFilterM, GpsTuning.anchorDistanceFilterM);
      expect(onCharger.interval, GpsTuning.anchorInterval);
      expect(onCharger.distanceFilterM, 0, reason: 'stationary fixes must keep flowing');
    });

    test('navigating on charger → responsive profile', () {
      final p = GpsTuning.profile(anchoring: false, charging: true);
      expect(p.distanceFilterM, GpsTuning.navDistanceFilterChargingM);
      expect(p.interval, GpsTuning.navIntervalCharging);
    });

    test('navigating off charger → economical profile', () {
      final p = GpsTuning.profile(anchoring: false, charging: false);
      expect(p.distanceFilterM, GpsTuning.navDistanceFilterBatteryM);
      expect(p.interval, GpsTuning.navIntervalBattery);
    });

    test('off-charger navigation is no more frequent than on-charger (saves power)', () {
      final onC = GpsTuning.profile(anchoring: false, charging: true);
      final offC = GpsTuning.profile(anchoring: false, charging: false);
      expect(offC.interval, greaterThanOrEqualTo(onC.interval));
      expect(offC.distanceFilterM, greaterThanOrEqualTo(onC.distanceFilterM));
    });
  });
}
