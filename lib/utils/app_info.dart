import 'package:package_info_plus/package_info_plus.dart';

/// Single runtime source of the app version, read from the APK metadata that
/// Gradle bakes in from `pubspec.yaml`'s `version: X.Y.Z+B`.
///
/// Populated once in `main()` via [load], then read synchronously everywhere
/// (e.g. the About screen).  Because it comes from the compiled package, it can
/// never drift out of sync with pubspec — there is nothing to hand-edit.
class AppInfo {
  AppInfo._();

  static String version = '';   // e.g. "1.1.1"
  static String build   = '';   // e.g. "5"

  /// "v1.1.1 (build 5)" — or "v1.1.1" if the build number is unavailable.
  static String get display =>
      build.isEmpty ? 'v$version' : 'v$version (build $build)';

  /// "v1.1.1+5" — compact form for the licence page.
  static String get short =>
      build.isEmpty ? 'v$version' : 'v$version+$build';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build   = info.buildNumber;
    } catch (_) {
      // Leave blank on failure; the UI degrades to an empty/short string.
    }
  }
}
