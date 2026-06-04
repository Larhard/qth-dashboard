import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/utils/formatting.dart';

/// These functions render the numbers the user actually reads on the dashboard
/// (speed, distance to a waypoint, altitude, elapsed time).  A regression in the
/// unit conversions or rounding rules would silently mislead — exactly the kind
/// of thing the "honest" design principle forbids — so they are worth pinning.
void main() {
  group('formatSpeed', () {
    test('metric: m/s → km/h with sub-0.5 floor and 1-decimal/integer rule', () {
      expect(formatSpeed(0, SpeedUnit.metric), '0.0 km/h');
      expect(formatSpeed(0.1, SpeedUnit.metric), '0.0 km/h');     // below floor
      expect(formatSpeed(1.0, SpeedUnit.metric), '3.6 km/h');     // 1 decimal < 10
      expect(formatSpeed(10.0, SpeedUnit.metric), '36 km/h');     // integer ≥ 10
    });
    test('nautical: m/s → knots', () {
      expect(formatSpeed(0, SpeedUnit.nautical), '0.0 kn');
      expect(formatSpeed(1.0, SpeedUnit.nautical), '1.9 kn');
      expect(formatSpeed(10.0, SpeedUnit.nautical), '19 kn');
    });
    test('imperial: m/s → mph', () {
      expect(formatSpeed(10.0, SpeedUnit.imperial), '22 mph');
    });
  });

  group('formatDistanceUnit', () {
    test('metric switches m → km at 1 km and drops decimals ≥ 100 km', () {
      expect(formatDistanceUnit(0.5, SpeedUnit.metric), '500 m');
      expect(formatDistanceUnit(1.0, SpeedUnit.metric), '1.0 km');
      expect(formatDistanceUnit(12.34, SpeedUnit.metric), '12.3 km');
      expect(formatDistanceUnit(150.0, SpeedUnit.metric), '150 km');
    });
    test('nautical uses metres below 0.05 nm, then nm tiers', () {
      expect(formatDistanceUnit(0.05, SpeedUnit.nautical), '50 m'); // 0.05 km ≈ 0.027 nm → metres
      expect(formatDistanceUnit(1.0, SpeedUnit.nautical), '0.54 nm');
      expect(formatDistanceUnit(100.0, SpeedUnit.nautical), '54.0 nm');
    });
    test('imperial uses feet below 0.1 mi, then mi tiers', () {
      expect(formatDistanceUnit(1.0, SpeedUnit.imperial), '0.62 mi');
      expect(formatDistanceUnit(200.0, SpeedUnit.imperial), '124 mi');
    });
  });

  group('formatAlt', () {
    test('metric = metres, imperial/nautical = feet', () {
      expect(formatAlt(100, SpeedUnit.metric), '100 m');
      expect(formatAlt(100, SpeedUnit.imperial), '328 ft');
      expect(formatAlt(100, SpeedUnit.nautical), '328 ft');
    });
  });

  group('formatElapsed (granularity buckets)', () {
    test('< 60 s → seconds', () {
      expect(formatElapsed(const Duration(seconds: 42)), '42s');
    });
    test('< 60 min → minutes (+seconds when non-zero)', () {
      expect(formatElapsed(const Duration(minutes: 5, seconds: 30)), '5m 30s');
      expect(formatElapsed(const Duration(minutes: 5)), '5m');
    });
    test('< 24 h → hours (+minutes when non-zero)', () {
      expect(formatElapsed(const Duration(hours: 3, minutes: 15)), '3h 15m');
      expect(formatElapsed(const Duration(hours: 3)), '3h');
    });
    test('≥ 1 day → days (+hours when non-zero)', () {
      expect(formatElapsed(const Duration(days: 2, hours: 11)), '2d 11h');
      expect(formatElapsed(const Duration(days: 2)), '2d');
    });
  });
}
