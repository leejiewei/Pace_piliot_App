import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Everything about the local database in one place: opening it, creating the
/// tables, and simple methods to save and load runs, readings and weather.
///
/// Use the shared instance:  AppDatabase.instance
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final folder = await getDatabasesPath();
    final path = p.join(folder, 'marathon_app.db');
    _db = await openDatabase(path, version: 3, onUpgrade: _upgrade,
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE run_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          distance_meters REAL NOT NULL,
          goal_pace_sec_per_km REAL NOT NULL,
          course_name TEXT NOT NULL DEFAULT 'Beginner',
          target_distance_meters REAL NOT NULL DEFAULT 10000
        )
      ''');
      await db.execute('''
        CREATE TABLE telemetry_points (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          speed_mps REAL NOT NULL,
          heart_rate_bpm INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE weather_samples (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER,
          timestamp INTEGER NOT NULL,
          temperature_c REAL NOT NULL,
          humidity_pct REAL NOT NULL,
          wind_speed_mps REAL NOT NULL,
          precipitation_mm REAL NOT NULL DEFAULT 0
        )
      ''');
    });
    return _db!;
  }

  // Runs when an older database (version 1) is opened: add the new columns
  // for the course feature so old data still works.
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE run_sessions ADD COLUMN course_name TEXT NOT NULL DEFAULT 'Beginner'");
      await db.execute(
          'ALTER TABLE run_sessions ADD COLUMN target_distance_meters REAL NOT NULL DEFAULT 10000');
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE weather_samples ADD COLUMN precipitation_mm REAL NOT NULL DEFAULT 0');
    }
  }

  // --- runs ---
  Future<int> insertSession(RunSession session) async {
    final db = await _open();
    final values = session.toMap()..remove('id');
    return db.insert('run_sessions', values);
  }

  Future<void> updateSession(RunSession session) async {
    final db = await _open();
    await db.update('run_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<List<RunSession>> allSessions() async {
    final db = await _open();
    final rows = await db.query('run_sessions', orderBy: 'started_at DESC');
    return rows.map(RunSession.fromMap).toList();
  }

  // --- readings ---
  Future<void> insertTelemetry(TelemetryPoint point) async {
    final db = await _open();
    final values = point.toMap()..remove('id');
    await db.insert('telemetry_points', values);
  }

  Future<List<TelemetryPoint>> telemetryForSession(int sessionId) async {
    final db = await _open();
    final rows = await db.query('telemetry_points',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'timestamp ASC');
    return rows.map(TelemetryPoint.fromMap).toList();
  }

  // --- weather ---
  Future<void> insertWeather(WeatherData sample) async {
    final db = await _open();
    final values = sample.toMap()..remove('id');
    await db.insert('weather_samples', values);
  }

  Future<WeatherData?> latestWeatherForSession(int sessionId) async {
    final db = await _open();
    final rows = await db.query('weather_samples',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return WeatherData.fromMap(rows.first);
  }
}
