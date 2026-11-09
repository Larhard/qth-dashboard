import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/ref_sources.dart';
import '../models/ham_ref.dart';
import '../models/poi_category.dart';
import '../refdata/fetch.dart';
import '../refdata/parsers.dart';
import 'reference_service.dart';

/// Downloads a program's full reference list from its official source and
/// installs it — on-device counterpart of `tool/fetch_refs.dart`, using the very
/// same parsers. This is the ONLY network access in the app, and it happens
/// only when the user taps "Update" in Settings.
class RefUpdater {
  RefUpdater._();

  static bool canUpdate(PoiCategory c) => refSources[c] != null;

  /// Returns the number of references installed. Throws on network/format errors
  /// (the previous data stays in place).
  static Future<int> update(
    PoiCategory c, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final src = refSources[c];
    if (src == null) {
      throw UnsupportedError('${c.label}: no download source');
    }
    final client = HttpClient()
      ..userAgent = 'QTH-Dashboard reference updater'
      ..connectionTimeout = const Duration(seconds: 20);

    // Multi-part sources (GMA regions, WCA prefixes): many small files, parsed
    // as they arrive by the shared orchestrator; progress = parts done / total.
    if (src.isMultiPart) {
      try {
        Future<String> get(String url) async {
          final res = await (await client.getUrl(Uri.parse(url))).close();
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
          return utf8.decode(await res.fold<List<int>>(<int>[], (b, d) => b..addAll(d)),
              allowMalformed: true);
        }

        final r = await fetchRefs(c, get, onProgress: (d, t) => onProgress?.call(d, t));
        if (r.refs.isEmpty) throw const FormatException('parsed 0 references');
        await ReferenceService.instance
            .installDownloaded(c, encodeRefFile(c.id, DateTime.now().toUtc(), r.refs));
        return r.refs.length;
      } finally {
        client.close();
      }
    }

    final String body;
    try {
      final res = await (await client.getUrl(Uri.parse(src.url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : null;
      final b = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in res) {
        b.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      body = utf8.decode(b.takeBytes(), allowMalformed: true);
    } finally {
      client.close();
    }

    // Parse + normalize off the UI thread (SOTA is ~25 MB of CSV).
    final normalized = await compute(_normalize, (id: c.id, body: body));
    final count = RefFileHeader.parse(normalized.split('\n').first)?.count ?? 0;
    if (count == 0) throw const FormatException('parsed 0 references — source format changed?');
    await ReferenceService.instance.installDownloaded(c, normalized);
    return count;
  }
}

String _normalize(({String id, String body}) a) {
  final c = PoiCategory.byId(a.id)!;
  final now = DateTime.now().toUtc();
  return encodeRefFile(c.id, now, parserFor(c)!(a.body, today: now));
}
