# Marathon App

A weather-based marathon training app, a bit like Nike Run Club. When you open
it, the **Today** screen checks the weather where you are and tells you **what
pace to run today**. While you run, it keeps adjusting your target pace based on
the live weather and your heart rate. Built with Flutter (Android).

Open the project folder in Android Studio (or run `flutter run`).

## What the app does

1. **Today screen (the home page)** – looks up today's weather for your location
   and shows a recommended pace, e.g. *"Hot and humid! Slow down about 30s/km."*
   This is the Nike-style "what pace for today" guidance.
2. **Run screen** – tracks your live pace (GPS) and heart rate (Bluetooth),
   saves everything to the phone, and keeps adjusting the target pace.
3. **History screen** – shows your past runs with pace/heart-rate charts and the
   weather each run was done in.

## How the weather changes your pace

All the maths is in [`lib/pacing.dart`](lib/pacing.dart). The idea:

```
recommended pace = your goal pace + weatherSlowdown(weather)
```

`weatherSlowdown` gets bigger when it's hotter, more humid, or windier. The same
function is used for today's advice AND for the live adjustments during a run.
The numbers at the top of `pacing.dart` are the easiest things to change.

## The files (one job per file)

All the code is in the `lib/` folder, with one file per feature:

| File | What it does | Requirement |
|------|--------------|-------------|
| [`lib/main.dart`](lib/main.dart) | starts the app | — |
| [`lib/models.dart`](lib/models.dart) | the data classes (run, reading, weather) | — |
| [`lib/database.dart`](lib/database.dart) | saves/loads everything on the phone (SQLite) | local database |
| [`lib/gps_tracker.dart`](lib/gps_tracker.dart) | running pace from GPS | 1a |
| [`lib/heart_rate.dart`](lib/heart_rate.dart) | heart rate from a Bluetooth strap/watch | 1b |
| [`lib/weather.dart`](lib/weather.dart) | gets the weather from the internet | 2 |
| [`lib/pacing.dart`](lib/pacing.dart) | decides your pace (today + during the run) | 3 |
| [`lib/today_screen.dart`](lib/today_screen.dart) | the Today / what-pace page | 3 + UI |
| [`lib/run_screen.dart`](lib/run_screen.dart) | the live run page (combines GPS + heart rate) | 1 |
| [`lib/history_screen.dart`](lib/history_screen.dart) | past runs + charts | 4 |
| [`lib/cloud.dart`](lib/cloud.dart) | optional cloud backup / offloading / scaling | 5, 6, 7 |

## Setup

1. `flutter pub get`
2. Run it on an Android phone or emulator.
   - The Today screen, weather, pacing and history all work on an emulator.
   - GPS is best on a real phone; the **Bluetooth heart rate needs a real phone**
     plus a heart-rate strap (Bluetooth does not work on an emulator).
3. The weather uses the free Open-Meteo API – no API key needed.
4. The cloud features in `lib/cloud.dart` are optional. Without a backend the app
   still works fully (everything saves on the phone). To use them, deploy
   `backend/` and set `backendBaseUrl` in `lib/cloud.dart`.
