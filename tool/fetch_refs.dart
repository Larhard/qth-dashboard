// Downloads the full world reference lists for the amateur-radio programs and
// writes the normalized files the app bundles (assets/refs/<id>.tsv) plus a
// manifest (assets/refs/manifest.json).
//
// It imports the SAME parsers the app uses for on-device updates
// (lib/refdata/parsers.dart), so bundled data and updates can never disagree.
//
// Usage (from the project root):
//   dart run tool/fetch_refs.dart                      # every program with a source
//   dart run tool/fetch_refs.dart --only sota,pota     # a subset
//   dart run tool/fetch_refs.dart --from-file sota=C:\dl\summitslist.csv
//   dart run tool/fetch_refs.dart --out assets/refs
//   dart run tool/fetch_refs.dart --renormalize     # re-clean existing files, no network
//
// Wrappers: scripts/fetch_refs.ps1 / scripts/fetch_refs.sh. The release scripts
// run this before building so every release ships references as of build time.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:qth_dashboard/config/ref_sources.dart';
import 'package:qth_dashboard/models/ham_ref.dart';
import 'package:qth_dashboard/models/poi_category.dart';
import 'package:qth_dashboard/refdata/fetch.dart';
import 'package:qth_dashboard/refdata/parsers.dart';

Future<void> main(List<String> args) async {
  var outDir = 'assets/refs';
  Set<String>? only;
  final fromFile = <String, String>{};
  var renormalize = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() => i + 1 < args.length ? args[++i] : _die('missing value for $a');
    switch (a) {
      case '--out':
        outDir = next();
      case '--only':
        only = next().split(',').map((s) => s.trim().toLowerCase()).toSet();
      case '--from-file':
        final kv = next().split('=');
        if (kv.length != 2) _die('--from-file expects id=path');
        fromFile[kv[0].trim().toLowerCase()] = kv[1].trim();
      case '--renormalize':
        renormalize = true;
      case '-h' || '--help':
        stdout.writeln('dart run tool/fetch_refs.dart [--only ids] [--from-file id=path] [--out dir] [--renormalize]');
        return;
      default:
        _die('unknown argument: $a');
    }
  }

  final dir = Directory(outDir)..createSync(recursive: true);
  final manifestFile = File('${dir.path}/manifest.json');
  final manifest = manifestFile.existsSync()
      ? (jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>)
      : <String, dynamic>{};
  final cats = (manifest['categories'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

  final today = DateTime.now().toUtc();
  var failures = 0;

  if (renormalize) {
    _renormalize(dir, only, cats);
    manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    return;
  }

  for (final cat in PoiCategory.references) {
    if (only != null && !only.contains(cat.id)) continue;
    final parser = parserFor(cat);
    final source = refSources[cat];
    final localPath = fromFile[cat.id];
    if (source == null && localPath == null) {
      stdout.writeln('- ${cat.id.padRight(6)} no source yet — skipped');
      continue;
    }
    if (localPath != null && (parser == null || source?.isMultiPart == true)) {
      stderr.writeln('✗ ${cat.id}: --from-file works only for single-file sources');
      failures++;
      continue;
    }
    try {
      final List<HamRef> refs;
      if (localPath != null) {
        refs = parser!(await File(localPath).readAsString(), today: today);
      } else {
        stdout.write('  ↓ ${cat.id} ');
        final r = await fetchRefs(cat, _download, today: today, onProgress: (done, total) {
          if (total > 1 && (done % 50 == 0 || done == total)) stdout.write('$done/$total ');
        });
        stdout.writeln(r.failedParts > 0 ? '(${r.failedParts} parts failed)' : '');
        refs = r.refs;
      }
      if (refs.isEmpty) throw StateError('parsed 0 references — format changed?');
      final text = encodeRefFile(cat.id, today, refs);
      final out = File('${dir.path}/${cat.id}.tsv');
      await out.writeAsString(text);
      cats[cat.id] = {
        'date': today.toIso8601String().substring(0, 10),
        'count': refs.length,
        'bytes': out.lengthSync(),
      };
      stdout.writeln('✓ ${cat.id.padRight(6)} ${refs.length.toString().padLeft(7)} refs  '
          '${(out.lengthSync() / 1048576).toStringAsFixed(1)} MB');
    } catch (e) {
      failures++;
      stderr.writeln('✗ ${cat.id.padRight(6)} FAILED: $e  (previous file, if any, kept)');
    }
  }

  manifest['generated'] = today.toIso8601String().substring(0, 10);
  manifest['categories'] = cats;
  manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('Manifest: ${manifestFile.path}');
  _client.close();
  if (failures > 0) exitCode = 1;
}

/// Re-runs the bundled files through the current codec (text repair etc.)
/// without downloading. Each file keeps its data date.
void _renormalize(Directory dir, Set<String>? only, Map<String, dynamic> cats) {
  for (final cat in PoiCategory.references) {
    if (only != null && !only.contains(cat.id)) continue;
    final f = File('${dir.path}/${cat.id}.tsv');
    if (!f.existsSync()) continue;
    final lines = f.readAsLinesSync();
    final header = lines.isEmpty ? null : RefFileHeader.parse(lines.first);
    if (header == null) {
      stderr.writeln('✗ ${cat.id}: bad header — skipped');
      continue;
    }
    final refs = lines.skip(1).map(HamRef.fromTsv).whereType<HamRef>().toList();
    final before = f.readAsStringSync();
    final after = encodeRefFile(cat.id, header.date, refs);
    if (after == before) continue;
    f.writeAsStringSync(after);
    final changed = _countDiff(before, after);
    (cats[cat.id] as Map?)?['bytes'] = f.lengthSync();
    stdout.writeln('✓ ${cat.id.padRight(6)} $changed lines cleaned');
  }
}

int _countDiff(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  var n = 0;
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) n++;
  }
  return n;
}

final _client = HttpClient()..userAgent = 'QTH-Dashboard reference updater';

Future<String> _download(String url) async {
  final res = await (await _client.getUrl(Uri.parse(url))).close();
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  final bytes = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

Never _die(String msg) {
  stderr.writeln('fetch_refs: $msg');
  exit(64);
}
