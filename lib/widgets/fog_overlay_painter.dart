import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/explored_cell.dart';


class FogOverlayPainter extends CustomPainter {
  final List<ExploredCell> exploredCells;
  final MapCamera camera;
  final double urbanRadiusMeters;
  final double ruralRadiusMeters;
  final Color fogColor;

  FogOverlayPainter({
    required this.exploredCells,
    required this.camera,
    this.urbanRadiusMeters = 100,
    this.ruralRadiusMeters = 300,
    this.fogColor = const Color(0xCC0A0E1A),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final fogPath = ui.Path()..addRect(fullRect);

    ui.Path? revealedPath;
    for (final cell in exploredCells) {
      final screenPoint = camera.latLngToScreenPoint(
        LatLng(cell.centerLat, cell.centerLng),
      );
      final center = Offset(screenPoint.x.toDouble(), screenPoint.y.toDouble());

      final inTown = cell.placeId != null;
      final radiusMeters = inTown ? urbanRadiusMeters : ruralRadiusMeters;
      final radiusPx = _metersToPixels(radiusMeters, cell.centerLat, camera.zoom);

      if (!fullRect.inflate(radiusPx).contains(center)) continue;

      final circlePath = ui.Path()..addOval(Rect.fromCircle(center: center, radius: radiusPx));
      revealedPath = revealedPath == null
          ? circlePath
          : ui.Path.combine(ui.PathOperation.union, revealedPath, circlePath);
    }

    final finalFogPath = revealedPath == null
        ? fogPath
        : ui.Path.combine(ui.PathOperation.difference, fogPath, revealedPath);

    canvas.drawPath(finalFogPath, Paint()..color = fogColor);
  }

  double _metersToPixels(double meters, double latitude, double zoom) {
    final metersPerPixel = (156543.03392 * math.cos(latitude * math.pi / 180)) / math.pow(2, zoom);
    return meters / metersPerPixel;
  }

  @override
  bool shouldRepaint(covariant FogOverlayPainter oldDelegate) {
    return oldDelegate.exploredCells.length != exploredCells.length ||
        oldDelegate.camera != camera;
  }
}