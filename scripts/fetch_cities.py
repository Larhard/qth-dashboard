#!/usr/bin/env python3
"""
Downloads GeoNames cities1000.zip (all places with population >= 1 000) and
produces three city databases, each a subset of the next:

  assets/cities.tsv          -- top 5 000 cities by population (global overview)
  assets/cities_precise.tsv  -- all ~47 000 cities with population >= 5 000
  assets/cities_detailed.tsv -- all ~140 000 cities with population >= 1 000
                                 (includes small towns like Swiatniki Gorne)

TSV columns (6): name, country, lat, lon, population, timezone
  population  integer, 0 if unknown
  timezone    IANA timezone name, e.g. "Europe/Warsaw"

Run once before building the app:
    python scripts/fetch_cities.py
Requires internet access for this one-time step; the app then works fully offline.
"""
import urllib.request
import zipfile
import io
import os
import sys
import time


# ── Progress helper ───────────────────────────────────────────────────────────

def _fmt_dur(s: float) -> str:
    if s < 60:   return f"{s:.0f}s"
    if s < 3600: return f"{s / 60:.1f}m"
    return f"{s / 3600:.1f}h"


class Progress:
    """Single-line progress display with elapsed time and ETA."""
    def __init__(self, total: int, label: str = "") -> None:
        self.total = total
        self.done  = 0
        self.start = time.monotonic()
        self.label = label

    def update(self, n: int = 1, detail: str = "") -> None:
        self.done += n
        elapsed = time.monotonic() - self.start
        pct  = self.done / self.total * 100 if self.total else 0
        rate = self.done / elapsed if elapsed > 0.05 else 0
        eta  = (self.total - self.done) / rate if rate > 0 else 0
        det  = f"  {detail}" if detail else ""
        sys.stderr.write(
            f"\r  [{self.done}/{self.total}] {pct:5.1f}%  "
            f"elapsed {_fmt_dur(elapsed)}  ETA {_fmt_dur(eta)}{det}          "
        )
        sys.stderr.flush()

    def finish(self, msg: str = "") -> None:
        elapsed = time.monotonic() - self.start
        sys.stderr.write(
            f"\r  Done {self.done}/{self.total} in {_fmt_dur(elapsed)}.{' ' + msg if msg else ''}\n"
        )
        sys.stderr.flush()

GEONAMES_URL = "https://download.geonames.org/export/dump/cities1000.zip"
ASSETS_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets')
LARGE_PATH    = os.path.join(ASSETS_DIR, 'cities.tsv')
PRECISE_PATH  = os.path.join(ASSETS_DIR, 'cities_precise.tsv')
DETAILED_PATH = os.path.join(ASSETS_DIR, 'cities_detailed.tsv')

LARGE_N         = 5_000
PRECISE_MIN_POP = 5_000

# GeoNames cities1000.txt column indices (0-based):
#  0  geonameid
#  1  name
#  2  asciiname
#  3  alternatenames
#  4  latitude
#  5  longitude
#  6  feature class
#  7  feature code
#  8  country code
#  9  cc2
# 10  admin1 code
# 11  admin2 code
# 12  admin3 code
# 13  admin4 code
# 14  population
# 15  elevation
# 16  dem
# 17  timezone     ← used
# 18  modification date


def _write_tsv(path: str, cities: list) -> None:
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('name\tcountry\tlat\tlon\tpopulation\ttimezone\n')
        for name, country, lat, lon, population, timezone in cities:
            safe_name = name.replace('\t', ' ')
            tz = timezone.replace('\t', ' ')
            f.write(f'{safe_name}\t{country}\t{lat}\t{lon}\t{population}\t{tz}\n')


def main():
    print("Downloading cities1000.zip from GeoNames (~10 MB)...")
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(GEONAMES_URL, timeout=120) as resp:
            data = resp.read()
    except Exception as e:
        print(f"Download failed: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"  Downloaded in {_fmt_dur(time.monotonic() - t0)}.")

    print("Parsing...")
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        with zf.open('cities1000.txt') as f:
            content = f.read().decode('utf-8')

    lines = content.splitlines()
    prog = Progress(len(lines), "cities")
    cities = []
    for line in lines:
        prog.update(detail=f"{len(cities)} accepted")
        parts = line.split('\t')
        if len(parts) < 18:
            continue
        try:
            name       = parts[1].strip()
            lat        = float(parts[4])
            lon        = float(parts[5])
            country    = parts[8].strip()
            population = int(parts[14]) if parts[14].strip() else 0
            timezone   = parts[17].strip()
            if not name:
                continue
            cities.append((name, country, lat, lon, population, timezone))
        except (ValueError, IndexError):
            continue

    prog.finish(f"{len(cities)} cities accepted.")

    # Sort by population descending so each subset is deterministic.
    print("Sorting and writing...")
    cities.sort(key=lambda x: x[4], reverse=True)

    os.makedirs(ASSETS_DIR, exist_ok=True)

    # Level 1 -- top 5 000 worldwide (global overview)
    _write_tsv(LARGE_PATH, cities[:LARGE_N])
    print(f"  Large:    {LARGE_N:7d} cities -> {LARGE_PATH}")

    # Level 2 -- all places with population >= 5 000 (regional)
    precise = [c for c in cities if c[4] >= PRECISE_MIN_POP]
    _write_tsv(PRECISE_PATH, precise)
    print(f"  Precise:  {len(precise):7d} cities -> {PRECISE_PATH}")

    # Level 3 -- full dataset: population >= 1 000 (local, includes small towns)
    _write_tsv(DETAILED_PATH, cities)
    print(f"  Detailed: {len(cities):7d} cities -> {DETAILED_PATH}")


if __name__ == '__main__':
    main()
