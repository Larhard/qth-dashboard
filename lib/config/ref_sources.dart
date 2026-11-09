/// Where each amateur-radio reference program's full world list is downloaded
/// from — used by the build tool (`tool/fetch_refs.dart`) and by the in-app
/// "Update via network" action. Pure Dart.
///
/// To add a program: add a [PoiCategory], a parser in `refdata/parsers.dart`, an
/// entry here, rules in `refdata/activation_rules.dart`, and a colour in
/// `theme/palette.dart`. Programs without an entry ship with no data and are
/// hidden from the dashboard until a source exists.
library;

import '../models/poi_category.dart';

/// How a source is downloaded (see `refdata/fetch.dart`).
enum RefFetch {
  /// One file with every reference.
  single,

  /// An index (JSON array of keys, or [RefSource.staticKeys]) + one file per key.
  parts,

  /// HEMA: no export — the public country / region / map pages are read and
  /// joined (country list → regions → summit rows + map markers).
  hemaSite,
}

class RefSource {
  /// [RefFetch.single]: the whole list. [RefFetch.parts]: the INDEX URL returning
  /// a JSON array of part keys (unused when [staticKeys] is set).
  /// [RefFetch.hemaSite]: the site base URL (ending in `/`).
  final String url;

  /// [RefFetch.parts] only: URL of one part, `{key}` replaced by each key
  /// (URL-encoded).
  final String? partUrl;

  /// [RefFetch.parts] with a fixed set of parts (no index request).
  final List<String>? staticKeys;

  final RefFetch fetch;

  /// Pause between requests to the same server (multi-request sources).
  final Duration pause;

  /// Approximate download size, shown before an on-device update.
  final int approxBytes;

  /// Program home page (attribution, rules, more info).
  final String homepage;

  /// Attribution line for the licences page / About screen.
  final String attribution;

  const RefSource({
    required this.url,
    this.partUrl,
    this.staticKeys,
    this.fetch = RefFetch.single,
    this.pause = const Duration(milliseconds: 150),
    required this.approxBytes,
    required this.homepage,
    required this.attribution,
  });

  bool get isMultiPart => fetch != RefFetch.single;
}

/// GMA's public map service (maps.gma.rocks redirects here). It also serves
/// the MOTA, ARLHS, WLOTA, GIA and SBW layers. Site footer: CC BY-SA (DL0QW).
const _gmaMap = 'https://www.gma.rocks/gmamap';
const _gmaAttr = 'via GMA map service (gma.rocks, CC BY-SA)';

const refSources = <PoiCategory, RefSource>{
  PoiCategory.sota: RefSource(
    url: 'https://storage.sota.org.uk/summitslist.csv',
    approxBytes: 25 * 1024 * 1024,
    homepage: 'https://www.sota.org.uk',
    attribution: 'Summits On The Air (SOTA) summit list © SOTA programme',
  ),
  PoiCategory.pota: RefSource(
    url: 'https://pota.app/all_parks_ext.csv',
    approxBytes: 10 * 1024 * 1024,
    homepage: 'https://pota.app',
    attribution: 'Parks On The Air (POTA) park list © Parks On The Air',
  ),
  PoiCategory.wwff: RefSource(
    url: 'https://wwff.co/wwff-data/wwff_directory.csv',
    approxBytes: 24 * 1024 * 1024,
    homepage: 'https://wwff.co',
    attribution: 'World Wide Flora & Fauna (WWFF) directory © WWFF',
  ),
  PoiCategory.iota: RefSource(
    url: 'https://www.iota-world.org/islands-on-the-air/downloads/download-file.html?path=fulllist.json',
    approxBytes: 1400 * 1024,
    homepage: 'https://www.iota-world.org',
    attribution: 'Islands On The Air (IOTA) group list © IOTA Ltd',
  ),
  PoiCategory.bota: RefSource(
    url: 'https://api.wwbota.org/bunkers/',
    approxBytes: 6 * 1024 * 1024,
    homepage: 'https://wwbota.org',
    attribution: 'World Wide Bunkers On The Air (WWBOTA) bunker list © WWBOTA',
  ),
  PoiCategory.tota: RefSource(
    url: 'https://www.rozhledny.eu/servis/generate_csv.php?ref=ALL&filter=all',
    approxBytes: 800 * 1024,
    homepage: 'https://www.rozhledny.eu',
    attribution: 'Towers On The Air (TOTA) tower list © rozhledny.eu',
  ),
  // GMA and WCA come from GMA's public map service, one request per region /
  // prefix (no bulk file exists). Fetched politely (sequential, short pause).
  PoiCategory.gma: RefSource(
    url: '$_gmaMap/load_gma_regions.php',
    partUrl: '$_gmaMap/load_gma.php?region={key}',
    fetch: RefFetch.parts,
    approxBytes: 40 * 1024 * 1024,
    homepage: 'https://www.gma.rocks',
    attribution: 'Global Mountain Activity (GMA) references © GMA / cqgma.org',
  ),
  PoiCategory.wca: RefSource(
    url: '$_gmaMap/load_cota_prefixes.php',
    partUrl: '$_gmaMap/load_cota.php?prefix={key}',
    fetch: RefFetch.parts,
    approxBytes: 15 * 1024 * 1024,
    homepage: 'https://wcagroup.org',
    attribution: 'World Castles Award (WCA / COTA) references © WCA group, '
        'coordinates via GMA (gma.rocks)',
  ),
  PoiCategory.llota: RefSource(
    url: 'https://llota.app/api/public/references',
    approxBytes: 6500 * 1024,
    homepage: 'https://llota.app',
    attribution: 'Lagoons & Lakes On The Air (LLOTA) reference list © LLOTA',
  ),
  PoiCategory.hema: RefSource(
    url: 'https://www.hema.org.uk/',
    fetch: RefFetch.hemaSite,
    pause: Duration(milliseconds: 300), // old, fragile site — be gentle
    approxBytes: 12 * 1024 * 1024,
    homepage: 'https://www.hema.org.uk',
    attribution: 'HuMPs Excluding Marilyns Award (HEMA) summit database © HEMA',
  ),
  PoiCategory.sbw: RefSource(
    url: '$_gmaMap/load_sbw.php',
    approxBytes: 30 * 1024,
    homepage: 'https://www.dl2lto.de',
    attribution: 'Sächsischer Bergwettbewerb (SBW) summit list, $_gmaAttr',
  ),
  PoiCategory.zlota: RefSource(
    url: 'https://ontheair.nz/api/assets',
    partUrl: 'https://ontheair.nz/api/assets?asset_type={key}',
    staticKeys: ['hut', 'island', 'lake', 'park', 'volcano', 'lighthouse'],
    fetch: RefFetch.parts,
    pause: Duration(milliseconds: 1500), // Cloudflare rate limiting
    approxBytes: 2900 * 1024,
    homepage: 'https://ontheair.nz',
    attribution: 'New Zealand On The Air (ZLOTA) assets © ontheair.nz '
        '(park boundaries: NZ Department of Conservation)',
  ),
  PoiCategory.gia: RefSource(
    url: '$_gmaMap/load_gia.php',
    approxBytes: 110 * 1024,
    homepage: 'https://www.gma.rocks',
    attribution: 'Global Island Activity (GIA) island list © GMA, $_gmaAttr',
  ),
  PoiCategory.mota: RefSource(
    url: '$_gmaMap/load_mota_prefixes.php',
    partUrl: '$_gmaMap/load_mota.php?pfx={key}', // NB: `pfx`, not `prefix`
    fetch: RefFetch.parts,
    approxBytes: 4 * 1024 * 1024,
    homepage: 'https://www.gma.rocks',
    attribution: 'Mills On The Air (MOTA) mill list © GMA, $_gmaAttr',
  ),
  PoiCategory.siota: RefSource(
    url: 'https://www.silosontheair.com/data/silos.csv',
    approxBytes: 380 * 1024,
    homepage: 'https://www.silosontheair.com',
    attribution: 'Silos On The Air (SiOTA) silo list © Silos On The Air '
        '(non-commercial use; see silosontheair.com/toc.html)',
  ),
  PoiCategory.arlhs: RefSource(
    url: '$_gmaMap/load_arlhs.php',
    approxBytes: 2900 * 1024,
    homepage: 'https://wlol.arlhs.com',
    attribution: 'ARLHS World List of Lights © ARLHS, LLC, $_gmaAttr',
  ),
  PoiCategory.wlota: RefSource(
    url: '$_gmaMap/load_wlota.php',
    approxBytes: 800 * 1024,
    homepage: 'https://wlota.com',
    attribution: 'World Lighthouses On The Air (WLOTA) list © WLOTA, $_gmaAttr',
  ),
};
