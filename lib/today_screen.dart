import 'package:flutter/material.dart';

import 'gps_tracker.dart';
import 'history_screen.dart';
import 'models.dart';
import 'pacing.dart';
import 'run_screen.dart';
import 'training_plans.dart';
import 'weather.dart';

// The home page (like Nike Run Club). It checks today's weather and shows the
// recommended pace, lets you pick a training plan, and shows that plan's daily
// workouts. Tap a workout to start it.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final gps = GpsTracker();
  final weather = WeatherService();

  WeatherData? todayWeather;
  bool loading = true;
  String? error;
  double goalPaceSecPerKm = 330; // 5'30" per km (your base pace)
  TrainingPlan selectedPlan = kPlans[0]; // Beginner by default

  @override
  void initState() {
    super.initState();
    loadTodayWeather();
  }

  Future<void> loadTodayWeather() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!await gps.ensurePermission()) {
        setState(() {
          loading = false;
          error = 'Location permission is needed to check the weather.';
        });
        return;
      }
      final spot = await gps.currentLocation();
      final w = await weather.fetch(spot.latitude, spot.longitude);
      setState(() {
        todayWeather = w;
        loading = false;
      });
    } catch (_) {
      setState(() {
        loading = false;
        error = 'Could not load the weather. Check your internet.';
      });
    }
  }

  // Start the tapped workout.
  void startWorkout(Workout workout) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RunScreen(
        workout: workout,
        baseGoalPaceSecPerKm: goalPaceSecPerKm,
      ),
    ));
  }

  void openHistory() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final plan = planForToday(goalPaceSecPerKm, todayWeather);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Run"),
        actions: [
          IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'History',
              onPressed: openHistory),
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh weather',
              onPressed: loadTodayWeather),
        ],
      ),
      // ListView so the whole page can scroll (weather + plan + workouts).
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (error != null) _errorCard(error!),
            if (todayWeather != null) _weatherCard(todayWeather!),
            const SizedBox(height: 12),
            _todaysPaceCard(plan),
          ],
          const SizedBox(height: 16),
          _goalPicker(),
          const SizedBox(height: 16),
          const Text('Choose your plan',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _planPicker(),
          const SizedBox(height: 16),
          Text('${selectedPlan.name} plan - goal ${selectedPlan.goal}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Tap a workout to start it.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          ..._workoutList(),
        ],
      ),
    );
  }

  // Beginner / Intermediate / Hard selector.
  Widget _planPicker() {
    return Row(
      children: kPlans.map((p) {
        final selected = p == selectedPlan;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedPlan = p),
            child: Card(
              color: selected ? Colors.teal : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Column(
                  children: [
                    Text(p.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : null)),
                    const SizedBox(height: 4),
                    Text(p.goal,
                        style: TextStyle(
                            color: selected ? Colors.white : Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // The list of workouts, with a small header before each new week.
  List<Widget> _workoutList() {
    final widgets = <Widget>[];
    var lastWeek = 0;
    for (final w in selectedPlan.workouts) {
      if (w.week != lastWeek) {
        lastWeek = w.week;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('Week ${w.week}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.teal)),
        ));
      }
      widgets.add(Card(
        child: ListTile(
          leading: Icon(_iconFor(w.type)),
          title: Text('${w.type.label} - ${w.minutes} min'),
          subtitle: Text('Day ${w.day}'),
          trailing: const Icon(Icons.play_circle_fill, color: Colors.teal),
          onTap: () => startWorkout(w),
        ),
      ));
    }
    return widgets;
  }

  IconData _iconFor(RunType type) {
    switch (type) {
      case RunType.recovery:
        return Icons.self_improvement;
      case RunType.easy:
        return Icons.directions_walk;
      case RunType.tempo:
        return Icons.speed;
      case RunType.speed:
        return Icons.bolt;
      case RunType.long:
        return Icons.timeline;
    }
  }

  Widget _errorCard(String text) => Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text(text),
        ),
      );

  Widget _weatherCard(WeatherData w) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('${w.temperatureC.toStringAsFixed(0)}C', 'Temp'),
              _stat('${w.humidityPct.toStringAsFixed(0)}%', 'Humidity'),
              _stat('${w.windSpeedMps.toStringAsFixed(1)} m/s', 'Wind'),
              _stat('${w.precipitationMm.toStringAsFixed(1)} mm', 'Rain'),
            ],
          ),
        ),
      );

  Widget _todaysPaceCard(TodayPlan plan) => Card(
        color: Colors.teal.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text("Today's recommended pace"),
              const SizedBox(height: 8),
              Text('${PacingDecision.formatPace(plan.recommendedPaceSecPerKm)} /km',
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(plan.message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label),
        ],
      );

  Widget _goalPicker() => Row(
        children: [
          const Text('Base pace  '),
          Text(PacingDecision.formatPace(goalPaceSecPerKm)),
          Expanded(
            child: Slider(
              min: 240,
              max: 480,
              divisions: 24,
              value: goalPaceSecPerKm,
              onChanged: (v) => setState(() => goalPaceSecPerKm = v),
            ),
          ),
        ],
      );
}
