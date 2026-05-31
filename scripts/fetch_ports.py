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

# NGA WPI download URLs to try in order.  The key encodes a publication-ID
# (e.g. 16694312) that can change between WPI editions.  The script also
# queries the NGA publications API to discover the latest key automatically.
# If all attempts fail, download the ZIP manually from
#   https://msi.nga.mil/Publications/WPI
# and pass it with:  --wpi-file /path/to/WPI.zip
_WPI_URL_TEMPLATES = [
    "https://msi.nga.mil/api/publications/download?type=view&key={key}",
]
_WPI_KNOWN_KEYS = [
    "16694312/SFH00000/WPI.zip",  # WPI 2024 / recent editions
]
_NGA_PUBS_API = "https://msi.nga.mil/api/publications"

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


def _wpi_urls_to_try() -> list[str]:
    """Return a list of WPI download URLs to attempt, newest-key first."""
    urls = [
        t.format(key=k)
        for t in _WPI_URL_TEMPLATES
        for k in _WPI_KNOWN_KEYS
    ]
    # Also try to discover the current key from the NGA publications API.
    raw = _get(_NGA_PUBS_API, headers=_BROWSER_HEADERS, timeout=15)
    if raw:
        try:
            listing = json.loads(raw)
            items = listing if isinstance(listing, list) else listing.get("publications", [])
            for item in items:
                title = str(item.get("title", "") + item.get("type", "")).upper()
                if "WPI" in title or "WORLD PORT INDEX" in title:
                    for field in ("downloadURL", "url", "fileUrl", "key", "file"):
                        val = item.get(field, "")
                        if val:
                            # If it looks like a key, build a full URL.
                            candidate = (
                                val if val.startswith("http")
                                else _WPI_URL_TEMPLATES[0].format(key=val)
                            )
                            if candidate not in urls:
                                urls.insert(0, candidate)  # prefer discovered URL
                    break
        except Exception:
            pass
    return urls


def fetch_wpi(override_file: str | None = None) -> list[dict]:
    if override_file:
        print(f"Loading WPI from local file: {override_file}")
        data = Path(override_file).read_bytes()
    else:
        print("Downloading WPI from NGA (~3 MB)…")
        data = None
        for url in _wpi_urls_to_try():
            data = _get(url, headers=_BROWSER_HEADERS)
            if data:
                break
        if data is None:
            print(
                "\n  WPI download failed (all URL attempts returned 403).\n"
                "  The NGA server may require a real browser session.\n"
                "\n  Manual fallback:\n"
                "  1. Open https://msi.nga.mil/Publications/WPI in a browser\n"
                "  2. Click the WPI download button and save the ZIP\n"
                "  3. Re-run:  python scripts/fetch_ports.py --wpi-file C:\\path\\to\\WPI.zip\n"
                "\n  The script will continue with GeoNames data only for now.\n",
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

# Free GeoNames service caps startRow at 5000.  We stop at 4000 to stay clear
# of the limit and avoid triggering error code 25.
_GEONAMES_MAX_START = 4000

# Error codes that are fatal for ALL feature codes (not just the current one).
_GEONAMES_FATAL = {10, 19}  # invalid credentials, IP block


def _geonames_error(status: dict, user: str) -> tuple[bool, bool]:
    """
    Print a human-readable explanation and return (fatal, stop_this_code).
    fatal=True means abort all remaining feature codes.
    """
    code, msg = status.get("value"), status.get("message", "")
    if code == 10:
        print(
            f"\n  GeoNames authentication failed for user '{user}'.\n"
            "  Most likely cause: free web services not yet enabled.\n"
            "  → Go to https://www.geonames.org/manageaccount\n"
            "    tick 'Free Web Services' and click Save\n",
            file=sys.stderr,
        )
        return True, True
    elif code == 18:
        print(
            f"\n  GeoNames daily limit exceeded.\n"
            "  → Register at https://www.geonames.org/login for a personal account,\n"
            "    enable free web services, then re-run with --user YOUR_USERNAME\n",
            file=sys.stderr,
        )
        return True, True
    elif code == 19:
        print(f"\n  GeoNames blocked this IP: {msg}\n", file=sys.stderr)
        return True, True
    elif code == 25:
        # Free service pagination limit — not an error, just a ceiling.
        # Stop this feature code but continue with the next ones.
        print(f"    Free service pagination limit reached for {code}; moving on.")
        return False, True
    else:
        print(f"\n  GeoNames error {code}: {msg}\n", file=sys.stderr)
        return False, True


def fetch_geonames(user: str) -> list[dict]:
    rows: list[dict] = []
    seen: set[int] = set()
    abort = False

    for feat_code in GEONAMES_CODES:
        if abort:
            break
        print(f"  Fetching GeoNames {feat_code}…")
        start = 0

        while True:
            # Stop before we hit the free-service startRow ceiling.
            if start >= _GEONAMES_MAX_START:
                print(f"    Reached pagination cap ({_GEONAMES_MAX_START} rows) for {feat_code}.")
                break

            url = (
                f"{GEONAMES_API}"
                f"?featureCode={feat_code}&maxRows=1000&startRow={start}"
                f"&username={user}&style=SHORT"
            )
            raw = _get(url, timeout=30)
            if raw is None:
                break  # HTTP error already printed by _get

            data = json.loads(raw)

            # GeoNames encodes errors in the JSON body (status 200 + error JSON).
            if "status" in data:
                fatal, stop_code = _geonames_error(data["status"], user)
                if fatal:
                    abort = True
                break  # always stop the inner loop on any status error

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
                            "type":       feat_code,
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
