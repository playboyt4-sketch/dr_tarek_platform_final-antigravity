#!/usr/bin/env node
/**
 * seed_attachment_feature_keys.cjs — ONE-TIME (idempotent) seeding of the
 * ratified `attachment.access` / `attachment.download` Feature Matrix keys
 * into `plan_features` for ALL FOUR plans, BEFORE any deploy of the
 * attachment-gating change goes to production.
 *
 * Teacher-confirmed defaults (by plan DOCUMENT ID — plan_key "free" is
 * shared by the Guest plan and the Center Free plan, so plan_key cannot
 * identify a plan on its own):
 *   plan id       attachment.access   attachment.download
 *   guest         false               false
 *   free          true                false
 *   pro           true                true
 *   max           true                true
 *
 * Behaviour:
 *   - Resolves plan documents by document ID (`plans/guest`, ...).
 *   - Upserts ONE plan_features doc per (plan, key) using the deterministic
 *     id `${planId}_${featureKey}` and MERGES, so re-running is safe.
 *   - Never overwrites a pre-existing doc's feature_value with different
 *     semantics silently: it prints the previous value and forces it to the
 *     confirmed default above (this script IS the ratification).
 *
 * Run locally by the Teacher (Platform Owner), exactly like
 * scripts/bootstrap_teacher.cjs:
 *   set GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>
 *   node scripts\seed_attachment_feature_keys.cjs
 *
 * This file lives in <repo>/scripts/ — OUTSIDE functions/ (firebase.json
 * functions.source = "functions"), so it can never be deployed as an
 * endpoint.
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

// PHASE 4 plan ID simplification: Center plan document IDs are "free" /
// "pro" / "max" (were "center_free" / "center_pro" / "center_max").
// plan_key stays "free" for both guest and free — never use it here
// as a plan identity.
const PLAN_IDS = ["guest", "free", "pro", "max"];

// Teacher-confirmed matrix (see header). feature_value mirrors the pdf.*
// convention: booleans for on/off access keys.
const RATIFIED_MATRIX = {
  "attachment.access": {
    guest: false,
    free: true,
    pro: true,
    max: true,
  },
  "attachment.download": {
    guest: false,
    free: false,
    pro: true,
    max: true,
  },
};

async function main() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path first.\n" +
        "Firebase Console -> Project settings -> Service accounts -> Generate new private key.",
    );
    process.exit(1);
  }

  admin.initializeApp();
  const db = admin.firestore();

  // Resolve every plan by document ID; abort rather than half-seed if any of
  // the four canonical plans is missing or inactive.
  const plansById = {};
  for (const planId of PLAN_IDS) {
    const ref = db.collection("plans").doc(planId);
    const snap = await ref.get();
    if (!snap.exists) {
      console.error(`ABORT: plan document "plans/${planId}" was not found.`);
      process.exit(1);
    }
    if (snap.data().is_active !== true) {
      console.error(`ABORT: plan document "plans/${planId}" is not active.`);
      process.exit(1);
    }
    plansById[planId] = snap;
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  let written = 0;
  let unchanged = 0;

  for (const [featureKey, perPlan] of Object.entries(RATIFIED_MATRIX)) {
    for (const planId of PLAN_IDS) {
      const planDoc = plansById[planId];
      const expected = perPlan[planId];
      const docRef = db
        .collection("plan_features")
        .doc(`${planDoc.id}_${featureKey}`);
      const existing = await docRef.get();
      const before =
        existing.exists ?
          {
            enabled: existing.data().enabled,
            feature_value: existing.data().feature_value,
          } :
          null;

      await docRef.set(
        {
          plan_id: planDoc.id,
          plan_key: planDoc.data().plan_key ?? null,
          feature_key: featureKey,
          label: featureKey === "attachment.access"
            ? "فتح المرفقات"
            : "تحميل المرفقات",
          enabled: expected,
          feature_value: expected,
          seeded_by: "seed_attachment_feature_keys.cjs",
          updated_at: now,
          ...(existing.exists ? {} : { created_at: now }),
        },
        { merge: true },
      );

      if (
        before &&
        (before.enabled === expected || before.feature_value === expected)
      ) {
        unchanged += 1;
        console.log(
          `unchanged ${planId} :: ${featureKey} = ${expected} (doc ${docRef.id})`,
        );
      } else {
        written += 1;
        console.log(
          `SET       ${planId} :: ${featureKey} = ${expected}` +
            `${before ? ` (previous: ${JSON.stringify(before)})` : ""}` +
            ` (doc ${docRef.id})`,
        );
      }
    }
  }

  console.log("");
  console.log(
    `DONE — ${written} doc(s) written, ${unchanged} already correct. ` +
      "Attachment gating may now be deployed safely.",
  );
}

main().catch((error) => {
  console.error("Seeding failed:", error.message);
  process.exitCode = 1;
});
