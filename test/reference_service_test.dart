import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:qth_dashboard/models/poi_category.dart';
import 'package:qth_dashboard/services/poi_service.dart';
import 'package:qth_dashboard/services/reference_service.dart';

/// Loads the real bundled tables through the real services.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('qth_refs_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

  setUpAll(() async {
    await GetStorage.init();
    await ReferenceService.instance.init();
    PoiService.instance.init();
  });

  final bundled = File('assets/refs/manifest.json').existsSync();

  test('awaited loads complete (regression: load() future waited on itself)', () async {
    final rs = ReferenceService.instance;
    // Two concurrent callers share one load; both must complete.
    final both = await Future.wait([rs.load(PoiCategory.gia), rs.load(PoiCategory.gia)])
        .timeout(const Duration(seconds: 20));
    expect(both[0], isNotNull);
    expect(both[1], same(both[0]));
  }, skip: bundled ? false : 'no bundled reference data (run fetch_refs)');

  test('Nearby list over all reference programs completes, nearest first', () async {
    final hits = await PoiService.instance
        .nearby(50.06, 19.94, PoiCategory.references, perCategory: 40, maxItems: 150)
        .timeout(const Duration(seconds: 60));
    expect(hits, isNotEmpty);
    for (var i = 1; i < hits.length; i++) {
      expect(hits[i].distKm, greaterThanOrEqualTo(hits[i - 1].distKm));
    }
    ReferenceService.instance.retainOnly(const {});
    expect(ReferenceService.instance.isLoaded(PoiCategory.sota), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)), skip: bundled ? false : 'no bundled reference data');
}
