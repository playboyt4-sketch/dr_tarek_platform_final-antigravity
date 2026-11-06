#!/usr/bin/env node
/**
 * student_cleanup.cjs — pre-onboarding test-student deactivation.
 *
 * Deactivates every existing test student account and soft-deletes its
 * student-owned operational data, while preserving the Doctor (Platform
 * Owner), every Admin, shared academic content, and all audit/security
 * history.
 *
 * Policy (approved): Soft Delete + Auth deactivation. Nothing is hard
 * deleted. `users.phone_number` is intentionally retained on the deactivated
 * row for audit; uniqueness code treats `is_deleted == true` as released so a
 * real student can register the same number.
 *
 * Usage:
 *   node scripts\student_cleanup.cjs --doctor-uid <uid>                     (DRY-RUN)
 *   node scripts\student_cleanup.cjs --doctor-uid <uid> --apply ^
 *        --backup-dir "D:\Temp\dr_tarek_student_cleanup_<ts>"               (WRITE)
 *
 * Flags:
 *   --doctor-uid <uid>      REQUIRED. Must be the unique role="doctor" account.
 *   --backup-dir <path>     REQUIRED with --apply. Full pre-state backup
 *                           (Auth users, users, secrets, linked docs) is
 *                           written OUTSIDE the repository before any write.
 *   --apply                 Perform writes. Default is read-only dry-run.
 *   --skip-orphan-auth      Do not disable Auth-only accounts that have no
 *                           Firestore profile (default: disable them).
 *
 * Safety:
 *   - Refuses any project except dr-tarek-platform (credential + Admin SDK).
 *   - Aborts without writing if the Doctor identity is missing/ambiguous,
 *     if the explicit UID does not match, or if any target has a payment or
 *     financial relationship.
 *   - Never writes to analytics_events, security_events,
 *     auth_security_events, admin_audit_log (only appends an audit entry),
 *     user_secrets, or shared content collections.
 *   - Idempotent: re-runs skip already-deactivated accounts/docs.
 *   - Prints UIDs, counts, and masked phones only. Never prints secrets,
 *     hashes, tokens, or full phone numbers.
 *
 * Credentials:
 *   set GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

let admin;
try {
  const {createRequire} = require("node:module");
  const repoRequire = createRequire(path.join(__dirname, "..", "functions", "package.json"));
  admin = repoRequire("firebase-admin");
} catch (error) {
  console.error("Could not load firebase-admin from functions/node_modules. Run npm install in functions/ first.");
  process.exit(1);
}

const {
  EXPECTED_PROJECT_ID,
  BATCH_LIMIT,
  normalizeProjectId,
  readCredentialFileProjectId,
  verifyTargetProjectOrExit,
} = require("./backfill_first_video.cjs");

const APPLY = process.argv.includes("--apply");
const DRY_RUN = !APPLY;
const SKIP_ORPHAN_AUTH = process.argv.includes("--skip-orphan-auth");

function argValue(flag) {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? String(process.argv[index + 1] ?? "").trim() : "";
}

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function log(message) {
  console.log(message);
}

function maskPhone(value) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text) return null;
  if (text.length <= 6) return "***";
  return `${text.slice(0, 3)}***${text.slice(-2)}`;
}

function sha256(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function writeJson(dir, name, value, manifest) {
  const file = path.join(dir, name);
  const text = JSON.stringify(value, null, 2);
  fs.writeFileSync(file, text, "utf8");
  manifest.push({file: name, bytes: Buffer.byteLength(text), sha256: sha256(text)});
}

function chunk(values, size) {
  const out = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

function normalizeRole(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

const STUDENT_ROLES = new Set(["student", "new_student"]);
const STAFF_ROLES = new Set(["doctor", "admin"]);

/**
 * Collections whose documents belong to a single student. `mode` decides the
 * soft-delete shape. Audit/security/analytics and shared content are
 * deliberately absent.
 */
const LINKED_COLLECTIONS = [
  {name: "devices", field: "user_id", mode: "soft"},
  {name: "notifications", field: "user_id", mode: "soft"},
  {name: "device_security_alerts", field: "user_id", mode: "soft"},
  {name: "lecture_progress", field: "student_id", mode: "soft"},
  {name: "learning_progress", field: "student_id", mode: "soft"},
  {name: "subject_progress_summary", field: "student_id", mode: "soft"},
  {name: "subscriptions", field: "student_id", mode: "soft"},
  {name: "notes", field: "student_id", mode: "soft"},
  {name: "bookmarks", field: "student_id", mode: "soft"},
  {name: "quiz_attempts", field: "student_id", mode: "soft"},
  {name: "exam_attempts", field: "student_id", mode: "soft"},
  {name: "student_questions", field: "student_id", mode: "soft"},
  {name: "chat_rooms", field: "student_id", mode: "soft"},
  {name: "playback_sessions", field: "student_id", mode: "soft"},
  {name: "device_change_requests", field: "student_id", mode: "soft"},
  {name: "registration_requests", field: "student_id", mode: "soft"},
  {name: "student_subject_pricing", field: "student_id", mode: "soft"},
  {name: "subject_access_assignments", field: "student_id", mode: "access"},
  {name: "subject_device_authorizations", field: "student_id", mode: "deviceauth"},
  {name: "lecture_access_grants", field: "student_id", mode: "grant"},
  {name: "password_reset_requests", field: "student_id", mode: "reset"},
  {name: "video_watch_windows", field: "user_id", mode: "window"},
];

const PRESERVED_COLLECTIONS = [
  "analytics_events",
  "security_events",
  "auth_security_events",
  "admin_audit_log",
  "admin_permissions",
  "user_secrets",
];

function plannedUserUpdate() {
  return {
    is_deleted: true,
    account_status: "disabled",
    current_device_id: null,
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: ACTOR_UID,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_by: ACTOR_UID,
  };
}

let ACTOR_UID = "";

/**
 * @param {string} mode linked collection mode
 * @param {object} data existing document data
 * @return {object|null} fields to update, or null when already handled
 */
function plannedLinkedUpdate(mode, data) {
  const existing = data && typeof data === "object" ? data : {};
  if (mode === "window") {
    const expiry = existing.window_expires_at;
    const expiryMs = expiry && typeof expiry.toMillis === "function" ? expiry.toMillis() : 0;
    if (expiryMs > 0 && expiryMs <= Date.now()) return null;
    return {window_expires_at: admin.firestore.Timestamp.fromMillis(0)};
  }
  if (existing.is_deleted === true) return null;

  const common = {
    is_deleted: true,
    deleted_at: admin.firestore.FieldValue.serverTimestamp(),
    deleted_by: ACTOR_UID,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_by: ACTOR_UID,
  };
  if (mode === "access") return {...common, enabled: false};
  if (mode === "grant") return {...common, allowed: false};
  if (mode === "deviceauth") {
    return {
      ...common,
      status: "revoked",
      revoked_at: admin.firestore.FieldValue.serverTimestamp(),
      revoked_by: ACTOR_UID,
      revoke_reason: "account_deactivated",
    };
  }
  if (mode === "reset") {
    const update = {...common};
    if (existing.status === "pending") update.status = "cancelled";
    return update;
  }
  return common;
}

async function loadAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function main() {
  const doctorUidArg = argValue("--doctor-uid");
  const backupDirArg = argValue("--backup-dir");

  if (!doctorUidArg) fail("--doctor-uid <uid> is required (explicit protected allowlist).");
  if (APPLY && !backupDirArg) fail("--backup-dir <path> is required with --apply.");

  const usingEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  if (!usingEmulator && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    fail("set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path first.");
  }
  if (admin.apps.length === 0) {
    if (usingEmulator) admin.initializeApp();
    else admin.initializeApp({projectId: EXPECTED_PROJECT_ID});
  }
  {
    const appOptions = (admin.app() && admin.app().options) || {};
    const adminOptionsProjectId = normalizeProjectId(appOptions.projectId);
    let adminCredentialProjectId = null;
    try {
      adminCredentialProjectId = normalizeProjectId(appOptions.credential && appOptions.credential.projectId);
    } catch {
      adminCredentialProjectId = null;
    }
    verifyTargetProjectOrExit({
      env: process.env,
      adminOptionsProjectId,
      adminCredentialProjectId,
      credentialFileProjectId: readCredentialFileProjectId(process.env.GOOGLE_APPLICATION_CREDENTIALS),
    });
  }

  const db = admin.firestore();
  const auth = admin.auth();

  log(`=== test-student cleanup (${DRY_RUN ? "DRY-RUN" : "APPLY"}) ===`);
  log(`project: ${EXPECTED_PROJECT_ID}`);

  // ---------- 1. Load all identities (read-only) ----------
  const [usersSnap, authUsers] = await Promise.all([
    db.collection("users").get(),
    loadAuthUsers(auth),
  ]);
  const userDocs = new Map(usersSnap.docs.map((doc) => [doc.id, doc]));
  const authById = new Map(authUsers.map((user) => [user.uid, user]));

  // ---------- 2. Verify Doctor identity (hard stop on ambiguity) ----------
  const doctorDocs = usersSnap.docs.filter((doc) => normalizeRole(doc.data()?.role) === "doctor");
  if (doctorDocs.length === 0) fail("No role=doctor account found. Cleanup aborted.");
  if (doctorDocs.length > 1) {
    fail(`Expected exactly one Doctor, found ${doctorDocs.length}. Ambiguous identity; cleanup aborted.`);
  }
  const doctorDoc = doctorDocs[0];
  if (doctorDoc.id !== doctorUidArg) {
    fail(`--doctor-uid does not match the unique Doctor account. Cleanup aborted.`);
  }
  const doctorData = doctorDoc.data() ?? {};
  if (doctorData.is_deleted === true) fail("Doctor account is soft-deleted. Cleanup aborted.");
  if (doctorData.account_status && doctorData.account_status !== "active") {
    fail("Doctor account is not active. Cleanup aborted.");
  }
  const doctorAuth = authById.get(doctorUidArg);
  if (!doctorAuth) fail("Doctor has no Firebase Auth account. Cleanup aborted.");
  if (doctorAuth.disabled === true) fail("Doctor Auth account is disabled. Cleanup aborted.");
  const doctorClaims = doctorAuth.customClaims ?? {};
  if (doctorClaims.role && normalizeRole(doctorClaims.role) !== "doctor") {
    fail("Doctor stored claims role does not match role=doctor. Cleanup aborted.");
  }
  ACTOR_UID = doctorUidArg;
  log(`Doctor verified: ${doctorUidArg}`);

  // ---------- 3. Protected allowlist (Doctor + all Admins) ----------
  const protectedUids = new Set([doctorUidArg]);
  for (const doc of usersSnap.docs) {
    if (STAFF_ROLES.has(normalizeRole(doc.data()?.role))) protectedUids.add(doc.id);
  }
  for (const user of authUsers) {
    if (STAFF_ROLES.has(normalizeRole(user.customClaims?.role))) protectedUids.add(user.uid);
  }
  const adminUids = [...protectedUids].filter((uid) => uid !== doctorUidArg);
  log(`protected allowlist: ${protectedUids.size} account(s) (1 Doctor + ${adminUids.length} Admin/staff)`);

  // ---------- 4. Select test-student targets ----------
  const studentDocs = usersSnap.docs.filter(
    (doc) => STUDENT_ROLES.has(normalizeRole(doc.data()?.role)) && doc.data()?.is_deleted !== true,
  );
  const targets = [];
  for (const doc of studentDocs) {
    if (protectedUids.has(doc.id)) fail(`Protected UID ${doc.id} matched a student target. Cleanup aborted.`);
    const data = doc.data() ?? {};
    const authUser = authById.get(doc.id) ?? null;
    targets.push({
      uid: doc.id,
      kind: "student",
      role: normalizeRole(data.role),
      fullName: data.full_name ?? "",
      phoneMasked: maskPhone(data.phone_number),
      hasAuth: !!authUser,
      authDisabled: authUser?.disabled === true,
      hasFirestoreUser: true,
      firestoreData: data,
    });
  }

  const orphanAuthUsers = authUsers.filter(
    (user) => !userDocs.has(user.uid) &&
      !protectedUids.has(user.uid) &&
      !STAFF_ROLES.has(normalizeRole(user.customClaims?.role)) &&
      user.disabled !== true,
  );
  if (!SKIP_ORPHAN_AUTH) {
    for (const user of orphanAuthUsers) {
      targets.push({
        uid: user.uid,
        kind: "orphan_auth",
        role: normalizeRole(user.customClaims?.role) || null,
        fullName: user.displayName ?? "",
        phoneMasked: maskPhone(user.phoneNumber),
        hasAuth: true,
        authDisabled: false,
        hasFirestoreUser: false,
        firestoreData: null,
      });
    }
  }

  if (targets.length === 0) {
    log("No live test-student or orphan Auth accounts found. Nothing to do.");
    return;
  }

  log(`targets: ${targets.length} (student profiles ${targets.filter((t) => t.kind === "student").length}, orphan Auth ${targets.filter((t) => t.kind === "orphan_auth").length})`);
  for (const target of targets) {
    log(`  - ${target.uid} role=${target.role ?? "unknown"} name="${target.fullName}" phone=${target.phoneMasked ?? "-"} auth=${target.hasAuth ? (target.authDisabled ? "already-disabled" : "active") : "missing"}`);
  }

  // ---------- 5. Financial / staff-permission safety gates ----------
  for (const target of targets) {
    if (target.kind !== "student") continue;
    const [payments, financial, permissions] = await Promise.all([
      db.collection("payment_logs").where("student_id", "==", target.uid).limit(1).get(),
      db.collection("student_financial_accounts").doc(target.uid).get(),
      db.collection("admin_permissions").doc(target.uid).get(),
    ]);
    if (!payments.empty || (financial.exists && financial.data()?.is_deleted !== true)) {
      fail(`Student ${target.uid} has payment/financial records. Cleanup aborted (manual review required).`);
    }
    if (permissions.exists && permissions.data()?.is_active === true) {
      fail(`Student ${target.uid} holds an active admin permission grant. Cleanup aborted.`);
    }
  }

  // ---------- 6. Build linked-document plan ----------
  const targetUids = targets.filter((t) => t.hasFirestoreUser).map((t) => t.uid);
  const linkedDocs = [];
  const perCollection = {};
  for (const mapping of LINKED_COLLECTIONS) {
    perCollection[mapping.name] = {scanned: 0, pending: 0, already: 0, ids: []};
    for (const ids of chunk(targetUids, 10)) {
      if (ids.length === 0) break;
      let snap;
      try {
        snap = await db.collection(mapping.name).where(mapping.field, "in", ids).get();
      } catch (error) {
        perCollection[mapping.name].error = error?.message ?? String(error);
        break;
      }
      for (const doc of snap.docs) {
        perCollection[mapping.name].scanned += 1;
        const update = plannedLinkedUpdate(mapping.mode, doc.data() ?? {});
        if (update === null) {
          perCollection[mapping.name].already += 1;
          continue;
        }
        perCollection[mapping.name].pending += 1;
        perCollection[mapping.name].ids.push(doc.id);
        linkedDocs.push({collection: mapping.name, id: doc.id, ref: doc.ref, update, data: doc.data() ?? {}});
      }
    }
  }

  // Derived child rows (replies/messages) are soft-deleted only when their
  // parent student-owned row belongs to a target.
  const derived = [];
  const questionDocs = linkedDocs.filter((row) => row.collection === "student_questions");
  for (const ids of chunk(questionDocs.map((row) => row.id), 10)) {
    if (ids.length === 0) break;
    const snap = await db.collection("student_question_replies").where("question_id", "in", ids).get();
    for (const doc of snap.docs) {
      const update = plannedLinkedUpdate("soft", doc.data() ?? {});
      if (update) derived.push({collection: "student_question_replies", id: doc.id, ref: doc.ref, update, data: doc.data() ?? {}});
    }
  }
  const roomDocs = linkedDocs.filter((row) => row.collection === "chat_rooms");
  for (const ids of chunk(roomDocs.map((row) => row.id), 10)) {
    if (ids.length === 0) break;
    const snap = await db.collection("chat_messages").where("room_id", "in", ids).get();
    for (const doc of snap.docs) {
      const update = plannedLinkedUpdate("soft", doc.data() ?? {});
      if (update) derived.push({collection: "chat_messages", id: doc.id, ref: doc.ref, update, data: doc.data() ?? {}});
    }
  }
  linkedDocs.push(...derived);
  if (derived.length > 0) {
    perCollection.student_question_replies = {scanned: derived.filter((d) => d.collection === "student_question_replies").length, pending: derived.filter((d) => d.collection === "student_question_replies").length, already: 0, ids: []};
    perCollection.chat_messages = {scanned: derived.filter((d) => d.collection === "chat_messages").length, pending: derived.filter((d) => d.collection === "chat_messages").length, already: 0, ids: []};
  }

  const userUpdates = targets.filter((t) => t.kind === "student").map((target) => ({
    collection: "users",
    id: target.uid,
    ref: db.collection("users").doc(target.uid),
    update: plannedUserUpdate(),
    data: target.firestoreData,
  }));

  log("--- planned Firestore changes by collection ---");
  for (const [name, info] of Object.entries(perCollection)) {
    log(`  ${name}: scan ${info.scanned}, to soft-delete ${info.pending}, already handled ${info.already}${info.error ? `, ERROR ${info.error}` : ""}`);
  }
  log(`  users: to deactivate ${userUpdates.length}`);
  const totalWrites = userUpdates.length + linkedDocs.length;
  log(`total Firestore documents to update: ${totalWrites}`);

  if (DRY_RUN) {
    if (backupDirArg) {
      fs.mkdirSync(backupDirArg, {recursive: true});
      const manifest = [];
      writeJson(backupDirArg, "dry_run_plan.json", {
        generatedAt: new Date().toISOString(),
        project: EXPECTED_PROJECT_ID,
        doctorUid: doctorUidArg,
        protectedUids: [...protectedUids],
        targets: targets.map((t) => ({
          uid: t.uid, kind: t.kind, role: t.role, fullName: t.fullName,
          phoneMasked: t.phoneMasked, hasAuth: t.hasAuth, authDisabled: t.authDisabled,
        })),
        perCollection,
        userUpdateIds: userUpdates.map((row) => row.id),
        linkedDocIds: linkedDocs.map((row) => ({collection: row.collection, id: row.id})),
      }, manifest);
      writeJson(backupDirArg, "manifest.json", {
        generatedAt: new Date().toISOString(), project: EXPECTED_PROJECT_ID, files: manifest,
      }, []);
      log(`dry-run plan written to ${backupDirArg}`);
    }
    log("DRY-RUN complete. No Auth or Firestore writes were performed.");
    return;
  }

  // ---------- 7. Mandatory backup BEFORE any write ----------
  const backupDir = path.resolve(backupDirArg);
  fs.mkdirSync(backupDir, {recursive: true});
  const manifest = [];
  const targetSet = new Set(targets.map((t) => t.uid));
  writeJson(backupDir, "auth_users.json", authUsers.map((u) => u.toJSON()), manifest);
  writeJson(backupDir, "users.json", usersSnap.docs.map((d) => ({id: d.id, data: d.data() ?? {}})), manifest);
  writeJson(backupDir, "doctor.json", {uid: doctorDoc.id, data: doctorData, claims: doctorClaims}, manifest);

  const secrets = [];
  for (const uid of targetSet) {
    const snap = await db.collection("user_secrets").doc(uid).get();
    if (snap.exists) secrets.push({id: uid, data: snap.data() ?? {}});
  }
  writeJson(backupDir, "user_secrets.json", secrets, manifest);
  writeJson(backupDir, "linked_documents.json", linkedDocs.map((row) => ({
    collection: row.collection, id: row.id, data: row.data,
  })), manifest);
  writeJson(backupDir, "users_to_update.json", userUpdates.map((row) => ({id: row.id, data: row.data})), manifest);
  writeJson(backupDir, "manifest.json", {
    generatedAt: new Date().toISOString(),
    project: EXPECTED_PROJECT_ID,
    doctorUid: doctorUidArg,
    protectedUids: [...protectedUids],
    targetUids: [...targetSet],
    files: manifest,
  }, []);
  log(`backup written to ${backupDir} (${manifest.length} files, verified-by-hash manifest)`);

  // ---------- 8. Deactivate Auth first (immediate access stop) ----------
  const authResults = [];
  for (const target of targets) {
    if (!target.hasAuth) {
      authResults.push({uid: target.uid, status: "no_auth"});
      continue;
    }
    if (target.authDisabled) {
      authResults.push({uid: target.uid, status: "already_disabled"});
      continue;
    }
    try {
      await auth.updateUser(target.uid, {disabled: true});
      await auth.revokeRefreshTokens(target.uid);
      authResults.push({uid: target.uid, status: "disabled"});
    } catch (error) {
      authResults.push({uid: target.uid, status: "error", error: error?.message ?? String(error)});
    }
  }
  log(`Auth deactivated: ${authResults.filter((r) => r.status === "disabled").length}, already disabled: ${authResults.filter((r) => r.status === "already_disabled").length}, errors: ${authResults.filter((r) => r.status === "error").length}`);

  // ---------- 9. Soft-delete Firestore data ----------
  const ops = [...userUpdates, ...linkedDocs];
  let written = 0;
  for (let i = 0; i < ops.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const row of ops.slice(i, i + BATCH_LIMIT)) batch.update(row.ref, row.update);
    await batch.commit();
    written += Math.min(BATCH_LIMIT, ops.length - i);
    log(`  ...committed ${written}/${ops.length} Firestore updates`);
  }

  // ---------- 10. Audit trail (append-only) ----------
  let auditBatch = db.batch();
  let auditOps = 0;
  const flushAudit = async () => {
    if (auditOps === 0) return;
    await auditBatch.commit();
    auditBatch = db.batch();
    auditOps = 0;
  };
  for (const target of targets) {
    const targetLinkedCount = linkedDocs.filter((row) => row.data &&
      (Object.values(row.data).includes(target.uid))).length;
    auditBatch.set(db.collection("admin_audit_log").doc(), {
      action: target.kind === "student" ? "test_student_account_deactivated" : "orphan_test_auth_deactivated",
      entity: "user",
      target_id: target.uid,
      target_role: target.role,
      reason: "pre_onboarding_test_account_cleanup",
      policy: "soft_delete_90_day_retention",
      linked_documents_updated: targetLinkedCount,
      actor_id: doctorUidArg,
      actor_role: "doctor",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    auditOps += 1;
    if (auditOps >= BATCH_LIMIT) await flushAudit();
  }
  auditBatch.set(db.collection("admin_audit_log").doc(), {
    action: "test_student_cleanup_summary",
    entity: "platform",
    target_id: "test_student_cleanup",
    accounts_deactivated: targets.length,
    firestore_documents_updated: written,
    per_collection: Object.fromEntries(Object.entries(perCollection).map(([k, v]) => [k, v.pending])),
    actor_id: doctorUidArg,
    actor_role: "doctor",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
  auditOps += 1;
  await flushAudit();
  log("audit entries appended to admin_audit_log");

  // ---------- 11. Post-apply verification ----------
  let verificationOk = true;
  const [doctorAfter, usersAfter, authAfter] = await Promise.all([
    db.collection("users").doc(doctorUidArg).get(),
    db.collection("users").get(),
    loadAuthUsers(auth),
  ]);
  const doctorAfterData = doctorAfter.data() ?? {};
  if (!doctorAfter.exists || doctorAfterData.is_deleted === true || doctorAfterData.account_status !== "active") {
    verificationOk = false;
    console.error("VERIFY FAILED: Doctor account is not intact.");
  }
  const authAfterById = new Map(authAfter.map((u) => [u.uid, u]));
  const doctorAuthAfter = authAfterById.get(doctorUidArg);
  if (!doctorAuthAfter || doctorAuthAfter.disabled === true) {
    verificationOk = false;
    console.error("VERIFY FAILED: Doctor Auth account is disabled/missing.");
  }
  for (const uid of adminUids) {
    const adminDoc = usersAfter.docs.find((d) => d.id === uid);
    if (adminDoc && adminDoc.data()?.is_deleted === true) {
      verificationOk = false;
      console.error(`VERIFY FAILED: protected Admin ${uid} was modified.`);
    }
    if (authAfterById.get(uid)?.disabled === true) {
      verificationOk = false;
      console.error(`VERIFY FAILED: protected Admin ${uid} Auth was disabled.`);
    }
  }
  const liveStudentUids = usersAfter.docs
    .filter((d) => STUDENT_ROLES.has(normalizeRole(d.data()?.role)) && d.data()?.is_deleted !== true)
    .map((d) => d.id);
  const remainingTargets = liveStudentUids.filter((uid) => targetSet.has(uid));
  if (remainingTargets.length > 0) {
    verificationOk = false;
    console.error(`VERIFY FAILED: ${remainingTargets.length} target student(s) still live.`);
  }
  const stillEnabled = [...targetSet].filter((uid) => authAfterById.get(uid)?.disabled !== true && authAfterById.has(uid));
  if (stillEnabled.length > 0) {
    verificationOk = false;
    console.error(`VERIFY FAILED: ${stillEnabled.length} target Auth account(s) still enabled.`);
  }
  if (!verificationOk) process.exitCode = 1;

  log("=== cleanup summary ===");
  log(`accounts deactivated: ${targets.length}`);
  log(`Firestore documents soft-deleted: ${written}`);
  log(`live student profiles remaining: ${liveStudentUids.length}`);
  log(`Doctor intact: ${doctorAfter.exists && doctorAfterData.is_deleted !== true}`);
  log(`Admin/staff preserved: ${adminUids.length}`);
  log(verificationOk ? "APPLY verification: PASS" : "APPLY verification: FAIL");
}

module.exports = {plannedLinkedUpdate};

if (require.main === module) {
  main().catch((error) => {
    console.error(`ERROR: ${error?.message ?? error}`);
    process.exitCode = 1;
  });
}
