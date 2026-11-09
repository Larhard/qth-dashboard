import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:qth_dashboard/services/waypoint_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('qth_wpt_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

  setUpAll(() async {
    await GetStorage.init();
    WaypointService.instance.load();
  });

  test('picking a POI sets it as the active waypoint, reusing a saved one', () {
    final ws = WaypointService.instance;
    final mob = ws.addEmergency(54.0, 18.0);
    final before = ws.waypoints.length;

    final a = ws.navigateTo('SP/BZ-005 Turbacz', 49.54278, 20.11139);
    expect(ws.activeId, a.id);
    expect(ws.waypoints.length, before + 1);

    // Same POI again (e.g. from the list next day): no duplicate.
    final again = ws.navigateTo('SP/BZ-005 Turbacz', 49.542781, 20.111391);
    expect(again.id, a.id);
    expect(ws.waypoints.length, before + 1);

    // A different POI becomes the new target; MOB tracking is untouched.
    final b = ws.navigateTo('Kraków', 50.06143, 19.93658);
    expect(ws.activeId, b.id);
    expect(ws.emergencyId, mob.id);
  });
}
