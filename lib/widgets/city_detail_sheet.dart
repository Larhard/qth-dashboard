import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/city_service.dart';
import '../utils/coordinate_utils.dart';
import '../utils/mgrs_utils.dart';
import '../utils/units.dart';

// ── City / Port detail bottom sheet ──────────────────────────────────────────
//
// Shown when the user long-presses the city section.
// Cities: population, timezone, bearing/distance.
// Ports:  all available WPI navigation fields.

class CityDetailSheet extends StatelessWidget {
  final NearestCity nc;
  final bool dayMode;
  final Position? position;
  final SpeedUnit speedUnit;
  final CoordFormat coordFormat;
  final LocatorType locatorType;

  const CityDetailSheet({
    required this.nc,
    required this.dayMode,
    required this.position,
    required this.speedUnit,
    required this.coordFormat,
    required this.locatorType,
  });

  bool get _isPort => nc.city.portType.isNotEmpty;

  Color get _cLabel  => dayMode ? kDFg3   : kN3;
  Color get _cValue  => dayMode ? kDFg0   : kN1;
  Color get _cAccent => dayMode ? kDPort  : kN2;  // cyan (maritime) / night-safe red
  Color get _cWarn   => dayMode ? kDCityP : kN1;  // amber warning / bright red
  Color get _cLink   => dayMode ? kDPort  : kN2;  // cyan link (no blue) / night-safe red

  // ── Copy-all ──────────────────────────────────────────────────────────────

  /// Builds a plain-text representation of all displayed details so it can
  /// be pasted into a messaging app and sent to another crew member.
  String _buildCopyText() {
    final city = nc.city;
    final buf = StringBuffer();

    void line(String label, String value) {
      if (value.isEmpty || value == '0' || value == '0.0') return;
      buf.writeln('$label: $value');
    }

    // ── Header ───────────────────────────────────────────────────────────
    buf.writeln('${city.name} (${city.country})');
    if (position != null) {
      buf.writeln(
          '${nc.bearingDeg.round()}°  ${formatDistanceUnit(nc.distKm, speedUnit)}');
    }
    buf.writeln();

    // ── Reporter GPS position ─────────────────────────────────────────────
    if (position != null) {
      buf.writeln('GPS Position:');
      buf.writeln('  ${formatLatF(position!.latitude, coordFormat)}');
      buf.writeln('  ${formatLonF(position!.longitude, coordFormat)}');
      final locStr = locatorType == LocatorType.maidenhead
          ? '${maidenhead(position!.latitude, position!.longitude)} (IARU)'
          : '${mgrs(position!.latitude, position!.longitude)} (MGRS)';
      buf.writeln('  $locStr');
      buf.writeln();
    }

    // ── City fields ───────────────────────────────────────────────────────
    if (!_isPort) {
      buf.writeln('LOCATION');
      line('Country', city.country);
      if (city.population > 0) line('Population', formatPopulation(city.population));
      line('Timezone', city.timezone);
    }

    // ── Port fields ───────────────────────────────────────────────────────
    if (_isPort) {
      buf.writeln('PORT OVERVIEW');
      line('Type', city.portType);
      if (city.harbourSize.isNotEmpty) {
        line('Harbour class', switch (city.harbourSize) {
          'L'  => 'Large', 'M'  => 'Medium',
          'S'  => 'Small', 'VS' => 'Very Small',
          _    => city.harbourSize,
        });
      }
      line('Harbour type', city.harborType);
      line('Primary use', city.harborUse);
      if (city.shelter.isNotEmpty) line('Shelter', _shelter(city.shelter));
      line('NAVAREA', city.navarea);

      if (city.channelDepthM > 0 || city.tidalRangeM > 0 || city.maxVesselLengthM > 0) {
        buf.writeln();
        buf.writeln('DIMENSIONS');
        if (city.channelDepthM > 0)    line('Channel depth',    '${city.channelDepthM} m');
        if (city.tidalRangeM > 0)      line('Tidal range',      '${city.tidalRangeM} m');
        if (city.maxVesselLengthM > 0) line('Max vessel length','${city.maxVesselLengthM} m');
        line('Chart', city.chart);
      }

      if (city.pilotage.isNotEmpty || city.firstPortEntry.isNotEmpty ||
          city.entryRestrictions.isNotEmpty) {
        buf.writeln();
        buf.writeln('ENTRY REQUIREMENTS');
        if (city.firstPortEntry == 'Y') line('First port of entry', 'Yes');
        else if (city.firstPortEntry == 'N') line('First port of entry', 'No');
        line('Pilotage', city.pilotage);
        line('Entry restrictions', city.entryRestrictions);
      }

      if (city.vhf.isNotEmpty || city.phone.isNotEmpty || city.callSign.isNotEmpty) {
        buf.writeln();
        buf.writeln('COMMUNICATIONS');
        if (city.vhf.isNotEmpty) {
          line('VHF', 'Ch ${city.vhf.replaceAll(";", " / Ch ")}');
        }
        line('Call sign', city.callSign);
        line('Phone', city.phone);
      }

      if (city.publication.isNotEmpty || city.publicationLink.isNotEmpty) {
        buf.writeln();
        buf.writeln('PUBLICATIONS');
        line('Sailing directions', city.publication);
        line('Link', city.publicationLink);
      }

      if (city.facilities.isNotEmpty) {
        buf.writeln();
        buf.writeln('FACILITIES');
        buf.writeln(city.facilities
            .split('|')
            .where((f) => f.isNotEmpty)
            .map((f) => f.replaceAll('_', ' '))
            .join(', '));
      }
    }

    return buf.toString().trim();
  }

  void _copyAll(BuildContext ctx) {
    final text = _buildCopyText();
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _showCopied(ctx, 'Details copied — paste into any app to share');
  }

  SnackBar _snack(String text, {Duration duration = const Duration(milliseconds: 1200)}) {
    final bg = dayMode ? kDSnackBg : kNBg;
    final fg = dayMode ? kDFg1     : kN2;
    return SnackBar(
      content: Text(text, style: TextStyle(color: fg, fontSize: 13),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      backgroundColor: bg,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
    child: Text(title.toUpperCase(),
        style: TextStyle(
            fontSize: 10, color: _cLabel,
            letterSpacing: 2.5, fontWeight: FontWeight.w700)),
  );

  // ── Shared snackbar ───────────────────────────────────────────────────────
  void _showCopied(BuildContext ctx, String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(ctx).showSnackBar(_snack(value));
  }

  // ── Generic row — long-press copies the value ──────────────────────────────
  Widget _row(BuildContext ctx, String label, String value, {Color? vc}) {
    if (value.isEmpty || value == '0' || value == '0.0') return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showCopied(ctx, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: _cLabel)),
            const SizedBox(width: 16),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      color: vc ?? _cValue,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }

  // ── Phone row — tap dials, long-press copies ───────────────────────────────
  Widget _phoneRow(BuildContext ctx, String phone) {
    if (phone.isEmpty) return const SizedBox.shrink();
    final uri = Uri.parse('tel:$phone');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      onLongPress: () => _showCopied(ctx, phone),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phone', style: TextStyle(fontSize: 12, color: _cLabel)),
            const SizedBox(width: 16),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone, size: 12, color: _cAccent),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(phone,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            color: _cAccent,
                            decoration: TextDecoration.underline,
                            decorationColor: _cAccent,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Link row — tap opens browser, long-press copies ────────────────────────
  Widget _linkRow(BuildContext ctx, String label, String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    final uri = Uri.tryParse(url);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: uri != null
          ? () => launchUrl(uri, mode: LaunchMode.externalApplication)
          : null,
      onLongPress: () => _showCopied(ctx, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: _cLabel)),
            const SizedBox(width: 16),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(url,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: _cLink,
                            decoration: TextDecoration.underline,
                            decorationColor: _cLink)),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 12, color: _cLink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shelter(String s) => switch (s) {
    'E' => 'Excellent',
    'G' => 'Good',
    'F' => 'Fair',
    'P' => 'Poor',
    _   => s,
  };

  // Shelter quality — day: green→amber→orange-red scale; night: brighter = better.
  Color _shelterColor(String s) {
    if (dayMode) {
      return switch (s) {
        'E' => kDGps,              // excellent — bright green
        'G' => kDShelterGood, // good — mid green (between kDGps and kDTrk)
        'F' => kDCityP,            // fair — amber warning
        'P' => kDStale,            // poor — orange-red
        _   => _cValue,
      };
    } else {
      return switch (s) {
        'E' => kN1,  // excellent — brightest red
        'G' => kN2,
        'F' => kN3,
        'P' => kN4,  // poor — dimmest
        _   => _cValue,
      };
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final city = nc.city;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: dayMode ? kDSheetBg : kNSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(children: [
          // Drag handle row with copy-all button
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2, right: 4),
            child: Row(children: [
              const SizedBox(width: 48),
              Expanded(
                child: Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: dayMode ? kDBrd : kNDiv,
                        borderRadius: BorderRadius.circular(2))),
                ),
              ),
              SizedBox(
                width: 48,
                child: IconButton(
                  icon: Icon(Icons.content_copy, size: 20, color: _cLabel),
                  tooltip: 'Copy all details',
                  onPressed: () => _copyAll(ctx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                // Header — long-press copies the name
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _showCopied(ctx, city.name),
                  child: Text(city.name,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700,
                          color: _cValue)),
                ),
                const SizedBox(height: 4),
                if (position != null) ...[
                  Text(
                    '${nc.bearingDeg.round()}°  ·  '
                    '${formatDistanceUnit(nc.distKm, speedUnit)}  ·  '
                    '${city.country}',
                    style: TextStyle(fontSize: 13, color: _cLabel)),
                ],

                // ── City fields ───────────────────────────────────────────
                if (!_isPort) ...[
                  _section('Location'),
                  _row(ctx, 'Country', city.country),
                  _row(ctx, 'Population', formatPopulation(city.population)),
                  _row(ctx, 'Timezone', city.timezone),
                ],

                // ── Port fields ───────────────────────────────────────────
                if (_isPort) ...[
                  _section('Port overview'),
                  _row(ctx, 'Type', city.portType),
                  _row(ctx, 'Harbour class', switch (city.harbourSize) {
                    'L'  => 'Large',
                    'M'  => 'Medium',
                    'S'  => 'Small',
                    'VS' => 'Very Small',
                    _    => city.harbourSize,
                  }),
                  _row(ctx, 'Harbour type', city.harborType),
                  _row(ctx, 'Primary use', city.harborUse),
                  _row(ctx, 'Shelter', _shelter(city.shelter),
                      vc: _shelterColor(city.shelter)),
                  _row(ctx, 'NAVAREA', city.navarea),

                  if (city.channelDepthM > 0 || city.tidalRangeM > 0 ||
                      city.maxVesselLengthM > 0) ...[
                    _section('Dimensions'),
                    _row(ctx, 'Channel depth',
                        city.channelDepthM > 0 ? '${city.channelDepthM} m' : ''),
                    _row(ctx, 'Tidal range',
                        city.tidalRangeM > 0 ? '${city.tidalRangeM} m' : ''),
                    _row(ctx, 'Max vessel length',
                        city.maxVesselLengthM > 0 ? '${city.maxVesselLengthM} m' : ''),
                    _row(ctx, 'Chart', city.chart),
                  ],

                  if (city.pilotage.isNotEmpty ||
                      city.firstPortEntry.isNotEmpty ||
                      city.entryRestrictions.isNotEmpty) ...[
                    _section('Entry requirements'),
                    _row(ctx, 'First port of entry',
                        city.firstPortEntry == 'Y' ? 'Yes' :
                        city.firstPortEntry == 'N' ? 'No'  : ''),
                    _row(ctx, 'Pilotage', city.pilotage),
                    _row(ctx, 'Entry restrictions', city.entryRestrictions,
                        vc: city.entryRestrictions.isNotEmpty ? _cWarn : null),
                  ],

                  if (city.vhf.isNotEmpty || city.phone.isNotEmpty ||
                      city.callSign.isNotEmpty) ...[
                    _section('Communications'),
                    _row(ctx, 'VHF working channel', city.vhf.isNotEmpty
                        ? 'Ch ${city.vhf.replaceAll(";", " / Ch ")}' : '',
                        vc: _cAccent),
                    _row(ctx, 'Call sign', city.callSign, vc: _cAccent),
                    _phoneRow(ctx, city.phone),
                  ],

                  if (city.publication.isNotEmpty ||
                      city.publicationLink.isNotEmpty) ...[
                    _section('Publications'),
                    _row(ctx, 'Sailing directions', city.publication),
                    _linkRow(ctx, 'Link', city.publicationLink),
                  ],

                  if (city.facilities.isNotEmpty) ...[
                    _section('Facilities'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: city.facilities.split('|')
                          .where((f) => f.isNotEmpty)
                          .map((f) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: dayMode ? kDDiv : kNBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: dayMode ? kDBrd : kNDiv, width: 1)),
                            child: Text(f.replaceAll('_', ' '),
                                style: TextStyle(
                                    fontSize: 11, color: _cLabel)),
                          ))
                          .toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
