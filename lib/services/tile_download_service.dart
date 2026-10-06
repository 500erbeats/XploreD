import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

import 'region_service.dart';
import 'settings_service.dart';

class TileDownloadProgress {
  final int done;
  final int total;
  const TileDownloadProgress(this.done, this.total);
  double get ratio => total == 0 ? 0 : done / total;
}

/// Lädt alle Kacheln für Zoomstufen 10-15 über das komplette Regionsgebiet
/// einmalig herunter und legt sie im selben lokalen Cache ab, den auch die
/// normale Kartenanzeige nutzt. Höhere Zoomstufen (Straßenebene, 16-19)
/// werden bewusst NICHT vorgeladen - die laden weiterhin dynamisch nach,
/// nur dort, wo tatsächlich erkundet wird (sonst wären es mehrere GB fürs
/// komplette Gebiet).
class TileDownloadService {
  static const int _minZoom = 10;
  static const int _maxZoom = 15;

  final _progressController = StreamController<TileDownloadProgress>.broadcast();
  Stream<TileDownloadProgress> get onProgress => _progressController.stream;

  bool _running = false;
  bool get isRunning => _running;

  Future<void> downloadRegion({required String apiKey, required bool darkTheme}) async {
    if (_running) return;
    _running = true;

    try {
      final cacheDir = await getTemporaryDirectory();
      final cachePath = '${cacheDir.path}/map_tiles';
      await Directory(cachePath).create(recursive: true);

      final dio = Dio();
      dio.interceptors.add(
        DioCacheInterceptor(
          options: CacheOptions(
            store: FileCacheStore(cachePath),
            policy: CachePolicy.forceCache,
            maxStale: const Duration(days: 30),
          ),
        ),
      );

      final bounds = RegionService.instance.config.bounds;
      final style = darkTheme ? 'dark_all' : 'light_all';

      final urls = <String>[];
      for (int z = _minZoom; z <= _maxZoom; z++) {
        final x1 = _lngToTileX(bounds.west, z);
        final x2 = _lngToTileX(bounds.east, z);
        final y1 = _latToTileY(bounds.north, z);
        final y2 = _latToTileY(bounds.south, z);

        for (int x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
          for (int y = math.min(y1, y2); y <= math.max(y1, y2); y++) {
            urls.add('https://basemaps.cartocdn.com/rastertiles/$style/$z/$x/$y.png?key=$apiKey');
          }
        }
      }

      var done = 0;
      _progressController.add(TileDownloadProgress(0, urls.length));

      // Mit Konkurrenz-Limit statt alles gleichzeitig - schont sowohl euer
      // Kontingent-Tempo als auch CARTOs Server vor einem Lastspitzen-Burst.
      const concurrency = 6;
      for (var i = 0; i < urls.length; i += concurrency) {
        final batch = urls.skip(i).take(concurrency);
        await Future.wait(batch.map((url) async {
          try {
            await dio.get(url, options: Options(responseType: ResponseType.bytes));
          } catch (_) {
            // Einzelne fehlgeschlagene Kachel nicht fatal - beim nächsten
            // normalen Kartenaufruf wird sie ganz normal nachgeladen.
          }
          done++;
        }));
        _progressController.add(TileDownloadProgress(done, urls.length));
      }

      await SettingsService().setLastTileSyncAt(DateTime.now());
    } finally {
      _running = false;
    }
  }

  int _lngToTileX(double lng, int z) => ((lng + 180) / 360 * (1 << z)).floor();

  int _latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180;
    return ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * (1 << z))
        .floor();
  }

  void dispose() => _progressController.close();
}