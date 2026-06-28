import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cloud.dart';
import 'database.dart';
import 'gps_tracker.dart';
import 'heart_rate.dart';
import 'models.dart';
import 'music_player.dart';
import 'pacing.dart';
import 'training_plans.dart';
import 'weather.dart';

// The live run page. It runs ONE workout from the plan (a run type + target
// minutes). It combines GPS pace + heart rate, saves and backs up the data,
// adjusts the target pace for the weather AND the run type, tracks the time
// toward the workout target, and plays your music.
class RunScreen extends StatefulWidget {
  const RunScreen({
    super.key,
    required this.workout,
    required this.baseGoalPaceSecPerKm,
  });

  final Workout workout;
  final double baseGoalPaceSecPerKm;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  final gps = GpsTracker();
  final heartRate = HeartRateMonitor();
  final weather = WeatherService();
  final cloud = CloudBackup();
  final db = AppDatabase.instance;
  final music = MusicPlayer();
  late final PacingEngine engine;

  RunSession? session;
  Timer? weatherTimer;
  Timer? clockTimer; // updates the elapsed time every second
  Position? _lastPosition;

  TelemetryPoint? latestPoint;
  WeatherData? latestWeather;
  PacingDecision? latestDecision;
  double distanceMeters = 0;
  double? gpsAccuracyMeters; // horizontal accuracy of the latest GPS fix

  bool get isRunning => session != null && session!.isActive;

  // How long the workout target is, in seconds.
  int get targetSeconds => widget.workout.minutes * 60;

  // How long we've been running.
  Duration get elapsed =>
      session == null ? Duration.zero : DateTime.now().difference(session!.startedAt);

  @override
  void initState() {
    super.initState();
    // The run type changes the goal pace: recovery slower, speed faster.
    final goalPace =
        widget.baseGoalPaceSecPerKm + widget.workout.type.paceOffsetSecPerKm;
    engine = PacingEngine(goalPaceSecPerKm: goalPace);
    heartRate.onHeartRate = (_) => setState(() {});
    music.onChanged = () => setState(() {});

    // Automatically connect the heart-rate watch and load all music when the
    // screen opens, so you don't have to set them up by hand.
    _autoConnectHeartRate();
    _autoLoadMusic();
  }

  // On open, look for a broadcasting watch and connect to the Garmin if we see
  // it. We do NOT just grab the first device, so it won't latch onto the ASUS
  // watch. If the Garmin isn't found, the user can pick from the heart icon.
  Future<void> _autoConnectHeartRate() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    final results = await heartRate.scan();
    if (results.isEmpty) return;

    // Prefer a Garmin / Forerunner by name.
    ScanResult? preferred;
    for (final r in results) {
      final name = HeartRateMonitor.nameOf(r).toLowerCase();
      if (name.contains('garmin') || name.contains('forerunner')) {
        preferred = r;
        break;
      }
    }
    if (preferred != null) {
      await heartRate.connect(preferred.device);
      if (mounted) {
        setState(() {});
        _msg('Heart rate: connected to ${heartRate.connectedName}.');
      }
    }
  }

  // Load every song on the phone automatically.
  Future<void> _autoLoadMusic() async {
    final count = await music.loadAllSongs();
    if (mounted) {
      setState(() {});
      if (count > 0) _msg('Loaded $count songs from your phone.');
    }
  }

  @override
  void dispose() {
    gps.stop();
    weatherTimer?.cancel();
    clockTimer?.cancel();
    heartRate.disconnect();
    music.dispose();
    super.dispose();
  }

  Future<void> startRun() async {
    if (!await gps.ensurePermission()) {
      _msg('Location permission is needed.');
      return;
    }
    final goalPace =
        widget.baseGoalPaceSecPerKm + widget.workout.type.paceOffsetSecPerKm;
    final newSession = RunSession(
      startedAt: DateTime.now(),
      goalPaceSecPerKm: goalPace,
      courseName: widget.workout.label, // e.g. "Tempo run 20min (W1D4)"
    );
    newSession.id = await db.insertSession(newSession);
    session = newSession;
    cloud.uploadSession(newSession);

    weatherTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => fetchWeather());
    // Tick every second so the elapsed time and progress bar update.
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    gps.start((position) async {
      gpsAccuracyMeters = position.accuracy;
      // Logged so GPS quality can be checked with: adb logcat -s flutter
      debugPrint('GPS fix: accuracy=${position.accuracy.toStringAsFixed(1)}m '
          'speed=${position.speed.toStringAsFixed(2)}m/s');
      final point = TelemetryPoint(
        sessionId: newSession.id!,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        speedMps: position.speed < 0 ? 0 : position.speed,
        heartRateBpm: heartRate.lastBpm,
      );
      _addDistance(position);
      latestPoint = point;
      await db.insertTelemetry(point);
      cloud.uploadReading(point);
      if (latestWeather == null) fetchWeather();
      latestDecision = engine.evaluate(point, latestWeather);
      setState(() {});
    });

    setState(() {});
  }

  void _addDistance(Position position) {
    if (_lastPosition != null) {
      distanceMeters += Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
    }
    _lastPosition = position;
  }

  Future<void> stopRun() async {
    gps.stop();
    weatherTimer?.cancel();
    clockTimer?.cancel();
    final finished = session!;
    finished.endedAt = DateTime.now();
    finished.distanceMeters = distanceMeters;
    await db.updateSession(finished);
    cloud.uploadSession(finished);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> fetchWeather() async {
    final point = latestPoint;
    if (point == null) return;
    try {
      final w = await weather.fetch(point.latitude, point.longitude);
      final sample = WeatherData(
        sessionId: session?.id,
        timestamp: w.timestamp,
        temperatureC: w.temperatureC,
        humidityPct: w.humidityPct,
        windSpeedMps: w.windSpeedMps,
        precipitationMm: w.precipitationMm,
      );
      latestWeather = sample;
      await db.insertWeather(sample);
      setState(() {});
    } catch (_) {}
  }

  // Reload all songs from the phone (e.g. after adding new music).
  Future<void> reloadMusic() async {
    final count = await music.loadAllSongs();
    if (mounted) _msg('Loaded $count songs.');
    setState(() {});
  }

  // Scan and let the user pick which watch to use (so they can choose the
  // Garmin instead of the ASUS).
  Future<void> chooseHeartRateDevice() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    _msg('Scanning for broadcasting watches...');
    final results = await heartRate.scan();
    if (!mounted) return;
    if (results.isEmpty) {
      _msg('None found. On your Forerunner 55 turn on Broadcast Heart Rate.');
      return;
    }

    final chosen = await showDialog<BluetoothDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose your watch'),
        children: results
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r.device),
                  child: Row(
                    children: [
                      const Icon(Icons.watch),
                      const SizedBox(width: 10),
                      Expanded(child: Text(HeartRateMonitor.nameOf(r))),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (chosen == null) return;
    final ok = await heartRate.connect(chosen);
    if (mounted) {
      setState(() {});
      _msg(ok
          ? 'Connected to ${heartRate.connectedName}.'
          : 'Could not read heart rate from that device.');
    }
  }

  void _msg(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workout;
    final decision = latestDecision;

    return Scaffold(
      appBar: AppBar(
        title: Text('${w.type.label} - ${w.minutes} min'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'Choose heart-rate watch (Garmin)',
            onPressed: chooseHeartRateDevice,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Week ${w.week} · Day ${w.day}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            _gpsStatus(),
            const SizedBox(height: 8),
            if (decision != null && decision.isSafetyAlert)
              _alertBanner(decision),
            _timeCard(),
            _card(
                'Current pace',
                latestPoint == null
                    ? "--'--\""
                    : PacingDecision.formatPace(latestPoint!.paceSecondsPerKm),
                '/km'),
            _card(
                'Target pace',
                decision?.targetLabel ??
                    PacingDecision.formatPace(engine.goalPaceSecPerKm),
                '/km',
                highlight: decision?.action == PacingAction.slowDown),
            _card('Heart rate', heartRate.lastBpm?.toString() ?? '--', 'bpm'),
            _card('Distance', (distanceMeters / 1000).toStringAsFixed(2), 'km'),
            const Spacer(),
            _musicCard(),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
              style: FilledButton.styleFrom(
                backgroundColor: isRunning ? Colors.red : null,
                minimumSize: const Size.fromHeight(56),
              ),
              label: Text(isRunning ? 'Stop run' : 'Start run'),
              onPressed: isRunning ? stopRun : startRun,
            ),
          ],
        ),
      ),
    );
  }

  // Live GPS signal quality, based on the fix accuracy in metres.
  Widget _gpsStatus() {
    final acc = gpsAccuracyMeters;
    String label;
    Color color;
    if (acc == null) {
      label = 'GPS: searching...';
      color = Colors.grey;
    } else if (acc <= 10) {
      label = 'GPS: strong (${acc.toStringAsFixed(0)} m)';
      color = Colors.green;
    } else if (acc <= 25) {
      label = 'GPS: ok (${acc.toStringAsFixed(0)} m)';
      color = Colors.orange;
    } else {
      label = 'GPS: weak (${acc.toStringAsFixed(0)} m)';
      color = Colors.red;
    }
    return Row(
      children: [
        Icon(Icons.gps_fixed, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // Elapsed time + progress toward the workout's target minutes.
  Widget _timeCard() {
    final elapsedSec = elapsed.inSeconds;
    var fraction = targetSeconds == 0 ? 0.0 : elapsedSec / targetSeconds;
    if (fraction > 1) fraction = 1;
    final done = elapsedSec >= targetSeconds && isRunning;
    return Card(
      color: done ? Colors.green.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Time'),
                Text('${_mmss(elapsedSec)} / ${widget.workout.minutes}:00',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: fraction, minHeight: 10),
            ),
            if (done)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Workout complete - great job!',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _musicCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.music_note),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(music.currentTitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    music.hasSongs
                        ? '${music.songCount} songs on your phone'
                        : 'Loading music...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: music.hasSongs ? music.previous : null),
            IconButton(
                icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: music.hasSongs ? music.togglePlay : null),
            IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: music.hasSongs ? music.next : null),
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload all songs',
                onPressed: reloadMusic),
          ],
        ),
      ),
    );
  }

  Widget _alertBanner(PacingDecision decision) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Slow to ${decision.targetLabel}/km - ${decision.reason}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _card(String label, String value, String unit,
      {bool highlight = false}) {
    return Card(
      color: highlight ? Colors.orange.shade50 : null,
      child: ListTile(
        title: Text(label),
        trailing: Text('$value $unit',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
