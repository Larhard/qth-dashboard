#!/usr/bin/env python3
"""
Builds assets/ports.tsv from two sources:

Primary — NGA World Port Index (WPI, Publication 150)
  Free US government publication covering ~4,000 commercial ports worldwide.
  Contains harbour size, VHF working channel, radio call sign, and many
  facility fields.  https://msi.nga.mil/Publications/WPI

Supplementary — GeoNames web service (https://secure.geonames.org)
  Covers smaller harbours, marinas, landings and anchorages not in the WPI.
  Requires a free GeoNames account with free web services enabled:
    1. Register:  https://www.geonames.org/login
    2. Enable:    https://www.geonames.org/manageaccount
       (tick "Free Web Services" and save)
    3. Run:  python scripts/fetch_ports.py --user YOUR_USERNAME

TSV columns (11):
  name, country, lat, lon, type, size, vhf, phone, call_sign, wpi_index, facilities

Usage:
  python scripts/fetch_ports.py [--user USERNAME] [--wpi-file WPI.zip] [--no-wpi] [--no-geonames]
"""
import argparse, csv, io, json, re, sys, time, urllib.error, urllib.request, zipfile
from pathlib import Path

OUT = Path(__file__).parent.parent / "assets" / "ports.tsv"

# ── HTTP helpers ──────────────────────────────────────────────────────────────

# NGA blocks the default Python-urllib user-agent with 403.
# A standard browser User-Agent string resolves this.
_BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/zip, application/octet-stream, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://msi.nga.mil/Publications/WPI",
}

def _get(url: str, *, headers: dict | None = None, timeout: int = 60) -> bytes | None:
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code} {e.reason}  ({url})", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Error fetching {url}: {e}", file=sys.stderr)
        return None


# ── WPI ───────────────────────────────────────────────────────────────────────

# NGA WPI download URL.  The key encodes the publication path in NGA's storage.
# If this returns 403 even with browser headers, download the ZIP manually from
#   https://msi.nga.mil/Publications/WPI
# and pass it with:  --wpi-file /path/to/WPI.zip
WPI_URL = (
    "https://msi.nga.mil/api/publications/download"
    "?type=view&key=16694312/SFH00000/WPI.zip"
)

_VHF_COLS      = ("comm_vhf",)
_PHONE_COLS    = ("comm_phone", "comm_radio_tel")
_CALLSIGN_COLS = ("radio_call_sign", "call_sign")
_SIZE_COLS     = ("harbor_size",)
_LAT_COLS      = ("latitude_dec", "latitude")
_LON_COLS      = ("longitude_dec", "longitude")
_NAME_COLS     = ("port_name", "main_port_name")
_COUNTRY_COLS  = ("country_code", "country")
_INDEX_COLS    = ("world_port_number", "index_no")

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
    h = [c.lower().replace(" ", "_") for c in header]
    for name in candidates:
        if name in h:
            return h.index(name)
    return -1


def _clean_vhf(raw: str) -> str:
    """Normalise WPI VHF field → semicolon-separated channel numbers."""
    if not raw:
        return ""
    channels = re.findall(r'\b(\d{1,2})\b', raw)
    channels = [c for c in channels if 1 <= int(c) <= 88]
    return ";".join(dict.fromkeys(channels))


def _parse_wpi_zip(data: bytes) -> list[dict]:
    rows = []
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        csv_name = next((n for n in zf.namelist() if n.lower().endswith(".csv")), None)
        if not csv_name:
            print("  No CSV found in WPI archive.  Files present:", file=sys.stderr)
            for n in zf.namelist():
                print(f"    {n}", file=sys.stderr)
            return []
        with zf.open(csv_name) as f:
            reader = csv.reader(io.TextIOWrapper(f, encoding="utf-8-sig", errors="replace"))
            header = next(reader)
            ci = {k: _col(header, v) for k, v in {
                "name":    _NAME_COLS,
                "country": _COUNTRY_COLS,
                "lat":     _LAT_COLS,
                "lon":     _LON_COLS,
                "size":    _SIZE_COLS,
                "vhf":     _VHF_COLS,
                "phone":   _PHONE_COLS,
                "sign":    _CALLSIGN_COLS,
                "index":   _INDEX_COLS,
            }.items()}
            fac_cols = {tag: _col(header, (col,)) for col, tag in _FACILITY_MAP.items()}

            for row in reader:
                def g(key: str) -> str:
                    idx = ci.get(key, -1)
                    return row[idx].strip() if 0 <= idx < len(row) else ""

                name = g("name")
                if not name:
                    continue
                try:
                    lat, lon = float(g("lat")), float(g("lon"))
                except ValueError:
                    continue

                facilities = [
                    tag for col, tag in _FACILITY_MAP.items()
                    if fac_cols.get(tag, -1) >= 0
                    and row[fac_cols[tag]].strip().upper() in ("Y", "YES", "1")
                ]
                rows.append({
                    "name":       name,
                    "country":    (g("country") + "  ")[:2].upper().strip(),
                    "lat":        lat,
                    "lon":        lon,
                    "type":       "PRT",
                    "size":       g("size").upper(),
                    "vhf":        _clean_vhf(g("vhf")),
                    "phone":      g("phone"),
                    "call_sign":  g("sign"),
                    "wpi_index":  g("index"),
                    "facilities": "|".join(facilities),
                })
    return rows


def fetch_wpi(override_file: str | None = None) -> list[dict]:
    if override_file:
        print(f"Loading WPI from local file: {override_file}")
        data = Path(override_file).read_bytes()
    else:
        print("Downloading WPI from NGA (~3 MB)…")
        data = _get(WPI_URL, headers=_BROWSER_HEADERS)
        if data is None:
            print(
                "\n  WPI download failed.  Manual fallback:\n"
                "  1. Open https://msi.nga.mil/Publications/WPI in a browser\n"
                "  2. Download the WPI ZIP\n"
                "  3. Run:  python scripts/fetch_ports.py --wpi-file /path/to/WPI.zip\n",
                file=sys.stderr,
            )
            return []

    rows = _parse_wpi_zip(data)
    vhf_count = sum(1 for r in rows if r["vhf"])
    print(f"  {len(rows)} WPI ports loaded ({vhf_count} with VHF data).")
    return rows


# ── GeoNames supplement ───────────────────────────────────────────────────────

# Use the HTTPS endpoint — http://api.geonames.org returns 401 for some clients.
GEONAMES_API   = "https://secure.geonames.org/searchJSON"
GEONAMES_CODES = ["HBR", "MRNA", "LDNG", "ANCH"]  # PRT covered by WPI


def _geonames_error(status: dict, user: str) -> None:
    code, msg = status.get("value"), status.get("message", "")
    if code == 10:
        print(
            f"\n  GeoNames authentication failed for user '{user}'.\n"
            "  Most likely cause: free web services not yet enabled.\n"
            "  → Go to https://www.geonames.org/manageaccount\n"
            "    tick 'Free Web Services' and click Save\n",
            file=sys.stderr,
        )
    elif code == 18:
        print(
            f"\n  GeoNames daily limit exceeded (demo account).\n"
            "  → Register at https://www.geonames.org/login for a personal account,\n"
            "    enable free web services, and re-run with --user YOUR_USERNAME\n",
            file=sys.stderr,
        )
    elif code == 19:
        print(f"\n  GeoNames blocked this IP: {msg}\n", file=sys.stderr)
    else:
        print(f"\n  GeoNames error {code}: {msg}\n", file=sys.stderr)


def fetch_geonames(user: str) -> list[dict]:
    rows: list[dict] = []
    seen: set[int] = set()

    for code in GEONAMES_CODES:
        print(f"  Fetching GeoNames {code}…")
        start = 0
        stop = False
        while not stop:
            url = (
                f"{GEONAMES_API}"
                f"?featureCode={code}&maxRows=1000&startRow={start}"
                f"&username={user}&style=SHORT"
            )
            raw = _get(url, timeout=30)
            if raw is None:
                break  # error already printed by _get

            data = json.loads(raw)

            # GeoNames encodes errors in the JSON body even when HTTP 200.
            if "status" in data:
                _geonames_error(data["status"], user)
                stop = True
                break

            hits = data.get("geonames", [])
            if not hits:
                break

            for h in hits:
                gid = h.get("geonameId")
                if gid and gid not in seen:
                    seen.add(gid)
                    name = (h.get("asciiName") or h.get("name", "")).strip()
                    if name:
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

        if stop:
            break

    print(f"  {len(rows)} GeoNames entries loaded.")
    return rows


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description="Build assets/ports.tsv from NGA WPI and GeoNames."
    )
    ap.add_argument("--user", default="demo",
                    help="GeoNames username (register free at geonames.org)")
    ap.add_argument("--wpi-file", metavar="PATH",
                    help="Path to a locally downloaded WPI.zip (skips NGA download)")
    ap.add_argument("--no-wpi",      action="store_true", help="Skip WPI entirely")
    ap.add_argument("--no-geonames", action="store_true", help="Skip GeoNames supplement")
    args = ap.parse_args()

    if args.user == "demo" and not args.no_geonames:
        print(
            "Note: using the 'demo' GeoNames account.\n"
            "  WPI data will still download fully.\n"
            "  For complete marina/harbour coverage, register free at\n"
            "  https://www.geonames.org/login and re-run with --user YOUR_USERNAME\n"
        )

    all_rows: list[dict] = []

    if not args.no_wpi:
        all_rows += fetch_wpi(args.wpi_file)

    if not args.no_geonames:
        print("Fetching GeoNames supplement…")
        all_rows += fetch_geonames(args.user)

    all_rows.sort(key=lambda r: (
        0 if r["type"] == "PRT" else {"HBR": 1, "MRNA": 2, "LDNG": 3, "ANCH": 4}.get(r["type"], 9),
        r["name"].lower()
    ))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("name\tcountry\tlat\tlon\ttype\tsize\tvhf\tphone\tcall_sign\twpi_index\tfacilities\n")
        for r in all_rows:
            f.write("\t".join([
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
            ]) + "\n")

    print(f"\nSaved {len(all_rows)} ports → {OUT}")


if __name__ == "__main__":
    main()
