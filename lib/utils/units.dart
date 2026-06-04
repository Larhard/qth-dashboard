/// Barrel kept for backwards compatibility.
///
/// The contents that used to live here are now split by concern:
///   • colours + the [Palette] resolver → `lib/theme/palette.dart`
///   • unit/value formatting              → `lib/utils/formatting.dart`
///   • persisted display preferences      → `lib/settings/display_settings.dart`
///
/// Prefer importing the specific file in new code; this re-export means existing
/// `import '.../utils/units.dart'` sites keep compiling unchanged.
library;

export '../theme/palette.dart';
export 'formatting.dart';
export '../settings/display_settings.dart';
