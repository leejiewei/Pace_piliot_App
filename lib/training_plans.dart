// Training plans. A plan is a list of daily workouts spread over weeks, like a
// real marathon plan. Each workout has a type (recovery, tempo, long, ...) and
// a target time in minutes. Rest days are simply not listed.

enum RunType { recovery, easy, tempo, speed, long }

extension RunTypeInfo on RunType {
  // Friendly name shown in the app.
  String get label {
    switch (this) {
      case RunType.recovery:
        return 'Recovery run';
      case RunType.easy:
        return 'Easy run';
      case RunType.tempo:
        return 'Tempo run';
      case RunType.speed:
        return 'Speed run';
      case RunType.long:
        return 'Long run';
    }
  }

  // How much to change the goal pace for this kind of run (seconds per km).
  // Positive = slower/easier, negative = faster/harder. This is what makes a
  // recovery run aim slower and a speed run aim faster.
  double get paceOffsetSecPerKm {
    switch (this) {
      case RunType.recovery:
        return 60; // much easier
      case RunType.easy:
        return 30;
      case RunType.long:
        return 20; // steady
      case RunType.tempo:
        return -15; // comfortably hard
      case RunType.speed:
        return -35; // fast
    }
  }
}

// One day's workout.
class Workout {
  final int week;
  final int day; // 1..7
  final RunType type;
  final int minutes; // target time

  const Workout(this.week, this.day, this.type, this.minutes);

  // A short label saved with the run, e.g. "Tempo run 20min (W1D4)".
  String get label => '${type.label} ${minutes}min (W${week}D$day)';
}

// A whole plan: a name, a goal distance, and the list of workouts.
class TrainingPlan {
  final String name; // Beginner / Intermediate / Hard
  final String goal; // "10 km"
  final List<Workout> workouts;

  const TrainingPlan(this.name, this.goal, this.workouts);

  int get weeks =>
      workouts.isEmpty ? 0 : workouts.map((w) => w.week).reduce((a, b) => a > b ? a : b);
}

// The three plans the user can pick. Edit the numbers to change the training!
const List<TrainingPlan> kPlans = [
  TrainingPlan('Beginner', '10 km', [
    // Week 1
    Workout(1, 1, RunType.recovery, 15),
    Workout(1, 2, RunType.recovery, 16),
    Workout(1, 4, RunType.tempo, 20),
    Workout(1, 5, RunType.recovery, 20),
    Workout(1, 7, RunType.long, 30),
    // Week 2
    Workout(2, 1, RunType.recovery, 18),
    Workout(2, 2, RunType.recovery, 18),
    Workout(2, 4, RunType.tempo, 24),
    Workout(2, 5, RunType.recovery, 22),
    Workout(2, 7, RunType.long, 40),
    // Week 3
    Workout(3, 1, RunType.recovery, 20),
    Workout(3, 2, RunType.recovery, 20),
    Workout(3, 4, RunType.speed, 25),
    Workout(3, 5, RunType.recovery, 24),
    Workout(3, 7, RunType.long, 50),
  ]),
  TrainingPlan('Intermediate', '21 km', [
    // Week 1
    Workout(1, 1, RunType.recovery, 20),
    Workout(1, 2, RunType.easy, 25),
    Workout(1, 4, RunType.tempo, 30),
    Workout(1, 5, RunType.recovery, 25),
    Workout(1, 7, RunType.long, 60),
    // Week 2
    Workout(2, 1, RunType.recovery, 22),
    Workout(2, 2, RunType.easy, 28),
    Workout(2, 4, RunType.speed, 30),
    Workout(2, 5, RunType.recovery, 28),
    Workout(2, 7, RunType.long, 75),
    // Week 3
    Workout(3, 1, RunType.recovery, 25),
    Workout(3, 2, RunType.easy, 30),
    Workout(3, 4, RunType.tempo, 35),
    Workout(3, 5, RunType.recovery, 30),
    Workout(3, 7, RunType.long, 90),
  ]),
  TrainingPlan('Hard', '42 km', [
    // Week 1
    Workout(1, 1, RunType.easy, 30),
    Workout(1, 2, RunType.easy, 35),
    Workout(1, 4, RunType.tempo, 40),
    Workout(1, 5, RunType.recovery, 30),
    Workout(1, 7, RunType.long, 90),
    // Week 2
    Workout(2, 1, RunType.easy, 35),
    Workout(2, 2, RunType.easy, 40),
    Workout(2, 4, RunType.speed, 40),
    Workout(2, 5, RunType.recovery, 35),
    Workout(2, 7, RunType.long, 120),
    // Week 3
    Workout(3, 1, RunType.easy, 40),
    Workout(3, 2, RunType.easy, 45),
    Workout(3, 4, RunType.tempo, 45),
    Workout(3, 5, RunType.recovery, 40),
    Workout(3, 7, RunType.long, 150),
  ]),
];
