/**
 * PacePilot — reference serverless backend (Firebase Cloud Functions / Gen 2).
 *
 * Implements the API contract the Flutter client calls in:
 *   - lib/services/cloud/computational_offloading_service.dart   (Function 5)
 *   - lib/services/cloud/cloud_sync_service.dart                 (Function 6)
 *   - lib/services/cloud/elastic_scalability_manager.dart        (Function 7)
 *
 * Deploy:  firebase deploy --only functions
 */

const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

/* ----------------------------------------------------------------------------
 * FUNCTION 5 — Computational Offloading
 * The heavy, authoritative pacing calculation. Mirrors the on-device fallback
 * in PacingEngineService so results are identical whether computed here or
 * locally. Min instances + generous concurrency keep latency low.
 * ------------------------------------------------------------------------- */
exports.pacingEvaluate = onRequest(
  { region: "us-central1", minInstances: 1, concurrency: 80 },
  (req, res) => {
    const {
      point,
      weather,
      goalPaceSecPerKm,
      currentTargetSecPerKm,
      safeHeartRateCeiling,
    } = req.body;

    const hr = point?.heart_rate_bpm ?? null;
    const previous = currentTargetSecPerKm;
    const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

    // Layer 1 — weather-adjusted baseline target (mirrors weatherPaceOffset).
    let weatherOffset = 0;
    let effectiveCeiling = safeHeartRateCeiling;
    if (weather) {
      const heatStress =
        weather.temperature_c +
        (weather.humidity_pct / 100) * 0.6 * weather.temperature_c;
      const heat = clamp(heatStress - 16, 0, 30) * 4.0;
      const wind = clamp(weather.wind_speed_mps, 0, 20) * 1.5;
      weatherOffset = clamp(heat + wind, 0, 90);
      effectiveCeiling -= Math.round(clamp(heatStress - 25, 0, 20));
    }
    const weatherTarget = goalPaceSecPerKm + weatherOffset;

    let action = "hold";
    let target = weatherTarget;
    let reason = weatherOffset > 0
      ? `Weather-adjusted target (+${Math.round(weatherOffset)}s/km)`
      : "Conditions good — holding goal pace";
    let isSafetyAlert = false;

    if (hr != null && hr > effectiveCeiling) {
      action = "slowDown";
      target = clamp(previous + 20, weatherTarget, goalPaceSecPerKm + 150);
      reason = `HR ${hr}bpm over safe ceiling ${effectiveCeiling}`;
      isSafetyAlert = true;
    } else if (hr != null && hr < effectiveCeiling - 15 && previous > weatherTarget) {
      action = "speedUp";
      target = Math.max(previous - 10, weatherTarget);
      reason = "HR has headroom — easing toward weather target";
    } else if (weatherTarget > previous + 0.5) {
      action = "slowDown";
      isSafetyAlert = weatherOffset >= 30;
    } else if (weatherTarget < previous - 0.5) {
      action = "speedUp";
    }

    res.json({ action, targetPaceSecPerKm: target, reason, isSafetyAlert });
  }
);

/** Heavy post-run aggregate analysis (zone breakdown, weather correlation). */
exports.telemetryAnalyze = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    const { sessionUuid } = req.body;
    const snap = await db
      .collection("sessions")
      .doc(sessionUuid)
      .collection("telemetry")
      .get();

    let sumSpeed = 0;
    let sumHr = 0;
    let hrCount = 0;
    snap.forEach((doc) => {
      const d = doc.data();
      sumSpeed += d.speed_mps || 0;
      if (d.heart_rate_bpm != null) {
        sumHr += d.heart_rate_bpm;
        hrCount += 1;
      }
    });
    const n = snap.size || 1;
    res.json({
      points: snap.size,
      avgSpeedMps: sumSpeed / n,
      avgHeartRate: hrCount ? sumHr / hrCount : null,
    });
  }
);

/* ----------------------------------------------------------------------------
 * FUNCTION 6 — Automated Cloud Data Synchronization
 * Idempotent session upsert + batched telemetry append into Firestore, so a
 * sudden phone power-off never loses training data.
 * ------------------------------------------------------------------------- */
exports.syncSession = onRequest({ region: "us-central1" }, async (req, res) => {
  const session = req.body;
  await db
    .collection("sessions")
    .doc(session.uuid)
    .set({ ...session, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  res.json({ ok: true });
});

exports.syncTelemetry = onRequest(
  { region: "us-central1", concurrency: 80 },
  async (req, res) => {
    const points = req.body.points || [];
    const batch = db.batch();
    for (const p of points) {
      const sessionRef = db.collection("sessions").doc(String(p.session_id));
      const ref = sessionRef.collection("telemetry").doc();
      batch.set(ref, p);
    }
    await batch.commit();
    res.json({ ok: true, written: points.length });
  }
);

/* ----------------------------------------------------------------------------
 * FUNCTION 7 — Elastic Cloud Scalability Manager
 * The platform autoscales instances (min/max set per-function above). These
 * endpoints let the client pre-warm before a race surge and read health so it
 * can decide whether to offload or compute on-device.
 * ------------------------------------------------------------------------- */
exports.scalingPrewarm = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    const { startTime, estimatedConcurrentRunners } = req.body;
    // Record the intent; a scheduled job (or Cloud Run min-instances bump)
    // reads this to pre-provision capacity ahead of the start time.
    await db.collection("scaling_hints").add({
      startTime,
      estimatedConcurrentRunners,
      createdAt: FieldValue.serverTimestamp(),
    });
    res.json({ ok: true });
  }
);

exports.scalingHealth = onRequest({ region: "us-central1" }, (req, res) => {
  // In production, surface real metrics (active instances, p95 latency).
  res.json({ healthy: true, activeInstances: 1, loadFactor: 0.2 });
});
