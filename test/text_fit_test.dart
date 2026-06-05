import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/utils/text_fit.dart';

/// `fitFontSize` underpins the no-scroll layout contract (constitution §3): names
/// must shrink to fit rather than overflow. These tests pin the boundary behaviour
/// without depending on exact glyph metrics (the test environment's font differs
/// from a device's).
void main() {
  // TextPainter.layout needs the binding initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('degenerate inputs return maxSize unchanged', () {
    expect(fitFontSize('anything', 0, maxSize: 32), 32);
    expect(fitFontSize('', 1000, maxSize: 32), 32);
  });

  test('text that fits in the line budget keeps the full size', () {
    expect(fitFontSize('Rio', 1000, maxSize: 32, maxLines: 2), 32);
  });

  test('a long name in a narrow box shrinks, but never below minSize', () {
    final size = fitFontSize(
      'Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch',
      40,
      maxSize: 32,
      minSize: 18,
      maxLines: 2,
    );
    expect(size, lessThan(32));
    expect(size, greaterThanOrEqualTo(18));
  });

  test('result is always within [minSize, maxSize]', () {
    for (final w in [10.0, 25.0, 50.0, 100.0, 500.0]) {
      final size = fitFontSize('Some City Name That Is Moderately Long', w,
          maxSize: 30, minSize: 12);
      expect(size, inInclusiveRange(12, 30));
    }
  });
}
