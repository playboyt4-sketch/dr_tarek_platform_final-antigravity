#!/usr/bin/env node
/**
 * migrate_center_plan_ids.cjs — PHASE 4 plan ID simplification:
 *   plans/center_free -> plans/free   (plan_key stays "free")
 *   plans/center_pro  -> plans/pro    (plan_key stays "pro")
 *   plans/center_max  -> plans/max    (plan_key stays "max")
 *   plans/guest is NEVER touched.
 *
 * plan_key values are NOT renamed: the canonical seed already stores
 * plan_key "free" / "pro" / "max" on the Center plans, and backend
 * default-plan resolution queries by (plan_key, student_type). If a legacy
 * plan doc still carries the old-style plan_key ("center_free" etc. per the
 * v1.7/v1.8 database drafts), the copy NORMALIZES plan_key to the target
 * value and reports it. Any other unexpected plan_key aborts (conflict).
 *
 * Scopes migrated (current references only):
 *   plans:              copy legacy -> target (fields/timestamps preserved,
 *                       plan_key normalized when old-style), then DEACTIVATE
 *                       legacy (is_active=false). Never deleted.
 *   plan_features:      plan_id legacy -> target, doc IDs
 *                       legacy_* -> target_* (legacy rows left in place and
 *                       reported for manual cleanup; never deleted).
 *   subscriptions:      plan_id legacy -> target. previous_plan_id is
 *                       HISTORY and is never rewritten.
 *   trial_campaigns:    plan_id legacy -> target (when the collection exists).
 *   system_settings:    default_plan equal to a legacy plan ID -> target ID.
 *                       plan_key values such as "free" are left as-is.
 *   Custom Claims:      claims.plan_id legacy -> target (merged, no global
 *                       revocation; role/student_type untouched).
 *
 * Never touched (history stays historically accurate):
 *   subscriptions.previous_plan_id, admin_audit_log, analytics_events,
 *   payment_logs, users.student_type, plans/guest, every plan_key.
 *
 * Conventions (same as scripts/migrate_public_to_guest.cjs):
 *   node scripts\migrate_center_plan_ids.cjs            (DRY-RUN, no writes)
 *   node scripts\migrate_center_plan_ids.cjs --dry-run  (explicit dry-run)
 *   node scripts\migrate_center_plan_ids.cjs --apply    (perform writes)
 *
 * Safety properties:
 *   - Dry-run (read-only) by default; writes ONLY with --apply.
 *   - Idempotent: re-running after success is a verified no-op (each step
 *     skips documents already in target state).
 *   - Conflict detection first: aborts (non-zero exit, no writes) when a
 *     legacy plan and its target are BOTH active, when neither exists, when
 *     a target plan has an unexpected student_type/plan_key, when a legacy
 *     plan has an unexpected student_type/plan_key, when subscriptions point
 *     at unknown plan IDs, or when duplicate plan_features targets exist
 *     with divergent content.
 *   - Batched writes (<=400 ops/batch), per-step counts, sampled doc IDs.
 *
 * Prerequisites:
 *   set GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>
 *   (or point FIRESTORE_EMULATOR_HOST at the emulator for isolated tests)
 *   npm install inside functions/ first (firebase-admin is loaded from there).
 *
 * Rollback limitation: there is no automatic rollback. The migration only
 * moves values forward and deactivates (never deletes) legacy plan docs, so
 * a manual rollback is: re-activate the legacy plans, point references back,
 * re-mint claims. Document the pre-migration counts printed here before
 * applying. DO NOT run against production without owner sign-off, a
 * verified backup, and a dry-run conflict report.
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

const CENTER_STUDENT_TYPE = "center_student";
const GUEST_PLAN_ID = "guest";

// Legacy plan ID -> { target, planKey }. plan_key is never renamed away
// from these values; a legacy doc carrying the old-style "center_*" plan_key
// is normalized to planKey on copy.
const PLAN_MIGRATION = {
  center_free: { target: "free", planKey: "free" },
  center_pro: { target: "pro", planKey: "pro" },
  center_max: { target: "max", planKey: "max" },
};
const LEGACY_IDS = Object.keys(PLAN_MIGRATION);
const TARGET_IDS = LEGACY_IDS.map((id) => PLAN_MIGRATION[id].target);

function log(...args) {
  console.log(...args);
}

function sample(ids, max = 10) {
  if (ids.length <= max) return ids.join(", ");
  return `${ids.slice(0, max).join(", ")} (+${ids.length - max} more)`;
}

function fail(message) {
  console.error(`CONFLICT: ${message}`);
  process.exit(1);
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

function featureDocId(planId, featureKey) {
  return `${planId}_${String(featureKey).replace(/\./g, "_")}`;
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

  log(`=== center_* plan ID simplification (${DRY_RUN ? "DRY-RUN" : "APPLY"}) ===`);
  log(`mapping: ${LEGACY_IDS.map((id) => `${id} -> ${PLAN_MIGRATION[id].target}`).join(", ")}; guest untouched`);

  // ---------- 0. Preflight / conflict detection (read-only) ----------
  const planSnaps = {};
  for (const id of [...LEGACY_IDS, ...TARGET_IDS, GUEST_PLAN_ID]) {
    planSnaps[id] = await db.collection("plans").doc(id).get();
  }
  const isActive = (snap) => snap.exists && snap.data().is_active === true;

  for (const legacyId of LEGACY_IDS) {
    const { target, planKey } = PLAN_MIGRATION[legacyId];
    const legacySnap = planSnaps[legacyId];
    const targetSnap = planSnaps[target];
    log(
      `plans/${legacyId}: ${legacySnap.exists ? (isActive(legacySnap) ? "exists ACTIVE" : "exists inactive") : "absent"}; ` +
        `plans/${target}: ${targetSnap.exists ? (isActive(targetSnap) ? "exists ACTIVE" : "exists inactive") : "absent"}`,
    );
    if (isActive(legacySnap) && isActive(targetSnap)) {
      fail(
        `both plans/${legacyId} and plans/${target} are ACTIVE. Refusing to migrate: ` +
          "resolve manually which doc is canonical first. Required owner decision: canonical plan document.",
      );
    }
    if (!legacySnap.exists && !targetSnap.exists) {
      fail(
        `neither plans/${legacyId} nor plans/${target} exists. Nothing to migrate; seed the database first.`,
      );
    }
    if (legacySnap.exists) {
      const data = legacySnap.data() || {};
      if (data.student_type !== CENTER_STUDENT_TYPE) {
        fail(
          `plans/${legacyId} has unexpected student_type ${JSON.stringify(data.student_type)} ` +
            `(expected "${CENTER_STUDENT_TYPE}"). Production data differs from the approved migration assumption.`,
        );
      }
      if (data.plan_key !== planKey && data.plan_key !== legacyId) {
        fail(
          `plans/${legacyId} has unexpected plan_key ${JSON.stringify(data.plan_key)} ` +
            `(expected ${JSON.stringify(planKey)} or legacy ${JSON.stringify(legacyId)}).`,
        );
      }
    }
    if (targetSnap.exists) {
      const data = targetSnap.data() || {};
      if (data.student_type !== CENTER_STUDENT_TYPE) {
        fail(
          `plans/${target} has unexpected student_type ${JSON.stringify(data.student_type)} ` +
            `(expected "${CENTER_STUDENT_TYPE}").`,
        );
      }
      if (data.plan_key !== planKey) {
        fail(
          `plans/${target} has unexpected plan_key ${JSON.stringify(data.plan_key)} ` +
            `(expected ${JSON.stringify(planKey)}, unchanged by migration).`,
        );
      }
    }
  }
  if (planSnaps[GUEST_PLAN_ID].exists) {
    const g = planSnaps[GUEST_PLAN_ID].data() || {};
    if (g.student_type !== "guest" || g.plan_key !== "free") {
      fail(
        `plans/guest has unexpected identity (student_type=${JSON.stringify(g.student_type)}, ` +
          `plan_key=${JSON.stringify(g.plan_key)}). Guest must stay (guest, free).`,
      );
    }
    log("plans/guest: present with expected identity; untouched.");
  } else {
    log("plans/guest: absent (nothing to verify; left untouched).");
  }

  // Unknown plan references in subscriptions (fail before partial execution).
  const knownIds = new Set([...LEGACY_IDS, ...TARGET_IDS, GUEST_PLAN_ID, "public_free"]);
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
        if (typeof pid !== "string" || !pid) continue;
        if (knownIds.has(pid)) continue;
        const planSnap = await db.collection("plans").doc(pid).get();
        if (!planSnap.exists) unknownPlanRefs.add(`${doc.id} -> ${pid}`);
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) break;
    }
  }
  if (unknownPlanRefs.size > 0) {
    fail(
      `${unknownPlanRefs.size} subscription(s) point at unknown plan IDs: ` +
        `${[...unknownPlanRefs].slice(0, 10).join("; ")}${unknownPlanRefs.size > 10 ? " ..." : ""}`,
    );
  }
  log("subscriptions: no unknown plan_id references.");

  // ---------- 1. plans docs ----------
  let plansCopied = 0;
  let plansDeactivated = 0;
  for (const legacyId of LEGACY_IDS) {
    const { target, planKey } = PLAN_MIGRATION[legacyId];
    const legacySnap = planSnaps[legacyId];
    const targetSnap = planSnaps[target];
    if (legacySnap.exists && !targetSnap.exists) {
      const data = legacySnap.data() || {};
      const normalizedKey = data.plan_key === legacyId;
      log(
        `plans: will copy plans/${legacyId} -> plans/${target} ` +
          `(student_type preserved; plan_key ${normalizedKey ? `normalized ${JSON.stringify(legacyId)} -> ${JSON.stringify(planKey)}` : `preserved as ${JSON.stringify(data.plan_key)}`}).`,
      );
      if (!DRY_RUN) {
        await db
          .collection("plans")
          .doc(target)
          .set(
            {
              ...data,
              student_type: CENTER_STUDENT_TYPE,
              plan_key: planKey,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        plansCopied++;
      }
    } else if (targetSnap.exists) {
      log(`plans: plans/${target} already present; copy skipped (idempotent).`);
    }
    if (isActive(legacySnap)) {
      log(`plans: will deactivate plans/${legacyId} (is_active=false, reversible).`);
      if (!DRY_RUN) {
        await db.collection("plans").doc(legacyId).set(
          {
            is_active: false,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        plansDeactivated++;
      }
    }
  }

  // ---------- 2. plan_features ----------
  let featuresToCopy = 0;
  const featureCopies = [];
  for (const legacyId of LEGACY_IDS) {
    const { target } = PLAN_MIGRATION[legacyId];
    const legacyFeaturesSnap = await db.collection("plan_features").where("plan_id", "==", legacyId).get();
    let pending = 0;
    for (const doc of legacyFeaturesSnap.docs) {
      const featureKey = doc.data().feature_key;
      const targetRef = db.collection("plan_features").doc(featureDocId(target, featureKey));
      const targetSnap = await targetRef.get();
      if (targetSnap.exists && targetSnap.data().plan_id === target) continue; // idempotent skip
      if (targetSnap.exists && targetSnap.data().plan_id !== target) {
        fail(
          `plan_features/${targetRef.id} already exists with divergent plan_id ` +
            `${JSON.stringify(targetSnap.data().plan_id)} (expected ${JSON.stringify(target)}). Resolve manually.`,
        );
      }
      featureCopies.push({ source: doc, targetRef, target });
      pending++;
    }
    log(`plan_features with plan_id "${legacyId}": ${legacyFeaturesSnap.size}; to copy -> "${target}": ${pending}`);
    featuresToCopy += pending;
  }
  log(`plan_features: ${featuresToCopy} doc(s) to copy (legacy rows left in place, reported for manual cleanup)`);
  if (!DRY_RUN) {
    for (const { source, targetRef, target } of featureCopies) {
      const data = source.data();
      await targetRef.set(
        {
          ...data,
          plan_id: target,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    if (featureCopies.length > 0) log("plan_features: copies written.");
  }

  // ---------- 3. subscriptions.plan_id (previous_plan_id untouched) ----------
  let subsToUpdate = 0;
  const subOps = [];
  for (const legacyId of LEGACY_IDS) {
    const { target } = PLAN_MIGRATION[legacyId];
    const snap = await db.collection("subscriptions").where("plan_id", "==", legacyId).get();
    log(`subscriptions with plan_id "${legacyId}": ${snap.size}${snap.size ? ` (${sample(snap.docs.map((d) => d.id))})` : ""} (previous_plan_id untouched: history)`);
    subsToUpdate += snap.size;
    if (!DRY_RUN) {
      for (const doc of snap.docs) {
        subOps.push((batch) =>
          batch.update(doc.ref, {
            plan_id: target,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_by: "migration_center_plan_ids",
          }),
        );
      }
    }
  }
  if (!DRY_RUN && subOps.length > 0) await commitBatches(db, subOps, "subscriptions.plan_id updates");

  // ---------- 4. trial_campaigns.plan_id (when present) ----------
  let trialsToUpdate = 0;
  const trialOps = [];
  for (const legacyId of LEGACY_IDS) {
    const { target } = PLAN_MIGRATION[legacyId];
    const snap = await db.collection("trial_campaigns").where("plan_id", "==", legacyId).get();
    if (snap.size > 0) {
      log(`trial_campaigns with plan_id "${legacyId}": ${snap.size} (${sample(snap.docs.map((d) => d.id))})`);
      trialsToUpdate += snap.size;
      if (!DRY_RUN) {
        for (const doc of snap.docs) {
          trialOps.push((batch) =>
            batch.update(doc.ref, {
              plan_id: target,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            }),
          );
        }
      }
    }
  }
  if (trialsToUpdate === 0) log("trial_campaigns: no legacy plan_id references.");
  if (!DRY_RUN && trialOps.length > 0) await commitBatches(db, trialOps, "trial_campaigns.plan_id updates");

  // ---------- 5. system_settings.default_plan ----------
  // default_plan holds a plan_key ("free") or the Guest plan ID ("guest");
  // a legacy center_* document ID here is a misconfiguration — fix it.
  const settingsSnap = await db.collection("system_settings").get();
  const settingsFixes = [];
  for (const doc of settingsSnap.docs) {
    const value = doc.data().default_plan;
    if (typeof value === "string" && LEGACY_IDS.includes(value)) {
      settingsFixes.push({ doc, from: value, to: PLAN_MIGRATION[value].target });
    } else {
      log(`system_settings/${doc.id}: default_plan=${JSON.stringify(value)} (left as-is)`);
    }
  }
  log(`system_settings docs needing legacy plan ID fix: ${settingsFixes.length}`);
  if (!DRY_RUN) {
    for (const { doc, to } of settingsFixes) {
      await doc.ref.update({
        default_plan: to,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  // ---------- 6. Custom Claims backfill ----------
  // Users whose token claims still carry legacy plan IDs (Firestore rows
  // carry no plan_id; collect candidate uids from legacy-plan subscriptions
  // plus a bounded Auth scan).
  const claimCandidateIds = new Set();
  for (const legacyId of LEGACY_IDS) {
    const snap = await db.collection("subscriptions").where("plan_id", "==", legacyId).limit(500).get();
    for (const doc of snap.docs) {
      const sid = doc.data().student_id;
      if (typeof sid === "string" && sid) claimCandidateIds.add(sid);
    }
  }
  // In dry-run the subscriptions may already be migrated; also scan Auth
  // directly for stale claims so the report is accurate either way.
  let claimsStale = 0;
  const claimsStaleSample = [];
  const claimsFixes = [];
  let nextPageToken = undefined;
  for (;;) {
    const listResult = await auth.listUsers(500, nextPageToken);
    for (const userRecord of listResult.users) {
      claimCandidateIds.add(userRecord.uid);
      const claims = userRecord.customClaims || {};
      const pid = claims.plan_id;
      if (typeof pid === "string" && LEGACY_IDS.includes(pid)) {
        claimsStale++;
        if (claimsStaleSample.length < 10) claimsStaleSample.push(`${userRecord.uid} -> ${pid}`);
        if (!DRY_RUN) {
          claimsFixes.push(
            auth.setCustomUserClaims(userRecord.uid, {
              ...claims,
              plan_id: PLAN_MIGRATION[pid].target,
            }),
          );
          if (claimsFixes.length >= 50) {
            await Promise.all(claimsFixes.splice(0, claimsFixes.length));
          }
        }
      }
    }
    nextPageToken = listResult.pageToken;
    if (!nextPageToken) break;
  }
  if (!DRY_RUN && claimsFixes.length > 0) await Promise.all(claimsFixes);
  log(
    `custom claims with legacy plan_id: ${claimsStale}${claimsStaleSample.length ? ` (${sample(claimsStaleSample)})` : ""}` +
      `${DRY_RUN ? " (re-run with --apply to refresh)" : " (refreshed)"}`,
  );
  if (!DRY_RUN) {
    log("claims: users keep existing sessions; refreshed claims apply on next token refresh (client re-login / forced refresh). No global revocation performed. role/student_type untouched.");
  }

  // ---------- 7. Summary ----------
  log("--- summary ---");
  log(`plans copied: ${DRY_RUN ? "(dry-run, would copy where target absent)" : plansCopied}; legacy plans deactivated: ${DRY_RUN ? "(dry-run)" : plansDeactivated}`);
  log(`plan_features to copy: ${featuresToCopy}; subscriptions to update: ${subsToUpdate}; trial_campaigns to update: ${trialsToUpdate}; settings to fix: ${settingsFixes.length}; stale claims: ${claimsStale}`);
  log(`=== migration ${DRY_RUN ? "DRY-RUN complete (no writes performed). Re-run with --apply to execute." : "APPLY complete."} ===`);
  log("NOTE: no automatic rollback. Legacy plans/* docs were deactivated (not deleted); legacy plan_features rows were left for manual cleanup; history (audit/analytics/previous_plan_id) and every plan_key untouched.");
}

main().catch((error) => {
  console.error("Migration failed:", error);
  process.exitCode = 1;
});
