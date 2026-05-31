#!/usr/bin/env python3
"""
Builds assets/ports.tsv from two sources:

Primary — NGA World Port Index (WPI, Publication 150)
  Free US government publication covering ~4,000 commercial ports worldwide.
  Contains harbour size, VHF working channel, radio call sign, and many
  facility fields.  Download: https://msi.nga.mil/Publications/WPI
  WPI ZIP URL is queried automatically from the NGA MSI API.

Supplementary — GeoNames web service
  Covers smaller harbours, marinas, landings and anchorages not in the WPI.
  Register free at https://www.geonames.org/login, then pass --user YOUR_NAME.
  Falls back to the 'demo' account if no username is given (rate-limited).

TSV columns (11):
  name       port/harbour name
  country    ISO-3166-1 alpha-2 country code
  lat        decimal latitude
  lon        decimal longitude
  type       GeoNames feature code: PRT / HBR / MRNA / LDNG / ANCH
  size       WPI harbour size: L / M / S / VS  (empty for GeoNames-only entries)
  vhf        primary VHF working channel(s), semicolon-separated, e.g. "12;74"
  phone      harbour-master / operations phone
  call_sign  ITU radio call sign
  wpi_index  WPI world port number (empty for GeoNames-only entries)
  facilities pipe-separated WPI facility flags, e.g. "FUEL|WATER|PROVISIONS"

Port-size note
  WPI classifies ports by HARBOR_SIZE:
    L  = Large  (major commercial port, can handle large ocean-going vessels)
    M  = Medium (handles medium cargo / ro-ro)
    S  = Small  (coastal / feeder service)
    VS = Very Small (local / fishing / recreational)
  If you later want two separate CityModes (port_major / port_marina) split on
  size: L+M → port_major, S+VS → port_marina.

Usage:
  python scripts/fetch_ports.py [--user YOUR_GEONAMES_USERNAME]
"""
import argparse, csv, io, json, re, sys, time, urllib.request, zipfile
from pathlib import Path

OUT = Path(__file__).parent.parent / "assets" / "ports.tsv"

# ── WPI ───────────────────────────────────────────────────────────────────────

WPI_API = ("https://msi.nga.mil/api/publications/download"
           "?type=view&key=16694312/SFH00000/WPI.zip")

# WPI CSV column names (lowercase, spaces replaced by _).
# Actual names may vary slightly between WPI editions; we match by pattern.
_VHF_COLS      = ("comm_vhf",)
_PHONE_COLS    = ("comm_phone", "comm_radio_tel")
_CALLSIGN_COLS = ("radio_call_sign", "call_sign")
_SIZE_COLS     = ("harbor_size",)
_LAT_COLS      = ("latitude_dec", "latitude")
_LON_COLS      = ("longitude_dec", "longitude")
_NAME_COLS     = ("port_name", "main_port_name")
_COUNTRY_COLS  = ("country_code", "country")
_INDEX_COLS    = ("world_port_number", "index_no")

# WPI facility columns and their compact tag.
_FACILITY_MAP = {
    "fuel_oil":           "FUEL_OIL",
    "fuel_diesel":        "DIESEL",
    "water":              "WATER",
    "provisions":         "PROVISIONS",
    "ice":                "ICE",
    "medical_facilities": "MEDICAL",
    "dry_dock":           "DRY_DOCK",
    "marine_railway":     "MARINE_RLY",
    "tugs_assist":        "TUGS",
    "degaussing":         "DEGAS",
}


def _col(header: list[str], candidates: tuple) -> int:
    """Return index of first matching candidate column, or -1."""
    h = [c.lower().replace(" ", "_") for c in header]
    for name in candidates:
        if name in h:
            return h.index(name)
    return -1


def _clean_vhf(raw: str) -> str:
    """Normalise VHF field: extract channel numbers, join with ';'."""
    if not raw:
        return ""
    # WPI VHF field examples: "VHF Ch 12  Ch 74", "CH 16/12", "12", "VHF 16"
    channels = re.findall(r'\b(\d{1,2})\b', raw)
    # Filter to valid marine VHF channels (1-88)
    channels = [c for c in channels if 1 <= int(c) <= 88]
    return ";".join(dict.fromkeys(channels))  # deduplicate, keep order


def fetch_wpi() -> list[dict]:
    print("Downloading WPI from NGA (~3 MB)…")
    try:
        with urllib.request.urlopen(WPI_API, timeout=60) as resp:
            raw = resp.read()
    except Exception as e:
        print(f"  WPI download failed: {e}", file=sys.stderr)
        return []

    rows = []
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        csv_name = next((n for n in zf.namelist() if n.lower().endswith(".csv")), None)
        if not csv_name:
            print("  No CSV found in WPI archive.", file=sys.stderr)
            return []
        with zf.open(csv_name) as f:
            reader = csv.reader(io.TextIOWrapper(f, encoding="utf-8-sig", errors="replace"))
            header = next(reader)
            ci = {
                "name":    _col(header, _NAME_COLS),
                "country": _col(header, _COUNTRY_COLS),
                "lat":     _col(header, _LAT_COLS),
                "lon":     _col(header, _LON_COLS),
                "size":    _col(header, _SIZE_COLS),
                "vhf":     _col(header, _VHF_COLS),
                "phone":   _col(header, _PHONE_COLS),
                "sign":    _col(header, _CALLSIGN_COLS),
                "index":   _col(header, _INDEX_COLS),
            }
            facility_cols = {tag: _col(header, (col,)) for col, tag in _FACILITY_MAP.items()}

            for row in reader:
                def g(key: str) -> str:
                    idx = ci.get(key, -1)
                    return row[idx].strip() if 0 <= idx < len(row) else ""

                name = g("name")
                if not name:
                    continue
                try:
                    lat = float(g("lat"))
                    lon = float(g("lon"))
                except ValueError:
                    continue

                facilities = [tag for col, tag in _FACILITY_MAP.items()
                              if facility_cols.get(tag, -1) >= 0
                              and row[facility_cols[tag]].strip().upper() in ("Y", "YES", "1")]

                rows.append({
                    "name":      name,
                    "country":   g("country")[:2].upper(),
                    "lat":       lat,
                    "lon":       lon,
                    "type":      "PRT",
                    "size":      g("size").strip().upper(),
                    "vhf":       _clean_vhf(g("vhf")),
                    "phone":     g("phone"),
                    "call_sign": g("sign"),
                    "wpi_index": g("index"),
                    "facilities": "|".join(facilities),
                })

    print(f"  {len(rows)} WPI ports loaded.")
    return rows


# ── GeoNames supplement ───────────────────────────────────────────────────────

GEONAMES_CODES  = ["HBR", "MRNA", "LDNG", "ANCH"]  # PRT already covered by WPI
CODE_PRIORITY   = {"HBR": 0, "MRNA": 1, "LDNG": 2, "ANCH": 3}


def fetch_geonames(user: str) -> list[dict]:
    rows = []
    seen: set[int] = set()

    for code in GEONAMES_CODES:
        print(f"  Fetching GeoNames {code}…")
        start = 0
        while True:
            url = (
                "http://api.geonames.org/searchJSON"
                f"?featureCode={code}&maxRows=1000&startRow={start}"
                f"&username={user}&style=SHORT"
            )
            try:
                with urllib.request.urlopen(url, timeout=30) as resp:
                    hits = json.loads(resp.read()).get("geonames", [])
            except Exception as e:
                print(f"    Warning: {e}", file=sys.stderr)
                break
            if not hits:
                break
            for h in hits:
                gid = h.get("geonameId")
                if gid and gid not in seen:
                    seen.add(gid)
                    name = (h.get("asciiName") or h.get("name", "")).strip()
                    if not name:
                        continue
                    rows.append({
                        "name":       name,
                        "country":    h.get("countryCode", "").strip(),
                        "lat":        float(h.get("lat", 0)),
                        "lon":        float(h.get("lng", 0)),
                        "type":       code,
                        "size":       "",
                        "vhf":        "",
                        "phone":      "",
                        "call_sign":  "",
                        "wpi_index":  "",
                        "facilities": "",
                    })
            start += len(hits)
            if len(hits) < 1000:
                break
            time.sleep(0.3)

    print(f"  {len(rows)} GeoNames supplement entries loaded.")
    return rows


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", default="demo",
                    help="GeoNames username (register free at geonames.org)")
    args = ap.parse_args()

    if args.user == "demo":
        print("Note: using the 'demo' GeoNames account (rate-limited).")
        print("  Register at https://www.geonames.org/login for higher limits.")

    # WPI first (authoritative communication data)
    wpi_rows = fetch_wpi()

    # GeoNames supplement for marina/harbour types not in WPI
    gn_rows = fetch_geonames(args.user)

    all_rows = wpi_rows + gn_rows
    all_rows.sort(key=lambda r: (
        0 if r["type"] == "PRT" else CODE_PRIORITY.get(r["type"], 9),
        r["name"].lower()
    ))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("name\tcountry\tlat\tlon\ttype\tsize\tvhf\tphone\tcall_sign\twpi_index\tfacilities\n")
        for r in all_rows:
            cols = [
                r["name"].replace("\t", " "),
                r["country"],
                str(r["lat"]),
                str(r["lon"]),
                r["type"],
                r["size"],
                r["vhf"],
                r["phone"].replace("\t", " "),
                r["call_sign"].replace("\t", " "),
                r["wpi_index"],
                r["facilities"],
            ]
            f.write("\t".join(cols) + "\n")

    print(f"\nSaved {len(all_rows)} ports → {OUT}")
    if wpi_rows:
        vhf_count = sum(1 for r in wpi_rows if r["vhf"])
        print(f"  WPI: {len(wpi_rows)} ports, {vhf_count} with VHF channel data")
    print(f"  GeoNames: {len(gn_rows)} supplement entries")


if __name__ == "__main__":
    main()
