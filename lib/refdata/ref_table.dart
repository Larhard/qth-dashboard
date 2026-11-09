/// Compact, spatially indexed store of one program's references. Pure Dart.
///
/// Memory / load time: SOTA alone is ~170k summits (14 MB of TSV). The table
/// keeps the file's raw UTF-8 bytes plus an offset per row and typed
/// `lats`/`lons` arrays — no per-row String or [HamRef] objects — and decodes a
/// full record only for rows actually displayed ([row]). Loading is one pass
/// over the bytes (coordinates are parsed in place), so it runs in a fraction
/// of the time and about half the memory of splitting the text into lines.
///
/// Lookup: references are bucketed in a 1° grid. [nearest]/[nearestK] search
/// expanding rings of cells and stop once no unvisited cell can contain a closer
/// point. Longitude bins wrap at ±180° (Pacific island groups, Chukotka…); a very
/// sparse neighbourhood falls back to a brute-force scan, which is always correct.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/ham_ref.dart';
import '../utils/geo_utils.dart';

typedef RefHit = ({int index, double distKm});

class RefTable {
  final Uint8List _data;
  final Int32List _start; // row i = _data[_start[i] .. _end[i])
  final Int32List _end;
  final Float64List lats;
  final Float64List lons;
  final Map<int, Int32List> _grid;
  final RefFileHeader? header;

  RefTable._(this._data, this._start, this._end, this.lats, this.lons, this._grid, this.header);

  static const _cellDeg = 1.0;
  static const _lonBins = 360; // 360 / _cellDeg
  static const _maxRing = 60;  // beyond this, brute force is cheaper & exact

  int get length => lats.length;
  bool get isEmpty => lats.isEmpty;

  /// Full record for row [i] (decoded on demand).
  HamRef row(int i) =>
      HamRef.fromTsv(utf8.decode(Uint8List.sublistView(_data, _start[i], _end[i]), allowMalformed: true))!;

  /// Builds a table from a normalized reference file (see `ham_ref.dart`).
  factory RefTable.fromTsv(String text) => RefTable.fromBytes(utf8.encode(text));

  /// Builds a table from the UTF-8 bytes of a normalized reference file.
  /// The table keeps [bytes]; don't modify them afterwards.
  factory RefTable.fromBytes(Uint8List bytes) {
    const nl = 0x0A, cr = 0x0D, tab = 0x09, hash = 0x23;
    RefFileHeader? header;
    // Rows ≈ bytes / 60 for every current program; the lists grow if needed.
    var cap = bytes.length ~/ 40 + 16, n = 0;
    var starts = Int32List(cap), ends = Int32List(cap);
    var la = Float64List(cap), lo = Float64List(cap);

    var pos = 0;
    final len = bytes.length;
    while (pos < len) {
      var eol = pos;
      while (eol < len && bytes[eol] != nl) {
        eol++;
      }
      final next = eol + 1;
      if (eol > pos && bytes[eol - 1] == cr) eol--;
      if (eol == pos) {
        pos = next;
        continue;
      }
      if (bytes[pos] == hash) {
        header ??= RefFileHeader.parse(utf8.decode(Uint8List.sublistView(bytes, pos, eol), allowMalformed: true));
        pos = next;
        continue;
      }
      // Columns: ref, name, lat, lon, … — only the coordinates are parsed now.
      final t1 = _indexOf(bytes, tab, pos, eol);
      final t2 = t1 < 0 ? -1 : _indexOf(bytes, tab, t1 + 1, eol);
      final t3 = t2 < 0 ? -1 : _indexOf(bytes, tab, t2 + 1, eol);
      if (t3 >= 0) {
        final t4 = _indexOf(bytes, tab, t3 + 1, eol);
        final lat = _parseNum(bytes, t2 + 1, t3);
        final lon = _parseNum(bytes, t3 + 1, t4 < 0 ? eol : t4);
        if (lat != null && lon != null) {
          if (n == cap) {
            cap *= 2;
            starts = _grow(starts, cap);
            ends = _grow(ends, cap);
            la = _growF(la, cap);
            lo = _growF(lo, cap);
          }
          starts[n] = pos;
          ends[n] = eol;
          la[n] = lat;
          lo[n] = lon;
          n++;
        }
      }
      pos = next;
    }
    return RefTable._build(bytes, Int32List.sublistView(starts, 0, n), Int32List.sublistView(ends, 0, n),
        Float64List.sublistView(la, 0, n), Float64List.sublistView(lo, 0, n), header);
  }

  /// For tests: a table from already-split rows and their coordinates.
  factory RefTable.fromColumns(List<String> lines, Float64List lats, Float64List lons,
      {RefFileHeader? header}) {
    final b = BytesBuilder(copy: false);
    final starts = Int32List(lines.length), ends = Int32List(lines.length);
    for (var i = 0; i < lines.length; i++) {
      starts[i] = b.length;
      b.add(utf8.encode(lines[i]));
      ends[i] = b.length;
      b.addByte(0x0A);
    }
    return RefTable._build(b.takeBytes(), starts, ends, lats, lons, header);
  }

  static RefTable _build(Uint8List data, Int32List starts, Int32List ends, Float64List lats,
      Float64List lons, RefFileHeader? header) {
    // Two-pass bucket fill: count per cell, then place indices — no growable lists.
    final keys = Int32List(lats.length);
    final counts = <int, int>{};
    for (var i = 0; i < lats.length; i++) {
      final k = keys[i] = _key(_latBin(lats[i]), _lonBin(lons[i]));
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final grid = {for (final e in counts.entries) e.key: Int32List(e.value)};
    final fill = <int, int>{};
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final at = fill[k] ?? 0;
      grid[k]![at] = i;
      fill[k] = at + 1;
    }
    return RefTable._(data, starts, ends, lats, lons, grid, header);
  }

  static int _indexOf(Uint8List b, int byte, int from, int to) {
    for (var i = from; i < to; i++) {
      if (b[i] == byte) return i;
    }
    return -1;
  }

  static Int32List _grow(Int32List a, int cap) => Int32List(cap)..setRange(0, a.length, a);
  static Float64List _growF(Float64List a, int cap) => Float64List(cap)..setRange(0, a.length, a);

  static const _pow10 = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15];

  /// Parses `-?digits(.digits)?` in place; exact (one correctly rounded
  /// division, same result as double.parse). Anything else falls back to
  /// double.tryParse.
  static double? _parseNum(Uint8List b, int from, int to) {
    var i = from;
    final neg = i < to && b[i] == 0x2D;
    if (neg) i++;
    var mant = 0, digits = 0, frac = 0;
    var dot = false;
    for (; i < to; i++) {
      final c = b[i];
      if (c >= 0x30 && c <= 0x39) {
        mant = mant * 10 + (c - 0x30);
        if (++digits > 15) break;
        if (dot) frac++;
      } else if (c == 0x2E && !dot) {
        dot = true;
      } else {
        break;
      }
    }
    if (i == to && digits > 0) {
      final v = mant / _pow10[frac];
      return neg ? -v : v;
    }
    return double.tryParse(String.fromCharCodes(b, from, to).trim());
  }

  static int _latBin(double lat) => (lat / _cellDeg).floor().clamp(-90, 89);
  static int _lonBin(double lon) {
    final b = (lon / _cellDeg).floor();
    return ((b + 180) % _lonBins + _lonBins) % _lonBins - 180; // wrap to [-180,179]
  }

  static int _key(int latBin, int lonBin) => (latBin + 90) * 1000 + (lonBin + 180);

  /// Lower bound (km) on the distance from a point in the centre cell to any cell
  /// of ring [ring]+1 — i.e. [ring] whole cells away in the worst direction.
  static double _ringBoundKm(double lat, int ring) {
    if (ring <= 0) return 0;
    final poleward = math.min(89.9, lat.abs() + (ring + 1) * _cellDeg);
    final kmPerDegLon = 111.32 * math.cos(poleward * math.pi / 180);
    return ring * _cellDeg * math.min(110.57, kmPerDegLon);
  }

  /// The single closest reference, or null if the table is empty.
  RefHit? nearest(double lat, double lon) {
    final r = nearestK(lat, lon, 1);
    return r.isEmpty ? null : r.first;
  }

  /// The [k] closest references, nearest first.
  List<RefHit> nearestK(double lat, double lon, int k) {
    if (isEmpty || k <= 0) return const [];
    final latBin = _latBin(lat), lonBin = _lonBin(lon);
    final cand = <RefHit>[];

    for (var ring = 0; ring <= _maxRing; ring++) {
      for (var dlat = -ring; dlat <= ring; dlat++) {
        final lb = latBin + dlat;
        if (lb < -90 || lb > 89) continue;
        for (var dlon = -ring; dlon <= ring; dlon++) {
          if (ring > 0 && dlat.abs() < ring && dlon.abs() < ring) continue; // inner
          final cell = _grid[_key(lb, _lonBin((lonBin + dlon).toDouble()))];
          if (cell == null) continue;
          for (final i in cell) {
            cand.add((index: i, distKm: haversineKm(lat, lon, lats[i], lons[i])));
          }
        }
      }
      if (cand.length >= k) {
        cand.sort((a, b) => a.distKm.compareTo(b.distKm));
        if (cand[k - 1].distKm <= _ringBoundKm(lat, ring)) return cand.sublist(0, k);
      }
    }
    // Sparse neighbourhood (or k ≥ what the rings held): exact brute force.
    final all = <RefHit>[
      for (var i = 0; i < length; i++)
        (index: i, distKm: haversineKm(lat, lon, lats[i], lons[i])),
    ]..sort((a, b) => a.distKm.compareTo(b.distKm));
    return all.sublist(0, math.min(k, all.length));
  }
}
