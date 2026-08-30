#!/usr/bin/env node
/**
 * seed_attachment_feature_keys.cjs — ONE-TIME (idempotent) seeding of the
 * ratified `attachment.access` / `attachment.download` Feature Matrix keys
 * into `plan_features` for ALL FOUR plans, BEFORE any deploy of the
 * attachment-gating change goes to production.
 *
 * Teacher-confirmed defaults:
 *   plan_key      attachment.access   attachment.download
 *   public_free   false               false
 *   center_free   true                false
 *   center_pro    true                true
 *   center_max    true                true
 *
 * Behaviour:
 *   - Resolves plan documents by `plans.plan_key` (never hardcodes ids).
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

const PLAN_KEYS = ["public_free", "center_free", "center_pro", "center_max"];

// Teacher-confirmed matrix (see header). feature_value mirrors the pdf.*
// convention: booleans for on/off access keys.
const RATIFIED_MATRIX = {
  "attachment.access": {
    public_free: false,
    center_free: true,
    center_pro: true,
    center_max: true,
  },
  "attachment.download": {
    public_free: false,
    center_free: false,
    center_pro: true,
    center_max: true,
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

  // Resolve every plan by plan_key; abort rather than half-seed if any of
  // the four canonical plans is missing.
  const plansByKey = {};
  for (const planKey of PLAN_KEYS) {
    const snap = await db
      .collection("plans")
      .where("plan_key", "==", planKey)
      .where("is_active", "==", true)
      .limit(2)
      .get();
    if (snap.empty) {
      console.error(`ABORT: no active plan found for plan_key "${planKey}".`);
      process.exit(1);
    }
    if (snap.size > 1) {
      console.error(
        `ABORT: multiple active plans share plan_key "${planKey}" — resolve manually first.`,
      );
      process.exit(1);
    }
    plansByKey[planKey] = snap.docs[0];
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  let written = 0;
  let unchanged = 0;

  for (const [featureKey, perPlan] of Object.entries(RATIFIED_MATRIX)) {
    for (const planKey of PLAN_KEYS) {
      const planDoc = plansByKey[planKey];
      const expected = perPlan[planKey];
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
          plan_key: planKey,
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
          `unchanged ${planKey} :: ${featureKey} = ${expected} (doc ${docRef.id})`,
        );
      } else {
        written += 1;
        console.log(
          `SET       ${planKey} :: ${featureKey} = ${expected}` +
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
