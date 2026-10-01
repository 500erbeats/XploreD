import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function(bool enabled) onTrackingToggle;

  const SettingsScreen({super.key, required this.onTrackingToggle});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();

  bool _trackingEnabled = true;
  double _distanceFilter = SettingsService.defaultDistanceFilter;
  bool? _batteryOptimizationIgnored;
  bool _loading = true;
  String _mapTheme = 'light';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracking = await _settings.isBackgroundTrackingEnabled();
    final filter = await _settings.getDistanceFilterMeters();
    final mapTheme = await _settings.getMapTheme();
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