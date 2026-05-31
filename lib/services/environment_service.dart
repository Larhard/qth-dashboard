import 'package:flutter/services.dart';

/// Streams environmental and motion sensor readings from Android hardware.
///
/// The EventChannel is completely idle when no listener is attached — zero
/// battery or CPU cost to the main dashboard.  Activate by subscribing to
/// [stream]; the Android side registers SensorManager listeners and starts
/// emitting at ~2 Hz.  Unsubscribe to stop the sensors.
///
/// Map keys emitted per packet:
///   available   List<String>   sensor keys that exist on this device
///   temperature double?  °C   TYPE_AMBIENT_TEMPERATURE (rare — Samsung/some flagships)
///   pressure    double?  hPa  TYPE_PRESSURE (barometer, very common)
///   light       double?  lux  TYPE_LIGHT (common)
///   humidity    double?  %RH  TYPE_RELATIVE_HUMIDITY (rare)
///   steps       double?  Δ    TYPE_STEP_COUNTER, delta since debug screen opened
///   mag_x/y/z   double?  µT   TYPE_MAGNETIC_FIELD axes
///   battery_pct double?  %    BatteryManager level
///   battery_temp double? °C   BatteryManager temperature (EXTRA_TEMPERATURE ÷ 10)
class EnvironmentService {
  static const _ch = EventChannel('qth_helper/environment');
  static final instance = EnvironmentService._();
  EnvironmentService._();

  Stream<Map<String, dynamic>> get stream =>
      _ch.receiveBroadcastStream()
         .map((d) => Map<String, dynamic>.from(d as Map));
}
