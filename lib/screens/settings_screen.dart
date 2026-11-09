import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ref_sources.dart';
import '../models/poi_category.dart';
import '../services/poi_service.dart';
import '../services/ref_updater.dart';
import '../services/reference_service.dart';
import '../theme/palette.dart';

/// App settings, reached from the Waypoints screen menu (deliberately NOT from
/// the dashboard, so nothing here can be changed by an accidental touch while
/// driving).
///
/// • Nearby POI categories — which categories the dashboard cycles through.
/// • Reference data — re-download amateur-radio reference lists from the
///   programs' official sources (the app's only network access).
class SettingsScreen extends StatefulWidget {
  final bool dayMode;
  const SettingsScreen({super.key, required this.dayMode});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Palette get _pal => Palette.of(widget.dayMode);
  final _progress = <PoiCategory, double?>{}; // null = indeterminate
  final _busy = <PoiCategory>{};

  @override
  void initState() {
    super.initState();
    ReferenceService.instance.revision.addListener(_refresh);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    ReferenceService.instance.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: TextStyle(color: _pal.textSecondary, fontSize: 13)),
        backgroundColor: _pal.snackBg,
        behavior: SnackBarBehavior.floating,
      ));

  String _status(PoiCategory c) {
    if (!c.isReference) {
      return PoiService.instance.hasData(c) ? 'Built in' : 'No data — run the setup scripts';
    }
    final info = ReferenceService.instance.info(c);
    if (info == null) {
      return refSources[c] == null ? 'No data source yet' : 'No data — tap Update below';
    }
    final d = info.date.toIso8601String().substring(0, 10);
    final origin = info.origin == RefOrigin.downloaded ? 'updated' : 'built in';
    return '${_n(info.count)} refs · $origin $d';
  }

  static String _n(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  Future<void> _update(PoiCategory c) async {
    setState(() {
      _busy.add(c);
      _progress[c] = null;
    });
    try {
      final count = await RefUpdater.update(c, onProgress: (got, total) {
        if (!mounted) return;
        setState(() => _progress[c] = total == null ? null : got / total);
      });
      _snack('${c.tag}: ${_n(count)} references installed');
    } catch (e) {
      _snack('${c.tag}: update failed — $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(c);
          _progress.remove(c);
        });
      }
    }
  }

  Future<void> _updateAll() async {
    for (final c in PoiCategory.references.where(RefUpdater.canUpdate)) {
      if (!mounted) return;
      await _update(c);
    }
  }

  Future<void> _confirmUpdateAll() async {
    final mb = PoiCategory.references
            .where(RefUpdater.canUpdate)
            .fold<int>(0, (s, c) => s + refSources[c]!.approxBytes) ~/
        (1024 * 1024);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: _pal.sheetBg,
        title: Text('Update all reference lists?', style: TextStyle(color: _pal.textPrimary)),
        content: Text('Downloads about $mb MB from the programs\' sites and GMA\'s '
            'map service. Wi-Fi recommended; HEMA takes a few minutes.', style: TextStyle(color: _pal.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Cancel', style: TextStyle(color: _pal.textDim))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Update', style: TextStyle(color: _pal.textPrimary))),
        ],
      ),
    );
    if (ok == true) _updateAll();
  }

  Widget _section(String title, [String? hint]) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: TextStyle(fontSize: 11, color: _pal.textDim, letterSpacing: 2, fontWeight: FontWeight.w700)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(hint, style: TextStyle(fontSize: 12, color: _pal.textFaint, height: 1.35)),
            ),
        ]),
      );

  Widget _dot(PoiCategory c) => Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: _pal.poi(c), shape: BoxShape.circle),
      );

  Widget _categoryTile(PoiCategory c) {
    final hasData = PoiService.instance.hasData(c);
    final on = PoiService.instance.isEnabled(c);
    return SwitchListTile(
      secondary: _dot(c),
      title: Text(c.label, style: TextStyle(color: hasData ? _pal.textPrimary : _pal.textFaint)),
      subtitle: Text(_status(c), style: TextStyle(fontSize: 12, color: _pal.textDim)),
      value: on,
      onChanged: (v) async {
        await PoiService.instance.setEnabled(c, v);
        setState(() {});
      },
      // Pin every state to the palette — Material's grey defaults would leak
      // non-red light in night mode.
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _pal.textPrimary : _pal.textFaint),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _pal.poi(c).withValues(alpha: 0.5) : _pal.tileBg),
      trackOutlineColor: WidgetStateProperty.all(_pal.border),
    );
  }

  Widget _updateTile(PoiCategory c) {
    final busy = _busy.contains(c);
    final info = ReferenceService.instance.info(c);
    final src = refSources[c]!;
    return ListTile(
      leading: _dot(c),
      title: Text(c.label, style: TextStyle(color: _pal.textPrimary)),
      subtitle: busy
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: _progress[c],
                color: _pal.poi(c),
                backgroundColor: _pal.divider,
              ),
            )
          : Text('${_status(c)} · ~${(src.approxBytes / 1048576).toStringAsFixed(src.approxBytes < 2 << 20 ? 1 : 0)} MB',
              style: TextStyle(fontSize: 12, color: _pal.textDim)),
      trailing: busy
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (info?.origin == RefOrigin.downloaded)
                IconButton(
                  tooltip: 'Revert to built-in data',
                  icon: Icon(Icons.restore, color: _pal.textDim),
                  onPressed: () async {
                    await ReferenceService.instance.deleteDownloaded(c);
                    _snack('${c.tag}: reverted to built-in data');
                  },
                ),
              IconButton(
                tooltip: 'Update via network',
                icon: Icon(Icons.cloud_download_outlined, color: _pal.textSecondary),
                onPressed: _busy.isEmpty ? () => _update(c) : null,
              ),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = PoiCategory.values.where((c) => !c.isReference);
    final ham = PoiCategory.references;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: _pal.textDim),
        title: Text('Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _pal.textDim)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section('Nearby POI categories',
              'The dashboard shows the nearest point of the current category. '
              'Long-press it to cycle through the categories enabled here; tap it to '
              'copy its coordinates. Categories without data are skipped.'),
          _section('Places'),
          ...places.map(_categoryTile),
          _section('Amateur radio — on the air'),
          ...ham.map(_categoryTile),
          Divider(color: _pal.divider, height: 32),
          _section('Reference data',
              'Each release includes the full world lists as of its build date. '
              'Update downloads the current lists from the programs\' official sites '
              '(the app\'s only use of the network). Wi-Fi recommended.'),
          ...ham.where(RefUpdater.canUpdate).map(_updateTile),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _busy.isEmpty ? _confirmUpdateAll : null,
              icon: Icon(Icons.sync, color: _pal.textSecondary),
              label: Text('Update all', style: TextStyle(color: _pal.textSecondary)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _pal.border), overlayColor: _pal.rippleMuted),
            ),
          ),
        ],
      ),
    );
  }
}
