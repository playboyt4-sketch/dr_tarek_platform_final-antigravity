#!/usr/bin/env node
/**
 * migrate_public_to_guest.cjs — PHASE 1 persisted-data migration:
 *   users.student_type:  public_student -> guest
 *   plans/public_free   -> plans/guest (student_type guest, plan_key stays "free")
 *   plan_features:       plan_id public_free -> guest, doc IDs public_free_* -> guest_*
 *   subscriptions:       plan_id public_free -> guest (previous_plan_id untouched: history)
 *   lectures:            public_free_enabled/preview_minutes -> guest_enabled/preview_minutes
 *   system_settings:     default_plan "public_free" -> "guest" ("free" left as-is)
 *   Custom Claims:       student_type/plan_id public_student/public_free -> guest
 *
 * Conventions (repo has no prior migration runner; this is the smallest safe
 * convention for the existing Node tooling):
 *   node scripts\migrate_public_to_guest.cjs            (DRY-RUN, default: no writes)
 *   node scripts\migrate_public_to_guest.cjs --dry-run  (explicit dry-run)
 *   node scripts\migrate_public_to_guest.cjs --apply    (perform writes)
 *
 * Safety properties:
 *   - Dry-run (read-only) by default; writes ONLY with --apply.
 *   - Idempotent: re-running after success is a verified no-op (each step
 *     skips documents already in target state; no guest_guest chains).
 *   - Non-destructive default: legacy plans/public_free is DEACTIVATED
 *     (is_active=false), never deleted; legacy plan_features rows are left in
 *     place and reported for manual cleanup; historical audit/analytics and
 *     subscriptions.previous_plan_id are never rewritten.
 *   - Conflict detection first: aborts (non-zero exit, no writes) when both
 *     plans/public_free and plans/guest are ACTIVE, when a Guest plan with an
 *     unexpected student_type/plan_key is found, or when subscriptions point
 *     at unknown plan IDs.
 *   - Batched writes (<=400 ops/batch), per-step counts, sampled doc IDs.
 *
 * Prerequisites (same as scripts/seed_attachment_feature_keys.cjs):
 *   set GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>
 *   (or point FIRESTORE_EMULATOR_HOST at the emulator for isolated tests)
 *   npm install inside functions/ first (firebase-admin is loaded from there).
 *
 * Rollback limitation: there is no automatic rollback. The migration only
 * moves values forward (public_* -> guest_*) and deactivates (never deletes)
 * the legacy plan doc, so a manual rollback is: re-activate plans/public_free,
 * point references back, re-mint claims. Document the pre-migration counts
 * printed here before applying.
 */

"use strict";

const path = require("path");

let admin;
try {
  const { createRequire } = require("module");
  const functionsRequire = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  admin = functionsRequire("firebase-admin");
} catch (error) {
  console.error(
    "Could not load firebase-admin from functions/node_modules.\n" +
      'Run "npm install" inside the functions/ folder first.',
  );
  process.exit(1);
}

const APPLY = process.argv.includes("--apply");
const DRY_RUN = !APPLY;
const BATCH_LIMIT = 400;

const LEGACY_TYPE = "public_student";
const GUEST_TYPE = "guest";
const LEGACY_PLAN_ID = "public_free";
const GUEST_PLAN_ID = "guest";

function log(...args) {
  console.log(...args);
}

function sample(ids, max = 10) {
  if (ids.length <= max) return ids.join(", ");
  return `${ids.slice(0, max).join(", ")} (+${ids.length - max} more)`;
}

async function commitBatches(db, ops, label) {
  let written = 0;
  for (let i = 0; i < ops.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + BATCH_LIMIT)) op(batch);
    await batch.commit();
    written += Math.min(BATCH_LIMIT, ops.length - i);
    log(`  ...committed ${written}/${ops.length} ${label}`);
  }
  return written;
}

async function main() {
  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  if (!usingEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path first\n" +
        "(or set FIRESTORE_EMULATOR_HOST to run against the emulator).",
    );
    process.exit(1);
  }

  admin.initializeApp();
  const db = admin.firestore();
  const auth = admin.auth();

  log(`=== public_student/public_free -> guest migration (${DRY_RUN ? "DRY-RUN" : "APPLY"}) ===`);

  // ---------- 0. Preflight / conflict detection (read-only) ----------
  const legacyPlanRef = db.collection("plans").doc(LEGACY_PLAN_ID);
  const guestPlanRef = db.collection("plans").doc(GUEST_PLAN_ID);
  const [legacyPlanSnap, guestPlanSnap] = await Promise.all([
    legacyPlanRef.get(),
    guestPlanRef.get(),
  ]);
  const legacyActive = legacyPlanSnap.exists && legacyPlanSnap.data().is_active === true;
  const guestExists = guestPlanSnap.exists;
  const guestActive = guestExists && guestPlanSnap.data().is_active === true;

  log(`plans/${LEGACY_PLAN_ID}: ${legacyPlanSnap.exists ? (legacyActive ? "exists ACTIVE" : "exists inactive") : "absent"}`);
  log(`plans/${GUEST_PLAN_ID}: ${guestExists ? (guestActive ? "exists ACTIVE" : "exists inactive") : "absent"}`);

  if (legacyActive && guestActive) {
    console.error(
      'CONFLICT: both plans/public_free and plans/guest are ACTIVE. ' +
        "Refusing to migrate: resolve manually which doc is canonical first.\n" +
        "Required owner decision: canonical Guest plan document.",
    );
    process.exit(1);
  }
  if (!legacyPlanSnap.exists && !guestExists) {
    console.error(
      "CONFLICT: neither plans/public_free nor plans/guest exists. Nothing to migrate; seed the database first.",
    );
    process.exit(1);
  }
  if (guestExists) {
    const g = guestPlanSnap.data();
    if (g.student_type !== GUEST_TYPE) {
      console.error(
        `CONFLICT: plans/guest has unexpected student_type ${JSON.stringify(g.student_type)} (expected "guest").`,
      );
      process.exit(1);
    }
    if (g.plan_key !== "free") {
      console.error(
        `CONFLICT: plans/guest has unexpected plan_key ${JSON.stringify(g.plan_key)} (expected "free", unchanged by migration).`,
      );
      process.exit(1);
    }
  }
  if (legacyPlanSnap.exists) {
    const legacyPlanData = legacyPlanSnap.data();
    if (legacyPlanData.plan_key !== "free") {
      console.error(
        `CONFLICT: plans/public_free has unexpected plan_key ${JSON.stringify(legacyPlanData.plan_key)} (expected "free"). ` +
          "Production data differs from the approved migration assumption.",
      );
      process.exit(1);
    }
  }

  // Unknown plan references in subscriptions (fail before partial execution).
  const unknownPlanRefs = new Set();
  {
    let last = null;
    for (;;) {
      let query = db.collection("subscriptions").orderBy("__name__").limit(500);
      if (last) query = query.startAfter(last);
      const snap = await query.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        const pid = doc.data().plan_id;
        if (typeof pid === "string" && pid && pid !== LEGACY_PLAN_ID && pid !== GUEST_PLAN_ID) {
          const planSnap = await db.collection("plans").doc(pid).get();
          if (!planSnap.exists) unknownPlanRefs.add(`${doc.id} -> ${pid}`);
        }
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) break;
    }
  }
  if (unknownPlanRefs.size > 0) {
    console.error(
      `CONFLICT: ${unknownPlanRefs.size} subscription(s) point at unknown plan IDs: ` +
        `${[...unknownPlanRefs].slice(0, 10).join("; ")}${unknownPlanRefs.size > 10 ? " ..." : ""}`,
    );
    process.exit(1);
  }

  // ---------- 1. users.student_type ----------
  const legacyUsersSnap = await db.collection("users").where("student_type", "==", LEGACY_TYPE).get();
  const legacyUserIds = legacyUsersSnap.docs.map((d) => d.id);
  log(`users with student_type "${LEGACY_TYPE}": ${legacyUserIds.length}${legacyUserIds.length ? ` (${sample(legacyUserIds)})` : ""}`);
  if (!DRY_RUN && legacyUserIds.length > 0) {
    const ops = legacyUsersSnap.docs.map((doc) => (batch) =>
      batch.update(doc.ref, {
        student_type: GUEST_TYPE,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_by: "migration_public_to_guest",
      }),
    );
    await commitBatches(db, ops, "users.student_type updates");
  }

  // ---------- 2. plans doc ----------
  let planCopyNeeded = legacyPlanSnap.exists && !guestExists;
  if (planCopyNeeded) {
    const data = legacyPlanSnap.data();
    log(`plans: will copy plans/${LEGACY_PLAN_ID} -> plans/${GUEST_PLAN_ID} (student_type guest, plan_key preserved as ${JSON.stringify(data.plan_key)}).`);
    if (!DRY_RUN) {
      await guestPlanRef.set(
        {
          ...data,
          student_type: GUEST_TYPE,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      log("plans: copied.");
    }
  } else if (guestExists) {
    log("plans: plans/guest already present; copy skipped (idempotent).");
  }
  if (legacyActive) {
    log(`plans: will deactivate plans/${LEGACY_PLAN_ID} (is_active=false, reversible).`);
    if (!DRY_RUN) {
      await legacyPlanRef.set(
        {
          is_active: false,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  }

  // ---------- 3. plan_features ----------
  const legacyFeaturesSnap = await db.collection("plan_features").where("plan_id", "==", LEGACY_PLAN_ID).get();
  log(`plan_features with plan_id "${LEGACY_PLAN_ID}": ${legacyFeaturesSnap.size}`);
  const featureCopies = [];
  for (const doc of legacyFeaturesSnap.docs) {
    const featureKey = doc.data().feature_key;
    const targetId = `${GUEST_PLAN_ID}_${String(featureKey).replace(/\./g, "_")}`;
    const targetRef = db.collection("plan_features").doc(targetId);
    const targetSnap = await targetRef.get();
    if (targetSnap.exists && targetSnap.data().plan_id === GUEST_PLAN_ID) continue; // idempotent skip
    featureCopies.push({ source: doc, targetRef });
  }
  log(`plan_features to copy -> plan_id "${GUEST_PLAN_ID}": ${featureCopies.length} (legacy rows left in place, reported for manual cleanup)`);
  if (!DRY_RUN) {
    for (const { source, targetRef } of featureCopies) {
      const data = source.data();
      await targetRef.set(
        {
          ...data,
          plan_id: GUEST_PLAN_ID,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    log("plan_features: copies written.");
  }

  // ---------- 4. subscriptions.plan_id ----------
  const legacySubsSnap = await db.collection("subscriptions").where("plan_id", "==", LEGACY_PLAN_ID).get();
  log(`subscriptions with plan_id "${LEGACY_PLAN_ID}": ${legacySubsSnap.size} (previous_plan_id untouched: history)`);
  if (!DRY_RUN && legacySubsSnap.size > 0) {
    const ops = legacySubsSnap.docs.map((doc) => (batch) =>
      batch.update(doc.ref, {
        plan_id: GUEST_PLAN_ID,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_by: "migration_public_to_guest",
      }),
    );
    await commitBatches(db, ops, "subscriptions.plan_id updates");
  }

  // ---------- 5. lectures preview fields ----------
  let lecturesLegacy = 0;
  let lecturesAlready = 0;
  const lectureRenames = [];
  {
    let last = null;
    for (;;) {
      let query = db.collection("lectures").orderBy("__name__").limit(500);
      if (last) query = query.startAfter(last);
      const snap = await query.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        const data = doc.data();
        const hasLegacy =
          "public_free_enabled" in data || "public_free_preview_minutes" in data;
        const hasNew = "guest_enabled" in data || "guest_preview_minutes" in data;
        if (hasLegacy && !hasNew) {
          lecturesLegacy++;
          if (lectureRenames.length < 20) lectureRenames.push(doc.id);
        } else if (hasNew) {
          lecturesAlready++;
        }
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) break;
    }
  }
  log(`lectures with legacy preview fields only: ${lecturesLegacy}${lectureRenames.length ? ` (${sample(lectureRenames, 20)})` : ""}; already on guest_* fields: ${lecturesAlready}`);
  if (!DRY_RUN && lecturesLegacy > 0) {
    let last = null;
    let moved = 0;
    for (;;) {
      let query = db.collection("lectures").orderBy("__name__").limit(200);
      if (last) query = query.startAfter(last);
      const snap = await query.get();
      if (snap.empty) break;
      const batch = db.batch();
      let batchOps = 0;
      for (const doc of snap.docs) {
        const data = doc.data();
        const hasLegacy =
          "public_free_enabled" in data || "public_free_preview_minutes" in data;
        const hasNew = "guest_enabled" in data || "guest_preview_minutes" in data;
        if (hasLegacy && !hasNew) {
          const update = {};
          if ("public_free_enabled" in data) update.guest_enabled = data.public_free_enabled;
          if ("public_free_preview_minutes" in data) {
            update.guest_preview_minutes = data.public_free_preview_minutes;
          }
          update.public_free_enabled = admin.firestore.FieldValue.delete();
          update.public_free_preview_minutes = admin.firestore.FieldValue.delete();
          update.updated_at = admin.firestore.FieldValue.serverTimestamp();
          batch.update(doc.ref, update);
          batchOps++;
          moved++;
        }
      }
      if (batchOps > 0) await batch.commit();
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 200) break;
    }
    log(`lectures: moved ${moved} doc(s) to guest_* fields.`);
  }

  // ---------- 6. system_settings.default_plan ----------
  const settingsSnap = await db.collection("system_settings").get();
  const settingsFixes = [];
  for (const doc of settingsSnap.docs) {
    const value = doc.data().default_plan;
    if (value === LEGACY_PLAN_ID) settingsFixes.push(doc);
    else {
      log(`system_settings/${doc.id}: default_plan=${JSON.stringify(value)} (left as-is${value === "free" ? ": plan_key, not plan identity" : ""})`);
    }
  }
  log(`system_settings docs needing default_plan "${LEGACY_PLAN_ID}" -> "${GUEST_PLAN_ID}": ${settingsFixes.length}`);
  if (!DRY_RUN) {
    for (const doc of settingsFixes) {
      await doc.ref.update({
        default_plan: GUEST_PLAN_ID,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  // ---------- 7. Custom Claims backfill ----------
  // Users whose Firestore row was (or is) guest-typed but whose token claims
  // still carry legacy values. In dry-run, evaluate the already-migrated set
  // plus the to-be-migrated set by uid.
  const claimCheckIds = new Set(legacyUserIds);
  {
    const guestUsersSnap = await db.collection("users").where("student_type", "==", GUEST_TYPE).limit(500).get();
    for (const doc of guestUsersSnap.docs) claimCheckIds.add(doc.id);
  }
  let claimsStale = 0;
  const claimsStaleSample = [];
  const claimsFixes = [];
  for (const uid of claimCheckIds) {
    let userRecord;
    try {
      userRecord = await auth.getUser(uid);
    } catch (error) {
      log(`claims: uid ${uid} has no Auth record (${error.code || error.message}); skipped.`);
      continue;
    }
    const claims = userRecord.customClaims || {};
    const needsType = claims.student_type === LEGACY_TYPE;
    const needsPlan = claims.plan_id === LEGACY_PLAN_ID;
    if (needsType || needsPlan) {
      claimsStale++;
      if (claimsStaleSample.length < 10) claimsStaleSample.push(uid);
      if (!DRY_RUN) {
        claimsFixes.push(
          auth.setCustomUserClaims(uid, {
            ...claims,
            ...(needsType ? { student_type: GUEST_TYPE } : {}),
            ...(needsPlan ? { plan_id: GUEST_PLAN_ID } : {}),
          }),
        );
        if (claimsFixes.length >= 50) {
          await Promise.all(claimsFixes.splice(0, claimsFixes.length));
        }
      }
    }
  }
  if (!DRY_RUN && claimsFixes.length > 0) await Promise.all(claimsFixes);
  log(`custom claims with legacy values: ${claimsStale}${claimsStaleSample.length ? ` (${sample(claimsStaleSample)})` : ""}${DRY_RUN ? " (re-run with --apply to refresh)" : " (refreshed)"}`);
  if (!DRY_RUN) {
    log("claims: users keep existing sessions; refreshed claims apply on next token refresh (client re-login / forced refresh). No global revocation performed.");
  }

  log(`=== migration ${DRY_RUN ? "DRY-RUN complete (no writes performed). Re-run with --apply to execute." : "APPLY complete."} ===`);
  log("NOTE: no automatic rollback. Legacy plans/public_free was deactivated (not deleted); legacy plan_features rows were left for manual cleanup; history (audit/analytics/previous_plan_id) untouched.");
}

main().catch((error) => {
  console.error("Migration failed:", error);
  process.exitCode = 1;
});
