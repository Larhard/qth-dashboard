import 'package:flutter/widgets.dart';

/// Largest font size (≤ [maxSize], ≥ [minSize]) at which [text] fits within
/// [maxWidth] in at most [maxLines] lines.
///
/// This underpins the no-scroll layout contract (constitution §3): variable-width
/// names shrink to fit rather than overflow. It measures exactly with a
/// [TextPainter], so text that already fits at [maxSize] is returned unchanged
/// (no unnecessary shrinkage). Pure function of its inputs — no widget state.
double fitFontSize(
  String text,
  double maxWidth, {
  double maxSize = 32,
  double minSize = 18,
  int maxLines = 2,
  FontWeight weight = FontWeight.w700,
}) {
  if (maxWidth <= 0 || text.isEmpty) return maxSize;
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: maxSize, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  final lines = tp.computeLineMetrics().length;
  if (lines <= maxLines) return maxSize;
  return (maxSize * maxLines / lines).clamp(minSize, maxSize);
}
