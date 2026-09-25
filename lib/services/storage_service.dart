import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/explored_cell.dart';

/// Kapselt die gesamte lokale Persistenz. Offline-first: keinerlei Server-
/// Abhängigkeit. Schema ist so gehalten, dass eine spätere Cloud-Sync über
/// ein `synced`-Flag pro Zeile ergänzt werden kann, ohne Kernstruktur zu
/// ändern.
class StorageService {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

Future<Database> _initDb() async {
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, 'fog_of_war.db');

  return openDatabase(
    path,
    version: 4,
    onCreate: (db, version) async {
      await _createV1Tables(db);
      await _createV2Tables(db);
      await _createV3Indexes(db);
      await _createV4PlaceColumn(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await _createV2Tables(db);
      if (oldVersion < 3) await _createV3Indexes(db);
      if (oldVersion < 4) await _createV4PlaceColumn(db);
    },
  );
}

/// Neue Spalte für die gecachte Orts-Zugehörigkeit jeder Zelle, plus Index
/// für schnelle "wie viele Zellen in Ort X"-Abfragen (Achievement-Check).
Future<void> _createV4PlaceColumn(Database db) async {
  // ALTER TABLE ADD COLUMN schlägt fehl, falls die Spalte schon existiert -
  // bei Migrationen von oldVersion < 4 ist das nicht der Fall, bei
  // onCreate (Neuinstallation) landen wir aber über _createV1Tables schon
  // ohne die Spalte, daher hier ergänzen.
  final columns = await db.rawQuery('PRAGMA table_info(explored_cells)');
  final hasPlaceId = columns.any((c) => c['name'] == 'place_id');
  if (!hasPlaceId) {
    await db.execute('ALTER TABLE explored_cells ADD COLUMN place_id TEXT');
  }
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_explored_cells_place
    ON explored_cells (place_id)
  ''');
}

  Future<void> _createV1Tables(Database db) async {
    await db.execute('''
      CREATE TABLE explored_cells (
        geohash TEXT PRIMARY KEY,
        center_lat REAL NOT NULL,
        center_lng REAL NOT NULL,
        first_visited INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Tabellen für Statistik (Erkundungstage) und Achievements.
  Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exploration_days (
        day TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements (
        id TEXT PRIMARY KEY,
        unlocked_at INTEGER NOT NULL
      )
    ''');
  }

  /// Index auf die Bounds-Query-Spalten - ohne diesen degradiert
  /// getCellsInBounds() bei wachsender Zellenzahl zum Full-Table-Scan.
  Future<void> _createV3Indexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_explored_cells_bounds
      ON explored_cells (center_lat, center_lng)
    ''');
  }

  // ---------- Erkundete Zellen ----------

  Future<bool> addExploredCell(ExploredCell cell) async {
    final db = await database;
    final rows = await db.insert(
      'explored_cells',
      cell.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return rows != 0;
  }

  Future<List<ExploredCell>> getAllExploredCells() async {
    final db = await database;
    final rows = await db.query('explored_cells');
    return rows.map(ExploredCell.fromMap).toList();
  }

  /// Lädt nur Zellen innerhalb eines Bounding Box (für performantes
  /// viewport-basiertes Rendering bei großen erkundeten Gebieten).
  Future<List<ExploredCell>> getCellsInBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) async {
    final db = await database;
    final rows = await db.query(
      'explored_cells',
      where: 'center_lat BETWEEN ? AND ? AND center_lng BETWEEN ? AND ?',
      whereArgs: [minLat, maxLat, minLng, maxLng],
    );
    return rows.map(ExploredCell.fromMap).toList();
  }

  /// Zählt erkundete Zellen für einen Ort direkt über die gecachte place_id-
/// Spalte - dank Index praktisch O(log n), kein Bounding-Box-Query und kein
/// erneuter Punkt-in-Polygon-Test mehr nötig.
Future<int> getExploredCellCountForPlace(String placeId) async {
  final db = await database;
  final result = await db.rawQuery(
    'SELECT COUNT(*) as c FROM explored_cells WHERE place_id = ?',
    [placeId],
  );
  return Sqflite.firstIntValue(result) ?? 0;
}

  Future<int> getExploredCellCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM explored_cells');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------- Position / App-State ----------

  Future<void> saveLastPosition(double lat, double lng) async {
    final db = await database;
    await db.insert(
      'app_state',
      {'key': 'last_position', 'value': '$lat,$lng'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<(double, double)?> getLastPosition() async {
    final db = await database;
    final rows = await db
        .query('app_state', where: 'key = ?', whereArgs: ['last_position']);
    if (rows.isEmpty) return null;
    final parts = (rows.first['value'] as String).split(',');
    return (double.parse(parts[0]), double.parse(parts[1]));
  }

  // ---------- Distanz-Tracking ----------

  Future<void> addDistanceMeters(double meters) async {
    final current = await getTotalDistanceMeters();
    final db = await database;
    await db.insert(
      'app_state',
      {'key': 'total_distance_m', 'value': '${current + meters}'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getTotalDistanceMeters() async {
    final db = await database;
    final rows = await db
        .query('app_state', where: 'key = ?', whereArgs: ['total_distance_m']);
    if (rows.isEmpty) return 0;
    return double.parse(rows.first['value'] as String);
  }

  // ---------- Erkundungstage (für Streaks) ----------

  /// Merkt sich, dass an diesem Kalendertag (lokale Zeit) etwas erkundet
  /// wurde. `INSERT OR IGNORE` macht Mehrfach-Aufrufe am selben Tag billig.
  Future<void> recordExplorationDay(DateTime date) async {
    final db = await database;
    await db.insert(
      'exploration_days',
      {'day': _dayKey(date)},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> getExplorationDayCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM exploration_days');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Alle Erkundungstage aufsteigend sortiert, für Streak-Berechnung.
  Future<List<DateTime>> getExplorationDaysSorted() async {
    final db = await database;
    final rows = await db.query('exploration_days', orderBy: 'day ASC');
    return rows.map((r) => DateTime.parse(r['day'] as String)).toList();
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- Achievements ----------

  /// Gibt true zurück, wenn das Achievement neu freigeschaltet wurde (also
  /// vorher noch nicht in der Tabelle stand).
  Future<bool> unlockAchievement(String id) async {
    final db = await database;
    final rows = await db.insert(
      'achievements',
      {'id': id, 'unlocked_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return rows != 0;
  }

  Future<Set<String>> getUnlockedAchievementIds() async {
    final db = await database;
    final rows = await db.query('achievements');
    return rows.map((r) => r['id'] as String).toSet();
  }

  // ---------- Generische Einstellungen ----------

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_state',
      {'key': 'setting_$key', 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db
        .query('app_state', where: 'key = ?', whereArgs: ['setting_$key']);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  // ---------- Datenschutz ----------

  /// Löscht ALLE lokal gespeicherten Daten - für den Datenschutz-Screen.
  /// Absichtlich NICHT enthalten: der Onboarding-Flag (setting_onboarding_
  /// completed) liegt technisch auch in app_state und würde daher ebenfalls
  /// gelöscht - das ist beabsichtigt, damit nach einem Reset auch das
  /// Onboarding erneut durchlaufen wird.
  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete('explored_cells');
    await db.delete('app_state');
    await db.delete('exploration_days');
    await db.delete('achievements');
  }
}
