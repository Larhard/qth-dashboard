import 'package:flutter/material.dart';

/// About / Legal screen.
///
/// Satisfies in-app attribution requirements for:
///   • GeoNames city / harbour data  — CC BY 4.0 (attribution required)
///   • OpenStreetMap contributors     — ODbL 1.0  (attribution required)
///   • NGA World Port Index           — public domain (attribution by custom)
///
/// Respects the app-wide day / night mode: night mode uses deep-red shades
/// consistent with the rest of the UI to avoid eye strain in the dark.
///
/// The "Open Source Licences" button opens Flutter's built-in licence page,
/// which renders all package licences registered via LicenseRegistry (see
/// main.dart for the data-source entries we add there).
class AboutScreen extends StatelessWidget {
  final bool dayMode;

  const AboutScreen({super.key, required this.dayMode});

  // ── Colour palette (mirrors waypoints_screen and home_screen) ────────────
  Color get _cPrimary   => dayMode ? Colors.white                : const Color(0xFFCC3333);
  Color get _cSecondary => dayMode ? const Color(0xFFCCCCCC)     : const Color(0xFF882222);
  Color get _cTertiary  => dayMode ? const Color(0xFF888888)     : const Color(0xFF551111);
  Color get _cDim       => dayMode ? const Color(0xFF666666)     : const Color(0xFF441111);
  Color get _cIcon      => dayMode ? const Color(0xFF555555)     : const Color(0xFF441111);
  Color get _cDivider   => dayMode ? const Color(0xFF1A1A1A)     : const Color(0xFF2A0000);
  Color get _cBtnFg     => dayMode ? const Color(0xFFAAAAAA)     : const Color(0xFF882222);
  Color get _cBtnBorder => dayMode ? const Color(0xFF333333)     : const Color(0xFF440000);

  // Disclaimer box colours
  Color get _cWarnBorder => dayMode ? const Color(0xFF2A2A00) : const Color(0xFF2A0000);
  Color get _cWarnBg     => dayMode ? const Color(0xFF0A0A00) : const Color(0xFF0A0000);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: _cSecondary,
        elevation: 0,
        title: Text('About & Legal',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _cSecondary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // ── App identity ──────────────────────────────────────────────────
          Text('QTH Dashboard',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _cPrimary)),
          const SizedBox(height: 4),
          Text('v1.1.0',
              style: TextStyle(fontSize: 13, color: _cDim)),
          const SizedBox(height: 12),
          _disclaimer(),

          _divider(),

          // ── Legally required attribution notices ──────────────────────────
          _sectionTitle('Data Attributions'),
          const SizedBox(height: 12),

          _credit(
            icon: Icons.location_city,
            title: 'City data',
            body: 'Provided by GeoNames (geonames.org).\n'
                'Used under the Creative Commons Attribution 4.0 '
                'International licence (CC BY 4.0).\n'
                'https://creativecommons.org/licenses/by/4.0/',
          ),

          const SizedBox(height: 16),

          _credit(
            icon: Icons.anchor,
            title: 'Port data — NGA World Port Index',
            body: 'Publication 150 produced by the National Geospatial-Intelligence '
                'Agency (NGA), United States Government.\n'
                'This is a United States Government work and is not subject '
                'to copyright protection in the United States '
                '(17 U.S.C. § 105).\n'
                'https://msi.nga.mil/Publications/WPI',
          ),

          const SizedBox(height: 16),

          _credit(
            icon: Icons.map_outlined,
            title: '© OpenStreetMap contributors',
            body: 'Inland marina and harbour data (where present) obtained '
                'from OpenStreetMap via the Overpass API.\n'
                'OpenStreetMap data is made available under the '
                'Open Database Licence 1.0 (ODbL).\n'
                'The generated ports.tsv file, when it contains OSM-derived '
                'data, is a Derived Database under the ODbL and must be '
                'redistributed under ODbL 1.0.\n'
                'https://www.openstreetmap.org/copyright\n'
                'https://opendatacommons.org/licenses/odbl/1.0/',
          ),

          _divider(),

          // ── Package licences ──────────────────────────────────────────────
          _sectionTitle('Open Source Software'),
          const SizedBox(height: 8),
          Text(
            'This app is built with Flutter and uses several open-source '
            'packages. Tap below to view their individual licences, as '
            'required by the BSD-3-Clause and MIT terms under which they '
            'are distributed.',
            style: TextStyle(
                fontSize: 13,
                color: _cTertiary,
                height: 1.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'QTH Dashboard',
              applicationVersion: 'v1.1.0',
              applicationLegalese:
                  '© 2026 Bartłomiej Puget <larhard@gmail.com>\n\n'
                  'City data © GeoNames (CC BY 4.0)\n'
                  'Port data: NGA WPI (public domain) + '
                  '© GeoNames (CC BY 4.0) + '
                  '© OpenStreetMap contributors (ODbL)',
            ),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Open Source Licences'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _cBtnFg,
              side: BorderSide(color: _cBtnBorder),
            ),
          ),

          _divider(),

          // ── App licence ───────────────────────────────────────────────────
          _sectionTitle('App Source Code'),
          const SizedBox(height: 8),
          Text(
            'The application source code is licensed under the MIT Licence.\n'
            'Copyright © 2026 Bartłomiej Puget <larhard@gmail.com>.',
            style: TextStyle(
                fontSize: 13,
                color: _cTertiary,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _disclaimer() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: _cWarnBorder),
          borderRadius: BorderRadius.circular(6),
          color: _cWarnBg,
        ),
        child: Text(
          'Vibe-coded — built with AI assistance. No formal testing, '
          'safety audit, or regulatory review has been performed. '
          'Never rely on this app as your sole means of navigation.',
          style: TextStyle(
              fontSize: 12, color: _cTertiary, height: 1.5),
        ),
      );

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _cDim,
          letterSpacing: 1.5));

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Divider(color: _cDivider, height: 1),
      );

  Widget _credit({
    required IconData icon,
    required String title,
    required String body,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _cIcon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _cSecondary)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 12,
                        color: _cTertiary,
                        height: 1.55)),
              ],
            ),
          ),
        ],
      );
}
