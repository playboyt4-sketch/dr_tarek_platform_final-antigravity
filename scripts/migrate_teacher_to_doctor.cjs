#!/usr/bin/env node
/**
 * migrate_teacher_to_doctor.cjs — ONE-SHOT Platform Owner role migration
 * (ADR-005): users/{OWNER_UID}.role `teacher` -> `doctor`.
 *
 * Run modes (default is READ-ONLY):
 *   node scripts\migrate_teacher_to_doctor.cjs                 (dry-run report, zero writes)
 *   node scripts\migrate_teacher_to_doctor.cjs --dry-run       (explicit dry-run, zero writes)
 *   node scripts\migrate_teacher_to_doctor.cjs --confirm       (perform the migration writes)
 *   node scripts\migrate_teacher_to_doctor.cjs --rollback --confirm
 *                                                              (doctor -> teacher, UID-gated)
 *
 * Optional identity pins (must match the expected values or the script aborts):
 *   --project <projectId>   (expected: dr-tarek-platform)
 *   --uid <ownerUid>        (expected: 2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2)
 *
 * This file lives in <repo>/scripts/ — OUTSIDE the deployed `functions/`
 * source directory — so it can never be deployed as a callable endpoint.
 *
 * What it changes (and ONLY this), in --confirm mode from State A:
 *   1. users/{uid}                 role: "teacher" -> "doctor" via update({role})
 *                                  (role-only write; every other field is
 *                                  re-read and verified byte-identical).
 *   2. admin_audit_log             one marker doc (Admin SDK write):
 *                                  action "role_migrated_teacher_to_doctor",
 *                                  recorded idempotently (see below).
 *
 * What it NEVER touches: user_secrets/{uid} (password/hash), any other user,
 * any historical audit record, any other collection, any code or config.
 *
 * Custom Claims are NEVER written by this script. Per the authoritative
 * architecture, staff claims are minted from Firestore `users.role` by
 * verifyStaffPassword at staff login, which remains the single source of
 * truth. After the role write, the owner signs out/in to obtain `doctor`
 * claims; the script only READS the Auth record to report claim names.
 *
 * What it NEVER touches: user_secrets/{uid} (password/hash), any other user,
 * any historical audit record, any other collection, any code or config.
 *
 * Safety properties:
 *   - Read-only by default; writes ONLY with explicit --confirm.
 *   - Double confirmation: expected project + expected UID + --confirm.
 *   - UID-gated: refuses any UID other than the expected owner UID.
 *   - Candidate check: aborts unless exactly ONE `role == "teacher"` user
 *     exists and it is the expected UID (no broad destructive queries).
 *   - Idempotent: `role == "doctor"` verifies without rewriting the role;
 *     the audit marker is recorded idempotently too, so a past run that
 *     migrated the role but missed its marker recovers the marker instead
 *     of stranding an unmarked migration (never a permanent
 *     ALREADY-MIGRATED-without-marker state).
 *   - State C (any other role / missing doc) aborts with non-zero exit.
 *   - Post-write re-read verifies role + field preservation.
 *   - No secrets are ever printed (only uid, project, role, claim NAMES).
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS (service-account JSON), same
 * as scripts/bootstrap_teacher.cjs. For isolated tests, point
 * FIRESTORE_EMULATOR_HOST at the emulator (Admin SDK honors it).
 */

"use strict";

const path = require("path");
const fs = require("fs");

const EXPECTED_PROJECT = "dr-tarek-platform";
const EXPECTED_UID = "2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2";
const LEGACY_ROLE = "teacher";
const TARGET_ROLE = "doctor";
const MIGRATION_ID = "adr-005-teacher-to-doctor";
const MARKER_ACTION = "role_migrated_teacher_to_doctor";
const ROLLBACK_MARKER_ACTION = "role_migrated_doctor_to_teacher_rollback";

// ---------------------------------------------------------------------------
// Pure helpers (exported for tests; no Admin SDK / no I/O here).
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    dryRun: false,
    confirm: false,
    rollback: false,
    project: null,
    uid: null,
    help: false,
  };
  for (const arg of argv) {
    if (arg === "--dry-run") opts.dryRun = true;
    else if (arg === "--confirm") opts.confirm = true;
    else if (arg === "--rollback") opts.rollback = true;
    else if (arg === "--help" || arg === "-h") opts.help = true;
    else if (arg.startsWith("--project=")) opts.project = arg.slice("--project=".length);
    else if (arg.startsWith("--uid=")) opts.uid = arg.slice("--uid=".length);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return opts;
}

function usage() {
  return [
    "Usage:",
    "  node scripts\\migrate_teacher_to_doctor.cjs [--dry-run] [--project=<id>] [--uid=<uid>]",
    "  node scripts\\migrate_teacher_to_doctor.cjs --confirm [--project=<id>] [--uid=<uid>]",
    "  node scripts\\migrate_teacher_to_doctor.cjs --rollback --confirm [--project=<id>] [--uid=<uid>]",
    "",
    `Expected project: ${EXPECTED_PROJECT}`,
    `Expected owner UID: ${EXPECTED_UID}`,
    "Default (no flags) is a read-only dry-run. Writes require --confirm.",
  ].join("\n");
}

/**
 * Classify the owner document state.
 * Returns "MIGRATE" | "ALREADY_MIGRATED" | "ROLLBACK" | throws.
 */
function decideState({docExists, role, rollback}) {
  if (!docExists) {
    throw new Error(`ABORT: owner document users/${EXPECTED_UID} does not exist.`);
  }
  if (rollback) {
    if (role === TARGET_ROLE) return "ROLLBACK";
    if (role === LEGACY_ROLE) return "ALREADY_MIGRATED";
    throw new Error(`ABORT: unexpected role "${role}" — refusing rollback.`);
  }
  if (role === LEGACY_ROLE) return "MIGRATE";
  if (role === TARGET_ROLE) return "ALREADY_MIGRATED";
  throw new Error(`ABORT: unexpected role "${role}" — refusing migration.`);
}

/** Keys that must never change on the owner doc: everything but role. */
function preservedFieldDiff(before, after) {
  const diffs = [];
  const keys = new Set([...Object.keys(before || {}), ...Object.keys(after || {})]);
  for (const key of keys) {
    if (key === "role") continue;
    const a = JSON.stringify(before ? before[key] : undefined);
    const b = JSON.stringify(after ? after[key] : undefined);
    if (a !== b) diffs.push(key);
  }
  return diffs;
}

/**
 * Idempotent marker handling. Returns "present" | "recorded" | "would-record".
 * Never rewrites historical records; records at most one marker per action.
 */
async function ensureMarker(deps, uid, action, previousRole, targetRole, writeMode, say) {
  const snap = await deps.db
    .collection("admin_audit_log")
    .where("migration_id", "==", MIGRATION_ID)
    .get();
  const exists = (snap.docs || []).some((d) => {
    const data = typeof d.data === "function" ? d.data() : {};
    return data.target_uid === uid && data.action === action;
  });
  if (exists) {
    say(`audit marker present: ${action}`);
    return "present";
  }
  if (!writeMode) {
    say(`DRY-RUN: would write admin_audit_log marker "${action}"`);
    return "would-record";
  }
  try {
    await deps.db.collection("admin_audit_log").add({
      actor_uid: uid,
      actor_role: targetRole,
      action,
      target_uid: uid,
      target_role: targetRole,
      previous_role: previousRole,
      migration_id: MIGRATION_ID,
      status: "completed",
      created_at: deps.fieldValue.serverTimestamp(),
      updated_at: deps.fieldValue.serverTimestamp(),
      timestamp: deps.fieldValue.serverTimestamp(),
    });
    say(`audit marker recorded: ${action}`);
    return "recorded";
  } catch (error) {
    throw new Error(`MARKER FAILED for "${action}" (${error.message}).`);
  }
}

// ---------------------------------------------------------------------------
// Operator core (deps-injected for tests; real Admin SDK in production).
// ---------------------------------------------------------------------------

async function runOperator(deps, opts, log) {
  const say = log || ((...a) => console.log(...a));
  const project = opts.project || EXPECTED_PROJECT;
  const uid = opts.uid || EXPECTED_UID;
  if (project !== EXPECTED_PROJECT) {
    throw new Error(`ABORT: project "${project}" does not match expected "${EXPECTED_PROJECT}".`);
  }
  if (uid !== EXPECTED_UID) {
    throw new Error("ABORT: UID does not match the expected Platform Owner UID.");
  }
  const writeMode = Boolean(opts.confirm);
  if (opts.rollback && !writeMode) {
    throw new Error("ABORT: --rollback requires --confirm (dry-run performs zero writes).");
  }

  // 1) Read owner document.
  const userRef = deps.db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const docExists = userSnap.exists === true;
  const userData = docExists ? userSnap.data() || {} : {};
  const role = typeof userData.role === "string" ? userData.role : null;
  const state = decideState({docExists, role, rollback: Boolean(opts.rollback)});
  say(`project: ${project}`);
  say(`owner uid: ${uid}`);
  say(`users/${uid}.role: ${role === null ? "(missing)" : JSON.stringify(role)}`);
  say(`state: ${state}`);

  // 2) Candidate check: exactly one legacy-role user, and it is this UID.
  // (Skipped meaningfully only when already migrated; still verified.)
  const legacySnap = await deps.db
    .collection("users")
    .where("role", "==", LEGACY_ROLE)
    .get();
  const legacyIds = (legacySnap.docs || []).map((d) => d.id);
  if (state === "MIGRATE" && (legacyIds.length !== 1 || legacyIds[0] !== uid)) {
    throw new Error(
      `ABORT: expected exactly one "${LEGACY_ROLE}" candidate (${uid}); found ${legacyIds.length}.`,
    );
  }
  if (state === "ROLLBACK" && legacyIds.some((id) => id !== uid)) {
    throw new Error(
      `ABORT: unexpected "${LEGACY_ROLE}" user(s) present; refusing rollback.`,
    );
  }

  // 3) Read Auth record (safe READ ONLY; claims names only in output).
  // Claims are never written here: verifyStaffPassword mints staff claims
  // from users.role at login, which remains the single source of truth.
  let authUser = null;
  try {
    authUser = await deps.auth.getUser(uid);
  } catch (error) {
    throw new Error(`ABORT: Auth user ${uid} is not readable (${error.message}).`);
  }
  const existingClaims = (authUser && authUser.customClaims) || {};
  say(`auth claims present: ${Object.keys(existingClaims).join(", ") || "(none)"}`);

  const targetRole = state === "ROLLBACK" ? LEGACY_ROLE : TARGET_ROLE;
  const markerAction = state === "ROLLBACK" ? ROLLBACK_MARKER_ACTION : MARKER_ACTION;

  if (state === "ALREADY_MIGRATED") {
    // Recovery-safe: a past run may have migrated the role but missed its
    // marker. Never strand that state — ensure exactly one marker.
    const marker = await ensureMarker(deps, uid, markerAction, role, targetRole, writeMode, say);
    if (marker === "recorded") {
      say("RECOVERED: missing audit marker recorded; role was already migrated.");
      return {state, wrote: true, marker};
    }
    say("ALREADY MIGRATED — NO WRITE REQUIRED");
    return {state, wrote: false, marker, dryRun: !writeMode || undefined};
  }

  if (!writeMode) {
    say(`DRY-RUN: would update users/${uid}.role ${JSON.stringify(role)} -> ${JSON.stringify(targetRole)} (role-only write)`);
    say("DRY-RUN: auth claims untouched — staff claims re-mint from users.role at next staff login (sign out/in).");
    await ensureMarker(deps, uid, markerAction, role, targetRole, false, say);
    say("DRY-RUN COMPLETE — ZERO WRITES PERFORMED");
    return {state, wrote: false, dryRun: true};
  }

  // 4) Role-only write.
  const before = JSON.parse(JSON.stringify(userData));
  await userRef.update({role: targetRole});

  // 5) Post-write verification (re-read, never trust the write call).
  const afterSnap = await userRef.get();
  const after = (afterSnap.exists && afterSnap.data()) || {};
  if (after.role !== targetRole) {
    throw new Error(`FAILED: post-write role is ${JSON.stringify(after.role)}, expected ${JSON.stringify(targetRole)}.`);
  }
  const drift = preservedFieldDiff(before, after);
  if (drift.length > 0) {
    throw new Error(`FAILED: protected owner fields changed: ${drift.join(", ")}.`);
  }
  say(`verified: users/${uid}.role == ${JSON.stringify(targetRole)}; all other fields preserved.`);

  // 6) Audit marker, idempotent (Admin SDK write; historical records untouched).
  const marker = await ensureMarker(deps, uid, markerAction, role, targetRole, true, say);
  if (marker !== "recorded" && marker !== "present") {
    throw new Error(`MIGRATION APPLIED BUT MARKER NOT RECORDED; role is ${JSON.stringify(targetRole)}.`);
  }

  say(state === "ROLLBACK" ? "ROLLBACK COMPLETE" : "MIGRATION COMPLETE");
  say("Next: owner signs out/in so staff login mints fresh claims from the migrated role.");
  return {state, wrote: true, marker};
}

// ---------------------------------------------------------------------------
// Production entrypoint (real Admin SDK; never runs on require()).
// ---------------------------------------------------------------------------

function loadAdmin() {
  try {
    const {createRequire} = require("module");
    const functionsRequire = createRequire(path.join(__dirname, "..", "functions", "package.json"));
    return functionsRequire("firebase-admin");
  } catch (error) {
    console.error(
      "Could not load firebase-admin from functions/node_modules.\n" +
        'Run "npm install" inside the functions/ folder first.',
    );
    process.exit(1);
  }
}

function resolveProjectId(opts) {
  if (opts.project) return opts.project;
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"]) {
    if (process.env[key]) return process.env[key];
  }
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyPath) {
    try {
      const parsed = JSON.parse(fs.readFileSync(keyPath, "utf8"));
      if (parsed && typeof parsed.project_id === "string") return parsed.project_id;
    } catch (error) {
      throw new Error(`ABORT: cannot read project_id from service-account key (${error.message}). Pass --project explicitly.`);
    }
  }
  throw new Error(`ABORT: cannot determine project — pass --project=${EXPECTED_PROJECT} explicitly.`);
}

async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(usage());
    return;
  }
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.FIRESTORE_EMULATOR_HOST) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path first\n" +
        "(or FIRESTORE_EMULATOR_HOST for isolated runs).",
    );
    process.exit(1);
  }
  if (opts.confirm && process.stdin.isTTY !== true) {
    console.error("ERROR: --confirm writes require an interactive terminal. Use --dry-run otherwise.");
    process.exit(1);
  }
  const admin = loadAdmin();
  admin.initializeApp();
  const project = resolveProjectId(opts);
  await runOperator(
    {
      db: admin.firestore(),
      auth: admin.auth(),
      fieldValue: admin.firestore.FieldValue,
    },
    {...opts, project},
    console.log.bind(console),
  );
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  EXPECTED_PROJECT,
  EXPECTED_UID,
  LEGACY_ROLE,
  TARGET_ROLE,
  MIGRATION_ID,
  MARKER_ACTION,
  ROLLBACK_MARKER_ACTION,
  parseArgs,
  decideState,
  preservedFieldDiff,
  ensureMarker,
  runOperator,
};
