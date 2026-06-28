import 'models.dart';

// FUNCTION 3 - The pacing brain of the app.
// It looks at the weather (and your heart rate while running) and decides what
// pace you should aim for. This is the most important file to understand.
//
// >>> The numbers below are the easiest things to change. <<<

// ---- Tunable settings (edit these) ------------------------------------------
const double kComfortIndex = 16.0; // below this "feels-like" temp, no slowdown
const double kSecondsPerHeatDegree = 4.0; // extra s/km per degree of heat
const double kSecondsPerWind = 1.5; // extra s/km per m/s of wind
const double kSecondsPerRainMm = 3.0; // extra s/km per mm of rain (wet/slippery)
const double kMaxRainSlowdown = 25.0; // cap on the rain slowdown (s/km)
const double kMaxWeatherSlowdown = 90.0; // most the weather can slow you (s/km)
const double kSafeHeartRateFraction = 0.88; // safe HR = this much of your max

// Rain amounts (mm) used to choose the advice message.
const double kRainLightMm = 0.1;
const double kRainModerateMm = 2.5;
const double kRainHeavyMm = 7.6;
// -----------------------------------------------------------------------------

/// How many seconds per km the weather should slow you down today.
/// Hotter + more humid + windier = bigger number. This is the core idea: the
/// app's pace depends on the weather.
double weatherSlowdown(WeatherData? weather) {
  if (weather == null) return 0;
  final heat = weather.heatStressIndex - kComfortIndex;
  final heatSlow = (heat < 0 ? 0 : heat) * kSecondsPerHeatDegree;
  final windSlow = weather.windSpeedMps * kSecondsPerWind;
  // Rain makes the ground slippery, so we ease the target for safety.
  var rainSlow = weather.precipitationMm * kSecondsPerRainMm;
  if (rainSlow > kMaxRainSlowdown) rainSlow = kMaxRainSlowdown;
  var total = heatSlow + windSlow + rainSlow;
  if (total > kMaxWeatherSlowdown) total = kMaxWeatherSlowdown;
  return total;
}

/// What pace to aim for TODAY, before the run starts (the Nike-style advice on
/// the Today screen). Combines your goal pace with the weather slowdown and a
/// friendly coaching message.
TodayPlan planForToday(double goalPaceSecPerKm, WeatherData? weather) {
  if (weather == null) {
    return TodayPlan(
      recommendedPaceSecPerKm: goalPaceSecPerKm,
      slowdownSecPerKm: 0,
      message: "Couldn't load the weather. Run your goal pace and adjust by feel.",
    );
  }
  final slowdown = weatherSlowdown(weather);
  final recommended = goalPaceSecPerKm + slowdown;
  final mm = weather.precipitationMm;

  String message;
  if (mm >= kRainHeavyMm) {
    message = 'Heavy rain. Consider a treadmill or rescheduling. If you go out, '
        'slow ~${slowdown.round()}s/km, stay visible and avoid puddled roads.';
  } else if (mm >= kRainModerateMm) {
    message = 'Rainy out. Ease off ~${slowdown.round()}s/km and watch your '
        'footing - the ground is slippery.';
  } else if (mm >= kRainLightMm) {
    message = slowdown > 0
        ? 'Light rain. Wear a cap, stay visible, and add ~${slowdown.round()}s/km.'
        : 'Light rain. Wear a cap and stay visible.';
  } else if (slowdown <= 0) {
    message = 'Great conditions today - you can run your goal pace!';
  } else if (slowdown < 20) {
    message = 'Mild conditions. Add about ${slowdown.round()}s/km.';
  } else if (slowdown < 45) {
    message = 'Warm or breezy today. Ease off about ${slowdown.round()}s/km.';
  } else {
    message = 'Hot and humid! Slow down about ${slowdown.round()}s/km, '
        'hydrate, and listen to your body.';
  }
  return TodayPlan(
    recommendedPaceSecPerKm: recommended,
    slowdownSecPerKm: slowdown,
    message: message,
  );
}

/// The advice shown on the Today screen.
class TodayPlan {
  final double recommendedPaceSecPerKm;
  final double slowdownSecPerKm;
  final String message;
  TodayPlan({
    required this.recommendedPaceSecPerKm,
    required this.slowdownSecPerKm,
    required this.message,
  });
}

/// What the engine decides at one moment during a run.
enum PacingAction { hold, slowDown, speedUp }

class PacingDecision {
  final PacingAction action;
  final double targetPaceSecPerKm;
  final String reason;
  final bool isSafetyAlert;

  PacingDecision({
    required this.action,
    required this.targetPaceSecPerKm,
    required this.reason,
    required this.isSafetyAlert,
  });

  String get targetLabel => formatPace(targetPaceSecPerKm);

  /// Turn seconds-per-km into a label like 5'30".
  static String formatPace(double secPerKm) {
    if (secPerKm.isInfinite || secPerKm.isNaN) return "--'--\"";
    final total = secPerKm.round();
    return "${total ~/ 60}'${(total % 60).toString().padLeft(2, '0')}\"";
  }
}

/// Adjusts the target pace live during a run, using weather + heart rate.
class PacingEngine {
  PacingEngine({required this.goalPaceSecPerKm, this.maxHeartRate = 190}) {
    currentTargetSecPerKm = goalPaceSecPerKm;
  }

  final double goalPaceSecPerKm;
  final int maxHeartRate;
  late double currentTargetSecPerKm;

  int get safeHeartRateCeiling =>
      (maxHeartRate * kSafeHeartRateFraction).round();

  /// Decide the new target pace for this reading.
  PacingDecision evaluate(TelemetryPoint point, WeatherData? weather) {
    final heartRate = point.heartRateBpm;

    // Step 1: the weather sets the baseline target.
    final slowdown = weatherSlowdown(weather);
    final weatherTarget = goalPaceSecPerKm + slowdown;

    // In hot weather, lower the safe heart-rate ceiling a little.
    var ceiling = safeHeartRateCeiling;
    if (weather != null && weather.heatStressIndex > 25) {
      final drop = (weather.heatStressIndex - 25).round();
      ceiling -= drop > 20 ? 20 : drop;
    }

    final note = weather == null
        ? ''
        : ' (${weather.temperatureC.toStringAsFixed(0)}C, '
            '${weather.humidityPct.toStringAsFixed(0)}% humidity'
            '${weather.isRaining ? ', rain' : ''}, '
            'adds ${slowdown.round()}s/km)';

    // Step 2a: heart rate too high -> slow down more and warn.
    if (heartRate != null && heartRate > ceiling) {
      var target = currentTargetSecPerKm + 20;
      if (target < weatherTarget) target = weatherTarget;
      if (target > goalPaceSecPerKm + 150) target = goalPaceSecPerKm + 150;
      currentTargetSecPerKm = target;
      return PacingDecision(
        action: PacingAction.slowDown,
        targetPaceSecPerKm: target,
        reason: 'Heart rate $heartRate over safe ceiling $ceiling$note',
        isSafetyAlert: true,
      );
    }

    // Step 2b: heart rate has room and we're slower than needed -> ease back.
    if (heartRate != null &&
        heartRate < ceiling - 15 &&
        currentTargetSecPerKm > weatherTarget) {
      var target = currentTargetSecPerKm - 10;
      if (target < weatherTarget) target = weatherTarget;
      currentTargetSecPerKm = target;
      return PacingDecision(
        action: PacingAction.speedUp,
        targetPaceSecPerKm: target,
        reason: 'Heart rate $heartRate has room - easing toward target',
        isSafetyAlert: false,
      );
    }

    // Step 3: otherwise just follow the weather target.
    final gotSlower = weatherTarget > currentTargetSecPerKm + 0.5;
    currentTargetSecPerKm = weatherTarget;
    return PacingDecision(
      action: gotSlower ? PacingAction.slowDown : PacingAction.hold,
      targetPaceSecPerKm: weatherTarget,
      reason: slowdown > 0
          ? 'Weather-adjusted target$note'
          : 'Good conditions - holding goal pace',
      isSafetyAlert: slowdown >= 30 && gotSlower,
    );
  }
}
