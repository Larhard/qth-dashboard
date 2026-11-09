import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:url_launcher/url_launcher.dart';

import '../config/ref_sources.dart';
import '../models/poi_hit.dart';
import '../refdata/activation_rules.dart';
import '../settings/display_settings.dart';
import '../theme/palette.dart';
import '../utils/coordinate_utils.dart';
import '../utils/formatting.dart';
import '../utils/mgrs_utils.dart';
import 'poi_widgets.dart';

/// Detail sheet for an amateur-radio reference: identity, location in the user's
/// coordinate format, activation essentials (+ the GPS zone estimate and its
/// caveat), and actions — copy coordinates, open in a map app, open the rules.
class RefDetailSheet extends StatelessWidget {
  final PoiHit hit;
  final bool dayMode;
  final Position? position;
  final SpeedUnit speedUnit;
  final CoordFormat coordFormat;
  final LocatorType locatorType;

  const RefDetailSheet({
    super.key,
    required this.hit,
    required this.dayMode,
    required this.position,
    required this.speedUnit,
    required this.coordFormat,
    required this.locatorType,
  });

  void _copy(BuildContext ctx, String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Copied: $text', style: TextStyle(color: Palette.of(dayMode).textSecondary)),
      backgroundColor: Palette.of(dayMode).snackBg,
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext ctx) {
    final pal = Palette.of(dayMode);
    final ref = hit.ref!;
    final rule = ruleFor(hit.category, hit.ref?.ref);
    final color = pal.poi(hit.category);
    final label = pal.textDim;
    final value = pal.textPrimary;

    Widget row(String l, String v, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 110, child: Text(l, style: TextStyle(fontSize: 13, color: label))),
              Expanded(child: Text(v, style: TextStyle(fontSize: 14, color: value))),
            ]),
          ),
        );

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(t.toUpperCase(),
              style: TextStyle(fontSize: 11, color: label, letterSpacing: 2, fontWeight: FontWeight.w700)),
        );

    final loc = locatorType == LocatorType.maidenhead
        ? maidenhead(ref.lat, ref.lon)
        : mgrs(ref.lat, ref.lon);

    String zoneText(ActivationRule r) => switch (r.zone) {
          ZoneKind.vertical => 'Within ${r.zoneMeters} m vertically of the summit',
          ZoneKind.radius => r.zoneFromPoint
              ? 'Within ${r.zoneMeters} m of the object'
              : 'Within ${r.zoneMeters} m (see note)',
          ZoneKind.insideArea => 'Inside the reference boundary',
          ZoneKind.onIsland => 'On an island of the group',
          ZoneKind.unknown => 'Not confirmed — check the rules',
        };

    final est = (rule != null && rule.zone == ZoneKind.vertical && position != null)
        ? estimateVerticalZone(
            summitAltM: ref.altM, gpsAltM: position!.altitude,
            distKm: hit.distKm, zoneMeters: rule.zoneMeters)
        : null;
    final inRadius = (rule != null && position != null) ? inRadiusZone(rule, hit.distKm) : null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: pal.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Center(
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: pal.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(children: [
              PoiTag(hit.category, dayMode: dayMode, fontSize: 12),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ref.ref,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(ref.name, style: TextStyle(fontSize: 18, color: value, fontWeight: FontWeight.w600)),
            if (ref.extra.isNotEmpty && ref.bbox == null)
              Text(ref.extra, style: TextStyle(fontSize: 13, color: label)),
            if (position != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${hit.bearingDeg.round()}°  ·  ${formatDistanceUnit(hit.distKm, speedUnit)}',
                    style: TextStyle(fontSize: 14, color: pal.poiSub(hit.category))),
              ),

            section('Location'),
            row('Latitude', formatLatF(ref.lat, coordFormat), onTap: () => _copy(ctx, hit.coordsText)),
            row('Longitude', formatLonF(ref.lon, coordFormat), onTap: () => _copy(ctx, hit.coordsText)),
            row(locatorType == LocatorType.maidenhead ? 'Locator' : 'MGRS', loc,
                onTap: () => _copy(ctx, loc)),
            if (ref.altM > 0) row('Altitude', formatAlt(ref.altM.toDouble(), speedUnit)),
            if (ref.bbox != null)
              row('Group area', 'lat ${ref.bbox!.latMin}…${ref.bbox!.latMax}, '
                  'lon ${ref.bbox!.lonMin}…${ref.bbox!.lonMax}'),

            section('Activation'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RefRuleChips(hit: hit, dayMode: dayMode, fontSize: 15, position: position),
            ),
            if (ref.points > 0)
              row('Points', ref.bonus > 0 ? '${ref.points}  (+${ref.bonus} winter bonus)' : '${ref.points}'),
            if (rule != null) ...[
              row('Zone', zoneText(rule)),
              row('QSOs needed', rule.minQsos == null
                  ? (rule.verified ? 'No fixed minimum' : 'Check the rules')
                  : '${rule.minQsos}${rule.cumulative ? ' (may be accumulated)' : ''}'),
              if (est != null)
                row('Your position',
                    '${est.deltaM >= 0 ? '+' : '−'}${est.deltaM.abs().round()} m vs summit — '
                    '${est.likelyInZone ? 'likely inside' : 'likely below'} the zone'),
              if (inRadius != null)
                row('Your position',
                    '${formatDistanceUnit(hit.distKm, speedUnit)} away — '
                    '${inRadius ? 'inside' : 'outside'} the ${rule.zoneMeters} m zone'),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(rule.note, style: TextStyle(fontSize: 13, color: value, height: 1.35)),
              ),
              if (est != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Estimate from GPS altitude (typically ±10–20 m). '
                    'Confirm with the summit\'s activation-zone map.',
                    style: TextStyle(fontSize: 12, color: label, fontStyle: FontStyle.italic)),
                ),
              if (!rule.verified)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Numbers for this program are not yet confirmed — check the official rules.',
                      style: TextStyle(fontSize: 12, color: pal.stale)),
                ),
            ],

            const SizedBox(height: 20),
            Wrap(spacing: 10, runSpacing: 8, children: [
              _button(pal, Icons.content_copy, 'Copy coordinates', () => _copy(ctx, hit.coordsText)),
              _button(pal, Icons.map_outlined, 'Open in map', () => launchUrl(
                  Uri.parse('geo:${ref.lat},${ref.lon}?q=${ref.lat},${ref.lon}'
                      '(${Uri.encodeComponent('${ref.ref} ${ref.name}')})'),
                  mode: LaunchMode.externalApplication)),
              if (rule != null)
                _button(pal, Icons.gavel_outlined, 'Rules', () => launchUrl(Uri.parse(rule.rulesUrl),
                    mode: LaunchMode.externalApplication)),
              if (refSources[hit.category] != null)
                _button(pal, Icons.public, 'Program site', () => launchUrl(
                    Uri.parse(refSources[hit.category]!.homepage), mode: LaunchMode.externalApplication)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _button(Palette pal, IconData icon, String text, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: pal.textSecondary),
        label: Text(text, style: TextStyle(color: pal.textSecondary)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: pal.border),
          overlayColor: pal.rippleMuted,
        ),
      );
}
