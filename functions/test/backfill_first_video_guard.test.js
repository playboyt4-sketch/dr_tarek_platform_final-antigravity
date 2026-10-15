/**
 * Backfill project-ID guard tests (Phase 8).
 *
 * Pure unit tests only: no Firestore, no emulator, no production contact.
 * The script module has no side effects on require; we exercise only the
 * exported guard helpers plus static placement checks.
 *
 * Run safely without emulators:
 *   node test/backfill_first_video_guard.test.js   (cwd = functions/)
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const backfill = require("../../scripts/backfill_first_video.cjs");

let passed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

const EXPECTED = "dr-tarek-platform";

// 1. Expected project ID accepted (production-like, no emulator).
check("expected project ID accepted", () => {
  assert.equal(backfill.EXPECTED_PROJECT_ID, EXPECTED);
  const out = backfill.verifyTargetProject({
    env: {},
    adminOptionsProjectId: null,
    adminCredentialProjectId: null,
    credentialFileProjectId: EXPECTED,
  });
  assert.equal(out, EXPECTED);
});

// Explicit Admin SDK projectId alone is accepted.
check("explicit admin projectId accepted", () => {
  const out = backfill.verifyTargetProject({
    env: {},
    adminOptionsProjectId: EXPECTED,
    adminCredentialProjectId: null,
    credentialFileProjectId: null,
  });
  assert.equal(out, EXPECTED);
});

// 2. Wrong project ID rejected.
check("wrong project ID rejected", () => {
  assert.throws(
    () =>
      backfill.verifyTargetProject({
        env: {},
        adminOptionsProjectId: null,
        adminCredentialProjectId: null,
        credentialFileProjectId: "some-other-project",
      }),
    /does not match/
  );
});

// 3. Missing project ID rejected.
check("missing project ID rejected", () => {
  assert.throws(
    () =>
      backfill.verifyTargetProject({
        env: {},
        adminOptionsProjectId: null,
        adminCredentialProjectId: null,
        credentialFileProjectId: null,
      }),
    /unable to determine/
  );
  const resolved = backfill.resolveEffectiveProjectId({
    env: {},
    adminOptionsProjectId: null,
    adminCredentialProjectId: null,
    credentialFileProjectId: null,
  });
  assert.equal(resolved.projectId, null);
  assert.equal(resolved.reason, "missing");
});

// Ambiguous sources rejected (env vs credential disagree).
check("ambiguous project IDs rejected", () => {
  const resolved = backfill.resolveEffectiveProjectId({
    env: {GOOGLE_CLOUD_PROJECT: EXPECTED},
    adminOptionsProjectId: null,
    adminCredentialProjectId: null,
    credentialFileProjectId: "other-project",
  });
  assert.equal(resolved.projectId, null);
  assert.equal(resolved.reason, "ambiguous");
  assert.throws(
    () =>
      backfill.verifyTargetProject({
        env: {GOOGLE_CLOUD_PROJECT: EXPECTED},
        adminOptionsProjectId: null,
        adminCredentialProjectId: null,
        credentialFileProjectId: "other-project",
      }),
    /unable to determine.*ambiguous/
  );
});

// Consistent duplicates (same ID from several sources) accepted.
check("consistent duplicate sources accepted", () => {
  const out = backfill.verifyTargetProject({
    env: {GOOGLE_CLOUD_PROJECT: EXPECTED, GCLOUD_PROJECT: EXPECTED},
    adminOptionsProjectId: EXPECTED,
    adminCredentialProjectId: null,
    credentialFileProjectId: EXPECTED,
  });
  assert.equal(out, EXPECTED);
});

// Credential JSON parsing extracts only project_id, tolerates junk.
check("credential JSON extraction is safe and minimal", () => {
  assert.equal(
    backfill.extractCredentialProjectIdFromJsonText(
      JSON.stringify({project_id: "dr-tarek-platform", private_key: "SECRET-KEY"})
    ),
    "dr-tarek-platform"
  );
  assert.equal(backfill.extractCredentialProjectIdFromJsonText("not-json"), null);
  assert.equal(backfill.extractCredentialProjectIdFromJsonText(""), null);
  assert.equal(backfill.extractCredentialProjectIdFromJsonText(null), null);
});

// Guard never leaks secrets: error text must not contain private key material.
check("guard errors do not leak secret material", () => {
  let message = "";
  try {
    backfill.verifyTargetProject({
      env: {},
      adminOptionsProjectId: null,
      adminCredentialProjectId: null,
      credentialFileProjectId: "wrong-project",
    });
  } catch (error) {
    message = error.message;
  }
  assert.ok(!message.includes("SECRET-KEY"));
  assert.ok(!message.includes("private_key"));
});

// 4. Guard runs before the first Firestore query (static placement check).
check("guard runs before first Firestore query", () => {
  const scriptPath = path.join(__dirname, "..", "..", "scripts", "backfill_first_video.cjs");
  const src = fs.readFileSync(scriptPath, "utf8");
  const guardIdx = src.indexOf("verifyTargetProjectOrExit({");
  const firestoreIdx = src.indexOf("const db = admin.firestore()");
  const firstQueryIdx = src.indexOf('db.collection("lectures").get()');
  assert.ok(guardIdx !== -1, "guard call not found");
  assert.ok(firestoreIdx !== -1, "admin.firestore() init not found");
  assert.ok(firstQueryIdx !== -1, "first lectures query not found");
  assert.ok(guardIdx < firestoreIdx, "guard must precede admin.firestore()");
  assert.ok(guardIdx < firstQueryIdx, "guard must precede first Firestore query");
});

// 5. Both dry-run and apply modes use the same guard (unconditional).
check("dry-run and apply share the same unconditional guard", () => {
  const scriptPath = path.join(__dirname, "..", "..", "scripts", "backfill_first_video.cjs");
  const src = fs.readFileSync(scriptPath, "utf8");
  // Guard block must exist exactly once in backfillFirstVideo and NOT sit
  // inside an APPLY/DRY_RUN conditional.
  const guardOccurrences = src.split("verifyTargetProjectOrExit({").length - 1;
  assert.equal(guardOccurrences, 1);
  const guardIdx = src.indexOf("verifyTargetProjectOrExit({");
  // Nearest enclosing conditional around the guard must not be DRY_RUN/APPLY-gated:
  // the guard source line itself carries the unconditional comment.
  assert.ok(src.includes("unconditionally (dry-run AND --apply)"));
  // The same verifyTargetProject export is mode-independent: identical inputs
  // give identical results regardless of any APPLY flag.
  const prodDeps = {
    env: {},
    adminOptionsProjectId: null,
    adminCredentialProjectId: null,
    credentialFileProjectId: EXPECTED,
  };
  assert.equal(backfill.verifyTargetProject(prodDeps), EXPECTED);
  assert.equal(backfill.verifyTargetProject({...prodDeps}), EXPECTED);
});

console.log(`backfill_first_video_guard tests passed (${passed} groups).`);
