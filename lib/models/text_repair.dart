/// Repairs text damage that several upstream reference lists ship with.
///
/// Pure Dart — runs inside [HamRef.toTsv], so the build tool and the on-device
/// updater clean every name the same way, whatever the source.
///
/// Fixes, in order:
///  • Mojibake — UTF-8 bytes that a server decoded as Windows-1252 and then
///    re-encoded ("KÄ™pa" → "Kępa", "SÃ£o" → "São"), sometimes two layers deep
///    ("FÃƒÂ¢ntÃƒÂ¢na" → "Fântâna"). Seen in GMA's map service (GMA, WCA, MOTA,
///    GIA, ARLHS, WLOTA) and a few WWFF / POTA / BOTA entries.
///  • HTML entities left in names ("M&#039;Bé", "&amp;").
///  • Soft hyphens and non-breaking / repeated spaces.
library;

/// Windows-1252 character → byte, for 0x80–0xFF. The five bytes cp1252 leaves
/// undefined (0x81 0x8D 0x8F 0x90 0x9D) pass through as Latin-1 controls,
/// which is what lenient decoders produce for them.
final Map<int, int> _cp1252 = () {
  const hi = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
  ];
  return {
    for (var i = 0; i < hi.length; i++) hi[i]: 0x80 + i,
    for (var b = 0xA0; b <= 0xFF; b++) b: b,
  };
}();

/// Only accept decoded characters that real place names use (Latin, Greek,
/// Cyrillic, Latin Extended Additional, punctuation). This rejects accidental
/// matches such as Czech "ÚŽ" (bytes DA 8E → Arabic "ڎ").
bool _plausible(int cp) =>
    (cp >= 0xA0 && cp < 0x0590) || (cp >= 0x1E00 && cp < 0x1F00) || (cp >= 0x2000 && cp < 0x2150);

/// One pass: replace every cp1252-spelled UTF-8 sequence by its character.
String _unMojibakeOnce(String s) {
  final cps = s.runes.toList();
  final out = StringBuffer();
  var i = 0;
  while (i < cps.length) {
    final lead = _cp1252[cps[i]];
    final n = lead == null
        ? 0
        : lead >= 0xC2 && lead <= 0xDF
            ? 2
            : lead >= 0xE0 && lead <= 0xEF
                ? 3
                : lead >= 0xF0 && lead <= 0xF4
                    ? 4
                    : 0;
    if (n > 0 && i + n <= cps.length) {
      final bytes = [lead!];
      for (var k = 1; k < n; k++) {
        final b = _cp1252[cps[i + k]];
        if (b == null || b < 0x80 || b > 0xBF) break;
        bytes.add(b);
      }
      if (bytes.length == n) {
        final cp = _decodeUtf8(bytes);
        if (cp != null && _plausible(cp)) {
          out.writeCharCode(cp);
          i += n;
          continue;
        }
      }
    }
    out.writeCharCode(cps[i]);
    i++;
  }
  return out.toString();
}

/// Strict decode of one 2–4 byte UTF-8 sequence (continuations pre-checked);
/// null for overlong forms and surrogates.
int? _decodeUtf8(List<int> b) {
  final cp = switch (b.length) {
    2 => ((b[0] & 0x1F) << 6) | (b[1] & 0x3F),
    3 => ((b[0] & 0x0F) << 12) | ((b[1] & 0x3F) << 6) | (b[2] & 0x3F),
    _ => ((b[0] & 0x07) << 18) | ((b[1] & 0x3F) << 12) | ((b[2] & 0x3F) << 6) | (b[3] & 0x3F),
  };
  const minFor = {2: 0x80, 3: 0x800, 4: 0x10000};
  if (cp < minFor[b.length]! || (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF) return null;
  return cp;
}

final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|amp|quot|apos|lt|gt|nbsp|acute);');
const _named = {'amp': '&', 'quot': '"', 'apos': "'", 'lt': '<', 'gt': '>', 'nbsp': ' ', 'acute': '´'};

String _unEntity(String s) => s.replaceAllMapped(_entity, (m) {
      final e = m[1]!;
      if (!e.startsWith('#')) return _named[e]!;
      final cp = e[1] == 'x' || e[1] == 'X' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
      return cp == null || cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
          ? m[0]!
          : String.fromCharCode(cp);
    });

final _spaces = RegExp(r'[\s ]+');
// Quick pre-check so clean ASCII / correctly encoded text skips the work.
final _suspect = RegExp(r'[Â-ô]|&|­| |\s\s');

/// Clean one text field (see library doc). Idempotent.
String repairText(String s) {
  if (!_suspect.hasMatch(s)) return s;
  for (var pass = 0; pass < 3; pass++) {
    final t = _unMojibakeOnce(s);
    if (t == s) break;
    s = t;
  }
  return _unEntity(s).replaceAll('­', '').replaceAll(_spaces, ' ').trim();
}
