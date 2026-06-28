# PacePilot — Serverless Backend (reference)

This is the cloud counterpart to the Flutter app's `lib/services/cloud/`
services. It's a reference implementation on **Firebase Cloud Functions (Gen 2)**
with **Firestore** as the secure cloud database.

## API contract

| Endpoint              | Client caller (Dart)                          | Function |
|-----------------------|-----------------------------------------------|----------|
| `POST /pacing/evaluate`  | `ComputationalOffloadingService.computePacing` | 5 |
| `POST /telemetry/analyze`| `ComputationalOffloadingService.analyzeSession`| 5 |
| `POST /sync/session`     | `CloudSyncService.pushSession`                 | 6 |
| `POST /sync/telemetry`   | `CloudSyncService.enqueue` / `_flush`          | 6 |
| `POST /scaling/prewarm`  | `ElasticScalabilityManager.announceExpectedSurge` | 7 |
| `POST /scaling/health`   | `ElasticScalabilityManager.health`             | 7 |

> In `functions/index.js` these are exported as `pacingEvaluate`, `telemetryAnalyze`,
> `syncSession`, `syncTelemetry`, `scalingPrewarm`, `scalingHealth`. Map them to the
> paths above via Firebase Hosting rewrites or an API Gateway, or set
> `backendBaseUrl` in `lib/main.dart` to the functions base URL and adjust paths.

## Elastic scalability (Function 7)

Autoscaling is **declarative**, configured per-function in `index.js`:

- `minInstances` keeps warm capacity (low latency for the pacing path).
- `concurrency` lets one instance serve many simultaneous requests.
- The platform adds/removes instances automatically as load rises on race
  morning. `scalingPrewarm` records an upcoming surge so a scheduled job can
  raise `minInstances` ahead of the start gun.

## Deploy

```bash
cd backend/functions
npm install firebase-admin firebase-functions
firebase deploy --only functions
```

Then set `backendBaseUrl` in `lib/main.dart`.
