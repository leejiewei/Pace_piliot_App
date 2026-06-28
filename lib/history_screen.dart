import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'database.dart';
import 'models.dart';

// FUNCTION 4 - History. Lists past runs from the local database. Tap one to see
// its pace and heart-rate charts plus the weather it was run in.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<List<RunSession>>(
        future: AppDatabase.instance.allSessions(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const Center(child: Text('No runs yet.'));
          }
          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, i) {
              final s = sessions[i];
              final date = DateFormat.yMMMEd().add_jm().format(s.startedAt);
              final km = (s.distanceMeters / 1000).toStringAsFixed(2);
              final mins = s.duration.inMinutes;
              final secs = s.duration.inSeconds % 60;
              return ListTile(
                leading: const Icon(Icons.directions_run),
                title: Text('$km km  -  ${s.courseName}'),
                subtitle: Text(date),
                trailing: Text('$mins:${secs.toString().padLeft(2, '0')}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RunDetailScreen(session: s),
                )),
              );
            },
          );
        },
      ),
    );
  }
}

// The charts for one run.
class RunDetailScreen extends StatelessWidget {
  const RunDetailScreen({super.key, required this.session});
  final RunSession session;

  Future<Map<String, Object?>> _load() async {
    final db = AppDatabase.instance;
    final points = await db.telemetryForSession(session.id!);
    final weather = await db.latestWeatherForSession(session.id!);
    return {'points': points, 'weather': weather};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run detail')),
      body: FutureBuilder<Map<String, Object?>>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = snapshot.data!['points'] as List<TelemetryPoint>;
          final weather = snapshot.data!['weather'] as WeatherData?;
          if (points.isEmpty) {
            return const Center(child: Text('No readings for this run.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (weather != null) _weatherCard(weather),
              const SizedBox(height: 16),
              const Text('Pace (min/km)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 200, child: _paceChart(points)),
              const SizedBox(height: 24),
              const Text('Heart rate (bpm)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 200, child: _heartRateChart(points)),
            ],
          );
        },
      ),
    );
  }

  Widget _weatherCard(WeatherData w) {
    Widget stat(String value, String label) => Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            stat('${w.temperatureC.toStringAsFixed(0)}C', 'Temp'),
            stat('${w.humidityPct.toStringAsFixed(0)}%', 'Humidity'),
            stat('${w.windSpeedMps.toStringAsFixed(1)} m/s', 'Wind'),
            stat('${w.precipitationMm.toStringAsFixed(1)} mm', 'Rain'),
          ],
        ),
      ),
    );
  }

  Widget _paceChart(List<TelemetryPoint> points) {
    final start = points.first.timestamp;
    final spots = <FlSpot>[];
    for (final p in points) {
      final pace = p.paceSecondsPerKm;
      if (pace.isInfinite || pace > 900) continue;
      final minutes = p.timestamp.difference(start).inSeconds / 60.0;
      spots.add(FlSpot(minutes, pace / 60.0));
    }
    return _lineChart(spots, Colors.blue);
  }

  Widget _heartRateChart(List<TelemetryPoint> points) {
    final start = points.first.timestamp;
    final spots = <FlSpot>[];
    for (final p in points) {
      if (p.heartRateBpm == null) continue;
      final minutes = p.timestamp.difference(start).inSeconds / 60.0;
      spots.add(FlSpot(minutes, p.heartRateBpm!.toDouble()));
    }
    return _lineChart(spots, Colors.red);
  }

  Widget _lineChart(List<FlSpot> spots, Color color) {
    if (spots.isEmpty) return const Center(child: Text('No data'));
    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}
