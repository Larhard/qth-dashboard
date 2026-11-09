/// Minimal RFC 4180 CSV reader. Pure Dart.
///
/// Streams rows to a callback instead of materialising the whole file, because
/// upstream reference lists are large (SOTA / WWFF ≈ 25 MB, ~200k rows) and the
/// parse runs on a phone. Handles quoted fields with embedded separators,
/// escaped quotes (`""`), CR/LF/CRLF line endings, newlines inside quotes, and a
/// leading UTF-8 BOM.
library;

void forEachCsvRow(
  String text,
  void Function(List<String> row) onRow, {
  String separator = ',',
}) {
  final sep = separator.codeUnitAt(0);
  const quote = 0x22, cr = 0x0D, lf = 0x0A;

  var i = (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) ? 1 : 0; // skip BOM
  final n = text.length;
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldStarted = false; // distinguishes "no row" from "row with empty field"

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    onRow(row);
    row = <String>[];
    fieldStarted = false;
  }

  while (i < n) {
    final c = text.codeUnitAt(i);
    if (inQuotes) {
      if (c == quote) {
        if (i + 1 < n && text.codeUnitAt(i + 1) == quote) {
          field.writeCharCode(quote); // escaped quote
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.writeCharCode(c);
      }
      i++;
      continue;
    }
    if (c == quote) {
      inQuotes = true;
      fieldStarted = true;
    } else if (c == sep) {
      endField();
      fieldStarted = true;
    } else if (c == cr || c == lf) {
      if (fieldStarted || field.isNotEmpty || row.isNotEmpty) endRow();
      if (c == cr && i + 1 < n && text.codeUnitAt(i + 1) == lf) i++;
    } else {
      field.writeCharCode(c);
      fieldStarted = true;
    }
    i++;
  }
  if (fieldStarted || field.isNotEmpty || row.isNotEmpty) endRow();
}

/// Convenience for small inputs (tests).
List<List<String>> parseCsv(String text, {String separator = ','}) {
  final rows = <List<String>>[];
  forEachCsvRow(text, rows.add, separator: separator);
  return rows;
}
