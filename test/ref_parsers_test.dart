import 'package:flutter_test/flutter_test.dart';
import 'package:qth_dashboard/models/ham_ref.dart';
import 'package:qth_dashboard/models/poi_category.dart';
import 'package:qth_dashboard/models/text_repair.dart';
import 'package:qth_dashboard/config/ref_sources.dart';
import 'package:qth_dashboard/refdata/activation_rules.dart';
import 'package:qth_dashboard/refdata/csv.dart';
import 'package:qth_dashboard/refdata/fetch.dart';
import 'package:qth_dashboard/refdata/parsers.dart';

/// Fixtures are real rows copied from each program's upstream download, so a
/// format change upstream shows up as a failing parser test, not a silently
/// empty category on the phone.
void main() {
  final today = DateTime(2026, 11, 9);

  group('CSV reader', () {
    test('quoted separators, escaped quotes, embedded newlines, CRLF, BOM', () {
      final rows = parseCsv('﻿a,"b,c","say ""hi""","multi\nline"\r\n1,2,3,4\r\n');
      expect(rows, [
        ['a', 'b,c', 'say "hi"', 'multi\nline'],
        ['1', '2', '3', '4'],
      ]);
    });

    test('empty trailing fields are kept; blank lines skipped', () {
      expect(parseCsv('x,,\n\n,y\n'), [
        ['x', '', ''],
        ['', 'y'],
      ]);
    });
  });

  group('SOTA', () {
    const csv = 'SOTA Summits List (Date=09/11/2026)\n'
        'SummitCode,AssociationName,RegionName,SummitName,AltM,AltFt,GridRef1,GridRef2,'
        'Longitude,Latitude,Points,BonusPoints,ValidFrom,ValidTo,ActivationCount,ActivationDate,ActivationCall\n'
        '3B8/MU-001,Mauritius,Mauritius,"Piton de la Petite Rivière Noire (Black River Peak)",'
        '828,2716,57.40771,-20.40882,57.40771,-20.40882,10,0,01/08/2026,31/12/2099,0,,\n'
        'SP/BZ-005,Poland,Beskidy Zachodnie,Turbacz,1310,4298,20.11160,49.54279,'
        '20.11160,49.54279,8,3,01/04/2008,31/12/2099,212,01/11/2026,SP9XYZ\n'
        'XX/RT-001,Retired,Old,"Gone Peak",500,1640,1,1,1.0,1.0,1,0,01/01/2000,31/12/2020,0,,\n'
        'XX/FU-001,Future,New,"Not Yet",500,1640,2,2,2.0,2.0,1,0,01/01/2030,31/12/2099,0,,\n';

    test('parses valid summits with altitude, points and winter bonus', () {
      final r = parseSota(csv, today: today);
      expect(r.map((e) => e.ref), ['3B8/MU-001', 'SP/BZ-005']);
      final t = r[1];
      expect(t.name, 'Turbacz');
      expect(t.altM, 1310);
      expect(t.points, 8);
      expect(t.bonus, 3);
      expect(t.lat, closeTo(49.54279, 1e-9));
      expect(t.lon, closeTo(20.11160, 1e-9));
      expect(t.extra, 'Poland · Beskidy Zachodnie');
      expect(r[0].name, contains('Rivière')); // quoted name with non-ASCII
    });

    test('skips retired and not-yet-valid summits', () {
      final refs = parseSota(csv, today: today).map((e) => e.ref);
      expect(refs, isNot(contains('XX/RT-001')));
      expect(refs, isNot(contains('XX/FU-001')));
    });
  });

  test('POTA keeps only active parks', () {
    const csv = '"reference","name","active","entityId","locationDesc","latitude","longitude","grid"\n'
        '"US-0001","Acadia National Park","1","291","US-ME","44.31","-68.2034","FN54vh"\n'
        '"US-9999","Closed Park","0","291","US-ME","44.0","-68.0","FN54aa"\n';
    final r = parsePota(csv);
    expect(r, hasLength(1));
    expect(r.single.ref, 'US-0001');
    expect(r.single.extra, 'US-ME');
    expect(r.single.points, 0);
  });

  test('WWFF keeps active refs and survives multi-line quoted changelogs', () {
    const csv = 'reference,status,name,program,dxcc,state,county,continent,iota,iaruLocator,'
        'latitude,longitude,IUCNcat,validFrom,validTo,notes,lastMod,changeLog,reviewFlag,'
        'specialFlags,website,country,region,dxccEnum,qsoCount,lastAct\n'
        '1SFF-0001,active,Spratly,1SFF,1S,1S,1S,AS,-,OJ58XO,8.61946,111.92416,n/a,0000-00-00,'
        '0000-00-00,"IOTA AS-051","2023-08-23 by M0YMA - Updated","2023-08-23 by M0YMA - Updated: '
        'Lat/Lon, Locator<br>2023-04-21 by ON4BB,\nmore",0,,-,"Spratly Archipelago",-,,,\n'
        'XXFF-0001,deleted,Gone,XXFF,XX,XX,XX,EU,-,JO00AA,50.0,10.0,n/a,,,,,,0,,-,X,-,,,\n';
    final r = parseWwff(csv);
    expect(r, hasLength(1));
    expect(r.single.ref, '1SFF-0001');
    expect(r.single.name, 'Spratly');
    expect(r.single.extra, 'Spratly Archipelago');
  });

  group('IOTA', () {
    test('uses the bounding-box centre and stores the box', () {
      const json = '[{"refno":"AF-001","name":"Agalega Islands","latitude_max":"-10.75",'
          '"latitude_min":"-10.00","longitude_max":"57.00","longitude_min":"56.25",'
          '"sub_groups":[{"status":"Active"}]}]';
      final r = parseIota(json).single;
      expect(r.ref, 'AF-001');
      expect(r.lat, closeTo(-10.375, 1e-9));
      expect(r.lon, closeTo(56.625, 1e-9));
      final box = r.bbox!;
      expect(box.latMin, -10.75);
      expect(box.latMax, -10.0);
    });

    test('unwraps groups crossing the antimeridian', () {
      const json = '[{"refno":"OC-999","name":"Dateline","latitude_max":"-16","latitude_min":"-18",'
          '"longitude_max":"-179","longitude_min":"179","sub_groups":[]}]';
      final r = parseIota(json).single;
      expect(r.lon.abs(), closeTo(180, 1e-9)); // centre sits on the dateline, not at 0°
    });

    test('skips groups whose islands are all deleted', () {
      const json = '[{"refno":"XX-1","name":"Gone","latitude_max":"1","latitude_min":"0",'
          '"longitude_max":"1","longitude_min":"0","sub_groups":[{"status":"Deleted"}]}]';
      expect(parseIota(json), isEmpty);
    });
  });

  test('BOTA (WWBOTA) JSON', () {
    const json = '[{"dxcc":497,"reference":"B/9A-0001","type":"Kingdom of Yugoslavia",'
        '"long":16.318265,"extra":{},"scheme":"9ABOTA","name":"Krči","lat":45.448409,"locator":"JN85DK"}]';
    final r = parseBota(json).single;
    expect(r.ref, 'B/9A-0001');
    expect(r.name, 'Krči');
    expect(r.extra, '9ABOTA · Kingdom of Yugoslavia');
  });

  test('LLOTA JSON with string coordinates', () {
    const json = '[{"id":330,"reference_code":"LLAR-0001","name":"Laguna del Diamante",'
        '"latitude":"-34.163931","longitude":"-69.694026","region":"Mendoza",'
        '"country_name":"Argentina"},{"reference_code":"LL-BAD","name":"No coords",'
        '"latitude":null,"longitude":null}]';
    final r = parseLlota(json);
    expect(r, hasLength(1));
    expect(r.single.ref, 'LLAR-0001');
    expect(r.single.extra, 'Mendoza · Argentina');
  });

  group('normalized file codec', () {
    test('HamRef round-trips through TSV (tabs/newlines in names are cleaned)', () {
      const r = HamRef(ref: 'SP/BZ-005', name: 'Tur\tbacz\n', lat: 49.54279, lon: 20.1116,
          altM: 1310, points: 8, bonus: 3, extra: 'Poland · Beskidy');
      final back = HamRef.fromTsv(r.toTsv())!;
      expect(back.name, 'Tur bacz');
      expect(back.altM, 1310);
      expect(back.points, 8);
      expect(back.bonus, 3);
      expect(back.lat, closeTo(r.lat, 1e-5));
    });

    test('file header encodes category, date and count', () {
      final text = encodeRefFile('sota', DateTime(2026, 11, 9), const [
        HamRef(ref: 'A', name: 'a', lat: 1, lon: 2),
      ]);
      final h = RefFileHeader.parse(text.split('\n').first)!;
      expect(h.categoryId, 'sota');
      expect(h.date, DateTime(2026, 11, 9));
      expect(h.count, 1);
    });
  });

  group('TOTA', () {
    test('semicolon CSV, altitude, access notes, bad coords skipped', () {
      const body = 'Ref;Nazev;Obec;Kraj;Lat;Lon;Kota_m;Vyska_veze_m;Pristupna\r\n'
          'OK-T0001;Rozhledna Kleť;Holubov;Jihočeský;48.8650;14.2833;1084;20;ano\r\n'
          'OK-T0002;"Věž; stará";Brno;Jihomoravský;49.2;16.6;300;;ne\r\n'
          'OK-T0003;Nowhere;X;Y;0;0;10;;ano\r\n';
      final r = parseTota(body);
      expect(r.map((e) => e.ref), ['OK-T0001', 'OK-T0002']);
      expect(r[0].altM, 1084);
      expect(r[0].extra, 'Holubov · Jihočeský · tower 20 m');
      expect(r[1].name, 'Věž; stará');
      expect(r[1].extra, contains('no public access'));
    });
  });

  group('GMA', () {
    test('GeoJSON region part', () {
      const body = '{"type":"FeatureCollection","features":['
          '{"type":"Feature","properties":{"ref":"DL/AL-001","name":"Zugspitze","points":10},'
          '"geometry":{"type":"Point","coordinates":[10.9863,47.4211]}},'
          '{"type":"Feature","properties":{"ref":"","name":"x"},'
          '"geometry":{"type":"Point","coordinates":[1,1]}},'
          '{"type":"Feature","properties":{"ref":"DL/AL-002","name":"y"},"geometry":null}]}';
      final r = parseGmaRegion(body);
      expect(r, hasLength(1));
      expect(r.single.ref, 'DL/AL-001');
      expect(r.single.lat, closeTo(47.4211, 1e-9));
      expect(r.single.lon, closeTo(10.9863, 1e-9));
      expect(r.single.points, 10);
      expect(parseGmaRegion('[]'), isEmpty);
    });
  });

  group('WCA', () {
    test('JSON prefix part, string coordinates', () {
      const body = '[{"ref":"OK-00001","name":"Karlštejn","latitude":"49.9394",'
          '"longitude":"14.1883","cota":"SC-001","ort":"Karlštejn"},'
          '{"ref":"OK-00002","name":"No coords","latitude":"","longitude":""}]';
      final r = parseCotaPrefix(body);
      expect(r, hasLength(1));
      expect(r.single.ref, 'OK-00001');
      expect(r.single.lat, closeTo(49.9394, 1e-9));
      expect(r.single.extra, 'SC-001 · Karlštejn');
    });
  });

  group('fetchRefs', () {
    test('multi-part: index, per-part parse, dedupe, failed parts skipped', () async {
      final src = refSources[PoiCategory.gma]!;
      String feat(String ref, double lon, double lat) =>
          '{"properties":{"ref":"$ref","name":"$ref"},'
          '"geometry":{"coordinates":[$lon,$lat]}}';
      String part(List<String> f) => '{"features":[${f.join(',')}]}';
      final responses = {
        src.url: '["A","B","C"]',
        src.partUrl!.replaceAll('{key}', 'A'): part([feat('A-1', 1, 1), feat('X-1', 2, 2)]),
        src.partUrl!.replaceAll('{key}', 'B'): part([feat('X-1', 2, 2), feat('B-1', 3, 3)]),
      };
      final progress = <int>[];
      final r = await fetchRefs(PoiCategory.gma, (url) async {
        final v = responses[url];
        if (v == null) throw Exception('404');
        return v;
      }, pause: Duration.zero, onProgress: (d, t) => progress.add(d));
      expect(r.refs.map((e) => e.ref), ['A-1', 'X-1', 'B-1']);
      expect(r.failedParts, 1);
      expect(progress, [1, 2, 3]);
    });

    test('multi-part: majority of parts failing throws', () async {
      final src = refSources[PoiCategory.wca]!;
      expect(
        fetchRefs(PoiCategory.wca, (url) async {
          if (url == src.url) return '["A","B","C"]';
          throw Exception('down');
        }, pause: Duration.zero),
        throwsStateError,
      );
    });

    test('single-part: one GET + parse', () async {
      final calls = <String>[];
      final r = await fetchRefs(PoiCategory.llota, (url) async {
        calls.add(url);
        return '[]';
      });
      expect(calls, [refSources[PoiCategory.llota]!.url]);
      expect(r.refs, isEmpty);
    });
  });

  group('GMA map layers', () {
    test('MOTA: mill type in extra, 9999 placeholder positions dropped', () {
      const body = '{"type":"FeatureCollection","features":['
          '{"geometry":{"type":"Point","coordinates":[0.84887,51.1912]},'
          '"properties":{"id":"2478","ref":"X02478","name":"Westwell Mill","type":1}},'
          '{"geometry":{"type":"Point","coordinates":[10.854459,51.039397]},'
          '"properties":{"id":"113","ref":"X00113","name":"Bockwindm\\u00fchle Kleinfahner","type":2}},'
          '{"geometry":{"type":"Point","coordinates":[9999.99999999,9999.99999999]},'
          '"properties":{"id":"9","ref":"X00009","name":"Lost","type":0}}]}';
      final r = parseMotaPrefix(body);
      expect(r.map((e) => e.ref), ['X02478', 'X00113']);
      expect(r[0].extra, 'water mill');
      expect(r[1].name, 'Bockwindmühle Kleinfahner');
      expect(r[1].extra, 'windmill');
    });

    test('GIA and SBW single GeoJSON files', () {
      final gia = parseGia('{"features":[{"geometry":{"coordinates":[12.446818,52.936233]},'
          '"properties":{"ref":"DAI/BB-001","name":"Unterseeinsel","ref2":"","wff":"DLFF-0001"}}]}');
      expect(gia.single.ref, 'DAI/BB-001');
      expect(gia.single.extra, 'WWFF DLFF-0001');
      final sbw = parseSbw('{"features":[{"geometry":{"coordinates":[13.74580002,50.73189926]},'
          '"properties":{"ref":"DA/SX-001","name":"Großer Lugstein","points":8}}]}');
      expect(sbw.single.points, 8);
      expect(sbw.single.lat, closeTo(50.7319, 1e-4));
    });

    test('ARLHS: refs normalized, malformed skipped, cross-refs kept', () {
      const body = '[{"id":930,"arlhs":"FED 001","illw":"DE0088","wlota":66,"name":"Alte Weser",'
          '"iota":"","dxcc":"DL","latitude":53.86299896,"longitude":8.12800026},'
          '{"id":944,"arlhs":"FAR-029","illw":"FO0003","wlota":"","name":"Skansin Lighthouse",'
          '"iota":"EU-018","dxcc":"OY","latitude":62.0078,"longitude":-6.7633},'
          '{"id":1,"arlhs":1,"name":"bad","latitude":1,"longitude":1},'
          '{"id":945,"arlhs":"FED-001","name":"dup","latitude":53.8,"longitude":8.1}]';
      final r = parseArlhs(body);
      expect(r.map((e) => e.ref), ['FED-001', 'FAR-029']);
      expect(r[0].extra, 'DL · ILLW DE0088 · WLOTA L 0066');
      expect(r[1].extra, 'OY · ILLW FO0003 · IOTA EU-018');
    });

    test('WLOTA: integer ref → "L nnnn", duplicates dropped', () {
      const body = '[{"id":1,"wlota":504,"arlhs":"","name":"Albatross Island","iota":"",'
          '"dxcc":"3B7","latitude":-16.25,"longitude":59.5900001},'
          '{"id":2,"wlota":504,"name":"dup","latitude":-16.2,"longitude":59.5},'
          '{"id":3,"wlota":"","name":"none","latitude":1,"longitude":1}]';
      final r = parseWlota(body);
      expect(r.single.ref, 'L 0504');
      expect(r.single.extra, '3B7');
    });
  });

  group('SiOTA', () {
    test('valid silos only, extra from locality/state', () {
      const body = 'ID,LAT,LNG,ARTY,NAME,LOCALITY,STATE,COUNTRY,SILO_CODE,RAILWAY,RAIL_STATUS,'
          'NOT_BEFORE,NOT_AFTER,TOTAL_ACTIVATIONS\n'
          '1554,-32.169081,150.892421,false,Aberdeen,Aberdeen,New South Wales,Australia,VK-ABN2,'
          'Hunter Line,Operational,2021-03-27T11:17:02Z,,2\n'
          '1600,-35.1,146.4,true,Artful,Somewhere,Victoria,Australia,VK-ART3,x,x,2021-03-27T11:17:02Z,,0\n'
          '1595,-35.166007,146.489323,false,Gone,Boree Creek,New South Wales,Australia,VK-YLA2,'
          'x,Abandoned,2021-03-27T11:17:02Z,2024-01-01T00:00:00Z,0\n';
      final r = parseSiota(body, today: DateTime.utc(2026, 11, 9));
      expect(r.map((e) => e.ref), ['VK-ABN2', 'VK-ART3']);
      expect(r[0].extra, 'Aberdeen · New South Wales');
      expect(r[1].extra, contains('silo art'));
    });
  });

  group('ZLOTA', () {
    test('WKT point (lon lat), altitude, type + region, inactive skipped', () {
      const body = '[{"id":480,"asset_type":"hut","code":"ZLH/HB-072","name":"Tarn Bivvy",'
          '"location":"POINT (176.14408304049422 -39.88369126984689)","altitude":null,'
          '"is_active":true,"region":"ZL1-HB"},'
          '{"id":38878,"asset_type":"volcano","code":"ZLV/AK-001","name":"Rarotonga / Mount Smart",'
          '"location":"POINT (174.8125 -36.91833)","altitude":20,"is_active":true,"region":"ZL1-AK"},'
          '{"id":1,"asset_type":"hut","code":"ZLH/XX-001","name":"Old","location":"POINT (170 -40)",'
          '"is_active":false}]';
      final r = parseZlota(body);
      expect(r.map((e) => e.ref), ['ZLH/HB-072', 'ZLV/AK-001']);
      expect(r[0].lat, closeTo(-39.8837, 1e-4));
      expect(r[0].lon, closeTo(176.1441, 1e-4));
      expect(r[0].extra, 'hut · ZL1-HB');
      expect(r[1].altM, 20);
    });
  });

  group('HEMA', () {
    const countries = "<a href='country.jsp?countryCode=GW'>GW</a>"
        "<a href='country.jsp?countryCode=VK3'>VK3</a><a href='country.jsp?countryCode=GW'>x</a>";
    const country = "<a href='region.jsp?countryCode=GW&regionCode=HSW'>South</a>"
        "<a href='region.jsp?countryCode=GW&amp;regionCode=HNW'>North</a>";
    const region = """
	<tr>
		<td class='line'><a href='fullSummit.jsp?summitKey=5268'>001 - Allt Cunedda</a></td>

		<td class='lineNumber'>192m</td>
</tr>
	<tr>
		<td class='lineOdd'><a href='fullSummit.jsp?summitKey=5267'>002 - Banc y Llyn &amp; Co</a></td>

		<td class='lineOddNumber'>280m</td>
</tr>""";
    const mapping = """
var Latitude=51.757;
var Longitude=-4.3098;
var nName="Allt Cunedda";
var nLabel='1';
google.maps.event.addDomListener(marker, 'click', function() {document.getElementById('right').contentWindow.location.href = 'mappingSummit.jsp?summitKey=5268';});
var Latitude=51.9;
var Longitude=-4.1;
var nName="Banc y Llyn";
google.maps.event.addDomListener(marker, 'click', function() {document.getElementById('right').contentWindow.location.href = 'mappingSummit.jsp?summitKey=5267';});
""";

    test('page extractors', () {
      expect(parseHemaCountries(countries), ['GW', 'VK3']);
      expect(parseHemaRegions(country, 'GW'), ['HSW', 'HNW']);
      final rows = parseHemaRegionRows(region);
      expect(rows.map((r) => (r.key, r.num, r.name, r.altM)),
          [(5268, '001', 'Allt Cunedda', 192), (5267, '002', 'Banc y Llyn & Co', 280)]);
      expect(parseHemaRegionRows(
              "<a href='fullSummit.jsp?summitKey=1'>003 - NoNameFound</a></td><td>10m")
          .single.name, '');
      expect(parseHemaMarkers(mapping)[5267], (lat: 51.9, lon: -4.1));
    });

    test('crawl joins region rows to map positions by summitKey', () async {
      final src = refSources[PoiCategory.hema]!;
      final pages = <String, String>{
        '${src.url}countries.jsp': "<a href='country.jsp?countryCode=GW'>GW</a>",
        '${src.url}country.jsp?countryCode=GW': country,
        '${src.url}mapping.jsp?countryCode=GW&regionCode=0&summitKey=0&action=&genericKey=': mapping,
        '${src.url}region.jsp?countryCode=GW&regionCode=HSW': region,
        // HNW missing → one failed request, rest still installed
      };
      final r = await fetchRefs(PoiCategory.hema, (url) async {
        final p = pages[url];
        if (p == null) throw Exception('404 $url');
        return p;
      }, pause: Duration.zero);
      expect(r.refs.map((e) => e.ref), ['GW/HSW-001', 'GW/HSW-002']);
      expect(r.refs.first.altM, 192);
      expect(r.refs.first.lat, 51.757);
      expect(r.failedParts, 1);
    });
  });

  test('ZLOTA rules are resolved per asset type', () {
    expect(ruleFor(PoiCategory.zlota, 'ZLH/HB-072')!.zoneMeters, 100);
    expect(ruleFor(PoiCategory.zlota, 'ZLP/WK-0001')!.zone, ZoneKind.insideArea);
    expect(ruleFor(PoiCategory.zlota, 'ZLX/??')!.zone, ZoneKind.unknown);
    expect(ruleFor(PoiCategory.sota, 'G/LD-001'), same(activationRules[PoiCategory.sota]));
  });

  test('fetchRefs: static part keys skip the index request', () async {
    final calls = <String>[];
    final r = await fetchRefs(PoiCategory.zlota, (url) async {
      calls.add(url);
      return '[]';
    }, pause: Duration.zero);
    expect(calls, hasLength(refSources[PoiCategory.zlota]!.staticKeys!.length));
    expect(calls.first, contains('asset_type=hut'));
    expect(r.refs, isEmpty);
  });

  test('every reference program with a source has a test fixture above', () {
    // Guards against adding a source without covering its parser here.
    const covered = {
      PoiCategory.sota, PoiCategory.pota, PoiCategory.wwff,
      PoiCategory.iota, PoiCategory.bota, PoiCategory.llota,
      PoiCategory.tota, PoiCategory.gma, PoiCategory.wca,
      PoiCategory.mota, PoiCategory.gia, PoiCategory.sbw, PoiCategory.arlhs,
      PoiCategory.wlota, PoiCategory.siota, PoiCategory.zlota, PoiCategory.hema,
    };
    expect(refSources.keys.toSet().difference(covered), isEmpty,
        reason: 'add a fixture-based test for the new source');
  });

  group('text repair (applied by the TSV codec)', () {
    test('mojibake: one and two layers, mixed with correct text', () {
      expect(repairText('KÄ™pa'), 'Kępa'); // GIA SOI/PK-001
      expect(repairText('Králičí­ ostrov'), 'Králičí ostrov');
      expect(repairText('CabeÃ§o de SÃ£o'), 'Cabeço de São');
      expect(repairText('FÃƒÂ¢ntÃƒÂ¢na'), 'Fântâna');
      expect(repairText('â€œStryiskyi parkâ€\u009d'), '“Stryiskyi park”');
    });

    test('correct text is left alone', () {
      for (final s in ['Stráž (Šumava)', 'Kryt ÚŽ-6', 'Großer Lugstein',
          '嘉代山', 'Колония', 'Plain ASCII']) {
        expect(repairText(s), s);
      }
    });

    test('entities, soft hyphens and spaces', () {
      expect(repairText('Ilot M&#039;BÃ©'), "Ilot M'Bé");
      expect(repairText('Fish &amp; Chips &#269;'), 'Fish & Chips č');
      expect(repairText('Kerl­ing­ar­fjöll'), 'Kerlingarfjöll');
      expect(repairText('St. Nikolai  Kirche '), 'St. Nikolai Kirche');
    });

    test('codec cleans names and extras, keeps the reference code', () {
      const r = HamRef(ref: 'SOI/PK-001', name: 'KÄ™pa', lat: 50.4, lon: 21.3, extra: 'A &amp; B');
      final back = HamRef.fromTsv(r.toTsv())!;
      expect(back.name, 'Kępa');
      expect(back.extra, 'A & B');
      expect(back.ref, 'SOI/PK-001');
    });
  });
}
