import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/utils/anchor_math.dart';

/// Guard test: the anchor-alarm thresholds that exist in BOTH languages must
/// agree.  Dart cannot share a compile-time constant with Kotlin, so the values
/// are duplicated:
///   • `lib/utils/anchor_math.dart` — the pure, unit-tested SPEC of the contract.
///   • `android/.../Tuning.kt`      — the native runtime AUTHORITY (the background
///     service evaluates the alarm with the Flutter engine dead).
///
/// Without this test the two copies WILL drift apart silently.  This reads the
/// Kotlin source and asserts the shared values match the Dart spec, failing the
/// build the moment someone changes one side only.
void main() {
  final tuningKt = File(
    'android/app/src/main/kotlin/com/elgassia/qthdashboard/Tuning.kt',
  );

  int ktInt(String source, String name) {
    final m = RegExp('const val $name\\s*=\\s*([0-9_]+)').firstMatch(source);
    expect(m, isNotNull, reason: '`$name` not found in Tuning.kt — did it move/rename?');
    return int.parse(m!.group(1)!.replaceAll('_', ''));
  }

  group('native Tuning.kt ↔ Dart AnchorMath threshold sync', () {
    late String src;
    setUpAll(() {
      expect(tuningKt.existsSync(), isTrue,
          reason: 'Tuning.kt missing at ${tuningKt.path}');
      src = tuningKt.readAsStringSync();
    });

    test('GPS warning seconds agree', () {
      expect(ktInt(src, 'GPS_WARN_S'), AnchorMath.gpsWarningSeconds,
          reason: 'Tuning.Anchor.GPS_WARN_S must equal AnchorMath.gpsWarningSeconds');
    });

    test('GPS alarm seconds agree', () {
      expect(ktInt(src, 'GPS_ALARM_S'), AnchorMath.gpsAlarmSeconds,
          reason: 'Tuning.Anchor.GPS_ALARM_S must equal AnchorMath.gpsAlarmSeconds');
    });

    test('escalation ordering is sane (warn before alarm, both positive)', () {
      expect(AnchorMath.gpsWarningSeconds, greaterThan(0));
      expect(AnchorMath.gpsAlarmSeconds, greaterThan(AnchorMath.gpsWarningSeconds));
    });
  });
}
