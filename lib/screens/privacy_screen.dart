import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _confirmAndDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text(
          'Das löscht deine gesamte erkundete Karte, Statistiken und '
          'Achievements unwiderruflich. Diese Aktion kann nicht rückgängig '
          'gemacht werden.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.instance.deleteAllData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle Daten wurden gelöscht.')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutz')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            'Wo werden meine Daten gespeichert?',
            'Alle Standortdaten - erkundete Gebiete, zurückgelegte Strecke, '
                'Erkundungstage und Achievements - werden ausschließlich '
                'lokal auf diesem Gerät in einer SQLite-Datenbank gespeichert. '
                'Es gibt keine Server-Übertragung und keine Cloud-Synchronisation.',
          ),
          _section(
            'Werden Daten an Dritte weitergegeben?',
            'Nein. Es findet keinerlei Analytics oder Tracking mit Standort- '
                'daten statt, und es werden keine Daten an Dritte übermittelt.',
          ),
          _section(
            'Welche Berechtigungen benötigt die App und warum?',
            '• Standort (während der Nutzung): um die Karte um deine aktuelle '
                'Position aufzudecken.\n'
                '• Standort (immer/Hintergrund): damit die Karte auch '
                'aufgedeckt wird, während die App im Hintergrund läuft, '
                'z.B. während einer Autofahrt.\n'
                'Beide Berechtigungen können jederzeit in den System-'
                'einstellungen widerrufen werden - die App funktioniert dann '
                'nur noch, während sie aktiv geöffnet ist.',
          ),
          _section(
            'Werden personenbezogene Daten benötigt?',
            'Nein. Die App benötigt kein Konto, keine E-Mail-Adresse und '
                'keinen Namen. Standortdaten werden nicht mit einer Identität '
                'verknüpft, die über dieses Gerät hinausgeht.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => _confirmAndDelete(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Meine Daten löschen'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: Colors.grey[300], height: 1.4)),
        ],
      ),
    );
  }
}
