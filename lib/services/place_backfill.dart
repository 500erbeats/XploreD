import 'dart:math' as math;

import 'boundary_service.dart';
import 'storage_service.dart';

/// Ordnet allen Zellen ohne place_id ihren Ort zu (in Batches, mit
/// Fortschritt) und trägt danach die Orte als besucht ein.
Future<int> backfillPlaceIds({
  void Function(int done, int total)? onProgress,
}) async {
  final storage = StorageService.instance;
  final cells = await storage.getCellsWithoutPlaceId();
  final total = cells.length;
  const chunkSize = 500;

  for (var start = 0; start < total; start += chunkSize) {
    final end = math.min(start + chunkSize, total);
    final updates = <String, String?>{};
    for (var i = start; i < end; i++) {
      final c = cells[i];
      updates[c.geohash] =
          BoundaryService.instance.placeContaining(c.centerLat, c.centerLng)?.id;
    }
    await storage.updateCellPlaceIds(updates);
    onProgress?.call(end, total);
    // UI-Thread kurz atmen lassen, damit der Fortschritt sichtbar bleibt.
    await Future<void>.delayed(Duration.zero);
  }

  await storage.syncVisitedPlacesFromCells();
  return total;
}