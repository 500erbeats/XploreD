import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/settings_service.dart';
import '../services/tile_download_service.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function(bool enabled) onTrackingToggle;

  const SettingsScreen({super.key, required this.onTrackingToggle});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _tileDownload = TileDownloadService();
  final _cartoKeyController = TextEditingController();

  bool _trackingEnabled = true;
  double _distanceFilter = SettingsService.defaultDistanceFilter;
  bool? _batteryOptimizationIgnored;
  bool _loading = true;
  String _mapTheme = 'light';
  DateTime? _lastSync;
  TileDownloadProgress? _downloadProgress;
  StreamSubscription<TileDownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    _progressSub = _tileDownload.onProgress.listen((p) {
      if (mounted) setState(() => _downloadProgress = p);
    });
    _load();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _tileDownload.dispose();
    _cartoKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tracking = await _settings.isBackgroundTrackingEnabled();
    final filter = await _settings.getDistanceFilterMeters();
    final mapTheme = await _settings.getMapTheme();
    final cartoKey = await _settings.getCartoApiKey();
    final lastSync = await _settings.getLastTileSyncAt();

    bool? batteryStatus;
    if (Platform.isAndroid) {
      batteryStatus = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    }

    if (!mounted) return;
    setState(() {
      _trackingEnabled = tracking;
      _distanceFilter = filter;
      _batteryOptimizationIgnored = batteryStatus;
      _mapTheme = mapTheme;
      _cartoKeyController.text = cartoKey ?? '';
      _lastSync = lastSync;
      _loading = false;
    });
  }

  Future<void> _onTrackingChanged(bool value) async {
    setState(() => _trackingEnabled = value);
    await _settings.setBackgroundTrackingEnabled(value);
    await widget.onTrackingToggle(value);
  }

  Future<void> _onDistanceFilterChanged(double value) async {
    setState(() => _distanceFilter = value);
    await _settings.setDistanceFilterMeters(value);
  }

  Future<void> _requestBatteryExemption() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    final status = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (mounted) setState(() => _batteryOptimizationIgnored = status);
  }

  Future<void> _onMapThemeChanged(String theme) async {
    setState(() => _mapTheme = theme);
    await _settings.setMapTheme(theme);
  }

  Future<void> _saveCartoKey() async {
    final key = _cartoKeyController.text.trim();
    await _settings.setCartoApiKey(key);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API-Key gespeichert.')),
      );
    }
  }

  Future<void> _confirmAndDownloadTiles() async {
    final apiKey = _cartoKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erst einen API-Key eintragen und speichern.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Karte vorladen?'),
        content: const Text(
          'Das lädt die komplette Region in mittlerer Zoomstufe herunter '
          '(ca. 100–180 MB). Straßenebene wird weiterhin nur dort nachgeladen, '
          'wo du tatsächlich unterwegs bist.\n\n'
          'Empfohlen: über WLAN, nicht über mobile Daten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Herunterladen')),
        ],
      ),
    );

    if (confirmed != true) return;
    await _downloadTiles(apiKey);
  }

  Future<void> _downloadTiles(String apiKey) async {
    await _tileDownload.downloadRegion(apiKey: apiKey, darkTheme: _mapTheme == 'dark');
    final newSync = await _settings.getLastTileSyncAt();
    if (mounted) {
      setState(() {
        _lastSync = newSync;
        _downloadProgress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Karte wurde für Offline-Nutzung vorgeladen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Erkundung'),
          const Divider(height: 40),
          _sectionTitle('Darstellung'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('Helle Karte'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 'dark', label: Text('Dunkle Karte'), icon: Icon(Icons.nightlight_outlined)),
            ],
            selected: {_mapTheme},
            onSelectionChanged: (selection) => _onMapThemeChanged(selection.first),
          ),
          SwitchListTile(
            title: const Text('Hintergrund-Tracking'),
            subtitle: const Text(
              'Erkunde die Karte auch, wenn die App im Hintergrund läuft.',
            ),
            value: _trackingEnabled,
            onChanged: _onTrackingChanged,
          ),
          const SizedBox(height: 8),
          _sliderTile(
            title: 'GPS-Update-Distanz',
            subtitle:
                '${_distanceFilter.round()} m – niedriger = genauer, aber höherer Akkuverbrauch',
            value: _distanceFilter,
            min: 20,
            max: 200,
            divisions: 9,
            onChanged: _onDistanceFilterChanged,
          ),
          const Divider(height: 40),
          _sectionTitle('Kartenanbieter'),
          TextField(
            controller: _cartoKeyController,
            decoration: const InputDecoration(
              labelText: 'CARTO API-Key',
              hintText: 'Kostenlos unter carto.com/basemaps/apikey',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _saveCartoKey, child: const Text('Key speichern')),
          ),
          const SizedBox(height: 16),
          if (_downloadProgress != null) ...[
            LinearProgressIndicator(value: _downloadProgress!.ratio),
            const SizedBox(height: 4),
            Text(
              '${_downloadProgress!.done}/${_downloadProgress!.total} Kacheln geladen',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
          ] else ...[
            Text(
              _lastSync != null
                  ? 'Zuletzt vorgeladen: ${_lastSync!.day}.${_lastSync!.month}.${_lastSync!.year}'
                  : 'Noch nicht vorgeladen',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _tileDownload.isRunning ? null : _confirmAndDownloadTiles,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(_lastSync == null ? 'Karte vorladen' : 'Karte neu laden'),
            ),
          ),
          const Divider(height: 40),
          if (Platform.isAndroid) ...[
            _sectionTitle('Akku (Android)'),
            ListTile(
              leading: Icon(
                _batteryOptimizationIgnored == true
                    ? Icons.battery_charging_full
                    : Icons.battery_alert,
                color: _batteryOptimizationIgnored == true ? Colors.green : Colors.orange,
              ),
              title: const Text('Akku-Optimierung ausschließen'),
              subtitle: Text(
                _batteryOptimizationIgnored == true
                    ? 'Aktiv – der Hersteller sollte das Tracking nicht mehr beenden.'
                    : 'Manche Hersteller (Xiaomi, Huawei, OnePlus) beenden Hintergrund-'
                        'Tracking sonst nach einiger Zeit.',
              ),
              trailing: _batteryOptimizationIgnored == true
                  ? null
                  : TextButton(
                      onPressed: _requestBatteryExemption,
                      child: const Text('Ausschließen'),
                    ),
            ),
            const Divider(height: 40),
          ],
          _sectionTitle('App'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.0 (MVP)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await _settings.setOnboardingCompleted(false);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Onboarding erneut anzeigen'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _sliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${value.round()} m',
          onChanged: onChanged,
        ),
      ],
    );
  }
}