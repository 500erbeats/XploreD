import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/explored_cell.dart';

/// Zeichnet die Fog-of-War-Ebene über der Karte.
///
/// Technik: Wir zeichnen zunächst eine halbtransparente dunkle Fläche über
/// den gesamten sichtbaren Kartenausschnitt. Anschließend "stanzen" wir für
/// jede erkundete Zelle einen weichen Kreis mit `BlendMode.clear` aus dieser
/// Ebene aus. Überlappende Kreise verschmelzen dabei automatisch zu einer
/// zusammenhängenden Fläche, ohne dass wir Polygon-Union-Berechnungen
/// brauchen - das erledigt die GPU/Canvas-Compositing für uns.
///
/// Wichtig: Alles läuft auf einem separaten `Layer` (via `saveLayer`), damit
/// `BlendMode.clear` nur innerhalb dieser Ebene wirkt und nicht die
/// darunterliegende Kartenebene mit ausstanzt.
class FogOverlayPainter extends CustomPainter {
  final List<ExploredCell> exploredCells;
  final MapCamera camera;
  final double revealRadiusMeters;
  final Color fogColor;

  FogOverlayPainter({
    required this.exploredCells,
    required this.camera,
    this.revealRadiusMeters = 200,
    this.fogColor = const Color(0xCC0A0E1A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Separate Compositing-Ebene, damit BlendMode.clear nur hier wirkt.
    canvas.saveLayer(rect, Paint());

    // 1. Fog-Basisebene über den gesamten sichtbaren Bereich.
    canvas.drawRect(rect, Paint()..color = fogColor);

    // 2. Für jede erkundete Zelle: weichen Kreis ausstanzen.
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    for (final cell in exploredCells) {
      final screenPoint = camera.latLngToScreenPoint(
        LatLng(cell.centerLat, cell.centerLng),
      );

      final radiusPx = _metersToPixels(
        revealRadiusMeters,
        cell.centerLat,
        camera.zoom,
      );

      canvas.drawCircle(
        Offset(screenPoint.x.toDouble(), screenPoint.y.toDouble()),
        radiusPx,
        clearPaint,
      );
    }

    canvas.restore();
  }

  /// Umrechnung Meter -> Bildschirm-Pixel bei gegebenem Zoom-Level und
  /// Breitengrad (Standard-Web-Mercator-Formel für Tile-Karten - die
  /// Pixelgröße verzerrt sich mit dem Breitengrad, siehe cos-Faktor).
  double _metersToPixels(double meters, double latitude, double zoom) {
    final metersPerPixel = (156543.03392 * math.cos(latitude * math.pi / 180)) /
        math.pow(2, zoom);
    return meters / metersPerPixel;
  }

  @override
  bool shouldRepaint(covariant FogOverlayPainter oldDelegate) {
    return oldDelegate.exploredCells.length != exploredCells.length ||
        oldDelegate.camera != camera ||
        oldDelegate.revealRadiusMeters != revealRadiusMeters;
  }
}
