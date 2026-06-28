import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

// The optional cloud features (functions 5, 6, 7). The app works fine WITHOUT a
// backend - everything still saves to the local database. Set [backendBaseUrl]
// to your deployed backend if you want these to do something.
const String backendBaseUrl = 'https://YOUR-PROJECT.cloudfunctions.net';

// FUNCTION 6 - Cloud backup. Sends runs and readings to the cloud so nothing is
// lost if the phone dies. Best-effort: errors are ignored.
class CloudBackup {
  Future<void> uploadSession(RunSession session) =>
      _post('/sync/session', session.toMap());

  Future<void> uploadReading(TelemetryPoint point) =>
      _post('/sync/telemetry', point.toMap());

  Future<void> _post(String path, Map<String, Object?> body) async {
    try {
      await http.post(
        Uri.parse('$backendBaseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      // No internet / no backend: ignore. Local database still has the data.
    }
  }
}

// FUNCTION 5 - Computational offloading. Heavy work (like analysing a whole
// run) can be done on the cloud to save phone battery.
class CloudAnalysis {
  Future<Map<String, Object?>?> analyzeSession(int sessionId) async {
    try {
      final res = await http.post(
        Uri.parse('$backendBaseUrl/telemetry/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId}),
      );
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }
}

// FUNCTION 7 - Elastic scalability. The cloud adds more servers automatically
// when many runners use the app at once (e.g. race morning). From the app we
// can warn the backend a race is coming and check if it's healthy.
class CloudScaling {
  Future<void> announceRace(DateTime startTime, int expectedRunners) async {
    try {
      await http.post(
        Uri.parse('$backendBaseUrl/scaling/prewarm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'startTime': startTime.toIso8601String(),
          'expectedRunners': expectedRunners,
        }),
      );
    } catch (_) {}
  }

  Future<bool> isHealthy() async {
    try {
      final res = await http.post(Uri.parse('$backendBaseUrl/scaling/health'));
      if (res.statusCode != 200) return false;
      final json = jsonDecode(res.body) as Map<String, Object?>;
      return json['healthy'] == true;
    } catch (_) {
      return false;
    }
  }
}
