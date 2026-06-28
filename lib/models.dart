// All the simple data classes for the app, kept together in one file.

/// One run.
class RunSession {
  int? id;
  final DateTime startedAt;
  DateTime? endedAt;
  double distanceMeters;
  final double goalPaceSecPerKm;
  final String courseName; // "Beginner" / "Intermediate" / "Hard"
  final double targetDistanceMeters; // goal distance for the chosen course

  RunSession({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.distanceMeters = 0,
    required this.goalPaceSecPerKm,
    this.courseName = 'Beginner',
    this.targetDistanceMeters = 10000,
  });

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);
  bool get isActive => endedAt == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'distance_meters': distanceMeters,
        'goal_pace_sec_per_km': goalPaceSecPerKm,
        'course_name': courseName,
        'target_distance_meters': targetDistanceMeters,
      };

  factory RunSession.fromMap(Map<String, Object?> map) => RunSession(
        id: map['id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
        distanceMeters: map['distance_meters'] as double,
        goalPaceSecPerKm: map['goal_pace_sec_per_km'] as double,
        courseName: map['course_name'] as String? ?? 'Beginner',
        targetDistanceMeters:
            (map['target_distance_meters'] as num?)?.toDouble() ?? 10000,
      );
}

/// One reading during a run (location + speed + heart rate).
class TelemetryPoint {
  final int? id;
  final int sessionId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speedMps;
  final int? heartRateBpm;

  TelemetryPoint({
    this.id,
    required this.sessionId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    this.heartRateBpm,
  });

  /// Pace in seconds per km (infinity if basically standing still).
  double get paceSecondsPerKm =>
      speedMps <= 0.1 ? double.infinity : 1000.0 / speedMps;

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'speed_mps': speedMps,
        'heart_rate_bpm': heartRateBpm,
      };

  factory TelemetryPoint.fromMap(Map<String, Object?> map) => TelemetryPoint(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        latitude: map['latitude'] as double,
        longitude: map['longitude'] as double,
        speedMps: map['speed_mps'] as double,
        heartRateBpm: map['heart_rate_bpm'] as int?,
      );
}

/// Weather at one moment.
class WeatherData {
  final int? id;
  final int? sessionId;
  final DateTime timestamp;
  final double temperatureC;
  final double humidityPct;
  final double windSpeedMps;
  final double precipitationMm; // rain (mm); 0 means dry

  WeatherData({
    this.id,
    this.sessionId,
    required this.timestamp,
    required this.temperatureC,
    required this.humidityPct,
    required this.windSpeedMps,
    this.precipitationMm = 0,
  });

  // True if it is currently raining.
  bool get isRaining => precipitationMm > 0;

  /// A simple "how hot it feels" number mixing heat and humidity.
  double get heatStressIndex =>
      temperatureC + (humidityPct / 100.0) * 0.6 * temperatureC;

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'temperature_c': temperatureC,
        'humidity_pct': humidityPct,
        'wind_speed_mps': windSpeedMps,
        'precipitation_mm': precipitationMm,
      };

  factory WeatherData.fromMap(Map<String, Object?> map) => WeatherData(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        temperatureC: map['temperature_c'] as double,
        humidityPct: map['humidity_pct'] as double,
        windSpeedMps: map['wind_speed_mps'] as double,
        precipitationMm: (map['precipitation_mm'] as num?)?.toDouble() ?? 0,
      );

  factory WeatherData.fromOpenMeteo(Map<String, Object?> json) {
    final current = json['current'] as Map<String, Object?>;
    return WeatherData(
      timestamp: DateTime.now(),
      temperatureC: (current['temperature_2m'] as num).toDouble(),
      humidityPct: (current['relative_humidity_2m'] as num).toDouble(),
      windSpeedMps: (current['wind_speed_10m'] as num).toDouble(),
      precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
    );
  }
}
