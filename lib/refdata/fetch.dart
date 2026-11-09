/// Download orchestration shared by the build tool and the on-device updater.
/// Pure Dart: the HTTP GET is injected, so this file has no dart:io / Flutter
/// dependency and the same loop runs in `tool/fetch_refs.dart` and in the app.
library;

import 'dart:convert';

import '../config/ref_sources.dart';
import '../models/ham_ref.dart';
import '../models/poi_category.dart';
import 'parsers.dart';

typedef HttpGet = Future<String> Function(String url);
typedef FetchResult = ({List<HamRef> refs, int failedParts});

/// Downloads and parses every reference of [c] (see [RefFetch]).
///
/// Multi-request sources run sequentially with the source's pause (override
/// with [pause]) to be polite to volunteer-run servers. A failing part is
/// skipped (counted in the result) rather than aborting the whole update;
/// more than half failing throws. [onProgress] reports requests done / total
/// (the total can grow while HEMA's regions are discovered).
Future<FetchResult> fetchRefs(
  PoiCategory c,
  HttpGet get, {
  DateTime? today,
  void Function(int done, int total)? onProgress,
  Duration? pause,
}) async {
  final src = refSources[c];
  if (src == null) throw UnsupportedError('${c.id}: no download source');
  final wait = pause ?? src.pause;
  switch (src.fetch) {
    case RefFetch.hemaSite:
      return _fetchHema(src, get, onProgress, wait);
    case RefFetch.single:
      final refs = _parser(c)(await get(src.url), today: today);
      onProgress?.call(1, 1);
      return (refs: refs, failedParts: 0);
    case RefFetch.parts:
      return _fetchParts(c, src, get, today, onProgress, wait);
  }
}

RefParser _parser(PoiCategory c) =>
    parserFor(c) ?? (throw UnsupportedError('${c.id}: no parser'));

Future<FetchResult> _fetchParts(PoiCategory c, RefSource src, HttpGet get, DateTime? today,
    void Function(int, int)? onProgress, Duration pause) async {
  final parse = _parser(c);
  final keys = src.staticKeys ??
      (jsonDecode(await get(src.url)) as List).map((e) => '$e').toList();
  final out = <HamRef>[];
  final seen = <String>{};
  var failed = 0;
  for (var i = 0; i < keys.length; i++) {
    try {
      final url = src.partUrl!.replaceAll('{key}', Uri.encodeQueryComponent(keys[i]));
      for (final r in parse(await get(url), today: today)) {
        if (seen.add(r.ref)) out.add(r); // parts can overlap at region borders
      }
    } catch (_) {
      failed++;
    }
    onProgress?.call(i + 1, keys.length);
    if (i + 1 < keys.length) await Future<void>.delayed(pause);
  }
  _checkFailures(c.id, failed, keys.length);
  return (refs: out, failedParts: failed);
}

/// HEMA: countries → per country (regions list + map markers) → per region
/// (summit rows). Rows are joined to marker positions by summitKey.
Future<FetchResult> _fetchHema(
    RefSource src, HttpGet get, void Function(int, int)? onProgress, Duration pause) async {
  final base = src.url;
  final countries = parseHemaCountries(await get('${base}countries.jsp'));
  if (countries.isEmpty) throw const FormatException('HEMA: no countries found');

  var total = countries.length * 2, done = 0, failed = 0;
  Future<String?> step(String url) async {
    await Future<void>.delayed(pause);
    try {
      return await get(url);
    } catch (_) {
      failed++;
      return null;
    } finally {
      onProgress?.call(++done, total);
    }
  }

  final out = <HamRef>[];
  final seen = <String>{};
  for (final cc in countries) {
    final q = Uri.encodeQueryComponent(cc);
    final countryHtml = await step('${base}country.jsp?countryCode=$q');
    final regions = countryHtml == null ? const <String>[] : parseHemaRegions(countryHtml, cc);
    final mapHtml =
        await step('${base}mapping.jsp?countryCode=$q&regionCode=0&summitKey=0&action=&genericKey=');
    if (mapHtml == null) continue; // no positions for this country — skip its regions
    total += regions.length;
    final pos = parseHemaMarkers(mapHtml);
    for (final rc in regions) {
      final html = await step(
          '${base}region.jsp?countryCode=$q&regionCode=${Uri.encodeQueryComponent(rc)}');
      if (html == null) continue;
      for (final r in parseHemaRegionRows(html)) {
        final p = pos[r.key];
        final ref = '$cc/$rc-${r.num}';
        if (p == null || !seen.add(ref)) continue;
        out.add(HamRef(ref: ref, name: r.name, lat: p.lat, lon: p.lon, altM: r.altM));
      }
    }
  }
  _checkFailures('hema', failed, done);
  return (refs: out, failedParts: failed);
}

void _checkFailures(String id, int failed, int total) {
  if (total > 0 && failed * 2 > total) {
    throw StateError('$id: $failed of $total requests failed');
  }
}
