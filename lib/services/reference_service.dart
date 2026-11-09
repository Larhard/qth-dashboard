import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ham_ref.dart';
import '../models/poi_category.dart';
import '../refdata/ref_table.dart';

/// Where a program's data currently comes from.
enum RefOrigin { bundled, downloaded }

/// Data status of one reference program (for the settings screen).
class RefInfo {
  final RefOrigin origin;
  final DateTime date;
  final int count;
  const RefInfo(this.origin, this.date, this.count);
}

/// Loads and caches the amateur-radio reference tables.
///
/// Two possible copies per program:
///   • bundled  — `assets/refs/<id>.tsv`, generated at build time by
///                `tool/fetch_refs.dart` (described by `assets/refs/manifest.json`);
///   • downloaded — `<app-support>/refs/<id>.tsv`, written by "Update via network".
/// Whichever is NEWER is used, so an app update that ships fresher data beats an
/// old download and vice versa.
///
/// Tables are loaded lazily (only categories that are actually shown) and parsed
/// in a background isolate, so the UI never janks on SOTA's ~170k rows. Only the
/// tables in use stay in memory (see [retainOnly]).
class ReferenceService {
  ReferenceService._();
  static final instance = ReferenceService._();

  static final _store = GetStorage();
  static String _metaKey(PoiCategory c) => 'refmeta_${c.id}';

  final Map<PoiCategory, RefInfo> _bundled = {};
  final Map<PoiCategory, RefTable> _tables = {};
  final Map<PoiCategory, Future<RefTable?>> _loading = {};
  Directory? _dir;

  /// Bumped whenever a table finishes loading or is replaced — listeners
  /// (dashboard, list view) re-query when it changes.
  final revision = ValueNotifier<int>(0);

  Future<void> init() async {
    try {
      final m = jsonDecode(await rootBundle.loadString('assets/refs/manifest.json'));
      final cats = (m['categories'] as Map?) ?? const {};
      for (final c in PoiCategory.references) {
        final e = cats[c.id];
        if (e is! Map) continue;
        final date = DateTime.tryParse('${e['date']}');
        final count = (e['count'] as num?)?.toInt() ?? 0;
        if (date != null && count > 0) _bundled[c] = RefInfo(RefOrigin.bundled, date, count);
      }
    } catch (_) {
      // No bundled references in this build (fetch_refs not run) — that's fine.
    }
    try {
      _dir = Directory('${(await getApplicationSupportDirectory()).path}/refs');
    } catch (_) {}
  }

  RefInfo? _downloaded(PoiCategory c) {
    final m = _store.read<Map>(_metaKey(c));
    if (m == null) return null;
    final date = DateTime.tryParse('${m['date']}');
    final count = (m['count'] as num?)?.toInt() ?? 0;
    return (date == null || count <= 0) ? null : RefInfo(RefOrigin.downloaded, date, count);
  }

  /// The copy that will be used (newest of bundled vs downloaded), or null.
  RefInfo? info(PoiCategory c) {
    final b = _bundled[c], d = _downloaded(c);
    if (d == null) return b;
    if (b == null) return d;
    return d.date.isBefore(b.date) ? b : d;
  }

  bool hasData(PoiCategory c) => info(c) != null;
  bool isLoaded(PoiCategory c) => _tables.containsKey(c);
  RefTable? table(PoiCategory c) => _tables[c];

  /// Loads (once) and returns the table for [c]; null if there's no data.
  Future<RefTable?> load(PoiCategory c) {
    final t = _tables[c];
    if (t != null) return Future.value(t);
    return _loading[c] ??= _load(c).whenComplete(() => _loading.remove(c));
  }

  Future<RefTable?> _load(PoiCategory c) async {
    final which = info(c);
    if (which == null) return null;
    try {
      // Raw bytes → table in ONE background isolate: no UTF-8 decode of the
      // whole file and no copy of a 14 MB String between isolates.
      final RefTable table;
      if (which.origin == RefOrigin.downloaded) {
        table = await compute(_tableFromFile, '${_dir!.path}/${c.id}.tsv');
      } else {
        final bd = await rootBundle.load('assets/refs/${c.id}.tsv');
        table = await compute(RefTable.fromBytes, bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
      }
      if (table.isEmpty) throw const FormatException('empty table');
      _tables[c] = table;
      revision.value++;
      return table;
    } catch (_) {
      // A broken download must not hide the bundled copy: drop it and retry once.
      if (which.origin == RefOrigin.downloaded) {
        await deleteDownloaded(c);
        return _bundled[c] == null ? null : _load(c);
      }
      return null;
    }
  }

  /// Frees memory for a category the user disabled.
  void unload(PoiCategory c) => _tables.remove(c);

  /// Frees every loaded table except [keep]. A table costs about its file size
  /// in RAM (SOTA ≈ 14 MB) and reloads in about a second, so only what's on
  /// screen stays resident; this keeps the app small while it runs in the
  /// background with the overlay.
  void retainOnly(Set<PoiCategory> keep) => _tables.removeWhere((c, _) => !keep.contains(c));

  /// Stores a freshly downloaded, already-normalized file and swaps it in.
  Future<void> installDownloaded(PoiCategory c, String normalizedText) async {
    final header = RefFileHeader.parse(normalizedText.substring(
        0, normalizedText.indexOf('\n').clamp(0, normalizedText.length)));
    if (header == null || header.count <= 0) throw const FormatException('empty reference file');
    final dir = _dir ?? (throw StateError('storage unavailable'));
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/${c.id}.tsv.part');
    await tmp.writeAsString(normalizedText, flush: true);
    await tmp.rename('${dir.path}/${c.id}.tsv'); // atomic swap
    await _store.write(_metaKey(c), {
      'date': header.date.toIso8601String().substring(0, 10),
      'count': header.count,
    });
    _tables[c] = await compute(RefTable.fromTsv, normalizedText);
    revision.value++;
  }

  /// Forget a download and fall back to the bundled copy (if any).
  Future<void> deleteDownloaded(PoiCategory c) async {
    await _store.remove(_metaKey(c));
    try {
      final f = File('${_dir?.path}/${c.id}.tsv');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _tables.remove(c);
    revision.value++;
  }
}

/// Isolate entry: read a downloaded reference file and index it.
RefTable _tableFromFile(String path) => RefTable.fromBytes(File(path).readAsBytesSync());
