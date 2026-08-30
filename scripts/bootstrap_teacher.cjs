#!/usr/bin/env node
/**
 * bootstrap_teacher.cjs — ONE-TIME Platform Owner (Teacher) bootstrap.
 *
 * Run locally by the Teacher (Platform Owner) with a service-account key.
 * This file lives at <repo>/scripts/ which is OUTSIDE the deployed
 * `functions/` source directory (firebase.json -> functions.source =
 * "functions"), so it can never be deployed as a callable endpoint. It is
 * a plain script, not an onCall/onRequest handler.
 *
 * What it creates (mirroring registerNewStudent's write pattern exactly):
 *   1. Firebase Auth user          admin.auth().createUser({displayName}) — no email,
 *                                  per the Custom Tokens architecture (FINAL_DECISIONS §3).
 *   2. Custom claims               { role: "teacher", approved: true }   (15 Admin Permissions §2.1)
 *   3. users/{uid}                 role: "teacher", approval_status: "approved",
 *                                  account_status: "active", full 05 Database field set.
 *   4. user_secrets/{uid}          password_hash in the EXACT hashPassword() format of
 *                                  functions/src/index.ts ("scrypt$salt$hash$16384",
 *                                  N=16384 r=8 p=1 keylen=64) — written via one atomic
 *                                  Firestore batch together with the users doc.
 *
 * Safety properties:
 *   - Self-locking: aborts if ANY users doc with role == "teacher" exists.
 *     No delete/recreate convenience is provided on purpose.
 *   - Rollback: if any step after Auth-user creation fails, the Auth user is
 *     deleted so no half-created owner can linger.
 *   - The password is never logged or written anywhere except the scrypt
 *     hash into user_secrets; prompts appear only in this terminal.
 *
 * Credentials: resolved from GOOGLE_APPLICATION_CREDENTIALS (service-account
 * JSON). That path pattern is already git-ignored (.gitignore: serviceAccountKey*.json).
 */

"use strict";

const path = require("path");
const crypto = require("crypto");
const readline = require("readline");

// ---------------------------------------------------------------------------
// Resolve firebase-admin from functions/node_modules so the project root needs
// no extra dependencies and the script stays outside the deployed bundle.
// ---------------------------------------------------------------------------
const functionsPkg = path.join(__dirname, "..", "functions", "package.json");
let admin;
try {
  const { createRequire } = require("module");
  const functionsRequire = createRequire(functionsPkg);
  admin = functionsRequire("firebase-admin");
} catch (error) {
  console.error(
    "Could not load firebase-admin from functions/node_modules.\n" +
      'Run "npm install" inside the functions/ folder first.',
  );
  process.exit(1);
}

// --- Constants mirrored EXACTLY from functions/src/index.ts -----------------
const EGYPT_PHONE_REGEX = /^01[0125][0-9]{8}$/; // index.ts:78
// index.ts:762 (assertStrongPassword :1036 uses this same pattern)
const STRONG_PASSWORD_REGEX =
  /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>_\-+=[\]/\\`~]).{8,}$/;
const SCRYPT_COST = 16384; // hashPassword() index.ts:68-73

function validateInputs({ fullName, displayHandle, phoneNumber, password }) {
  // Null-safe defaults: no code path may ever call .trim() on undefined.
  const errors = [];
  const name = String(fullName ?? "").trim();
  const handle = String(displayHandle ?? "").trim();
  const phoneInput = String(phoneNumber ?? "").trim();
  const pass = String(password ?? "");
  if (name.length < 3 || name.length > 100) {
    // registerNewStudent enforces the same 100-char ceiling (index.ts:680).
    errors.push("full_name must be between 3 and 100 characters.");
  }
  if (handle.length < 3 || handle.length > 60) {
    errors.push("display_handle must be between 3 and 60 characters.");
  }
  if (!EGYPT_PHONE_REGEX.test(phoneInput)) {
    errors.push("phone_number must be a valid Egyptian number (01[0125]XXXXXXXX).");
  }
  if (!STRONG_PASSWORD_REGEX.test(pass)) {
    errors.push(
      "password must contain at least 8 characters including uppercase and lowercase letters, a number, and a special character.",
    );
  }
  return { errors, name, handle, phone: phoneInput };
}

/** Identical to hashPassword() in functions/src/index.ts (:68-73). */
function hashPassword(password) {
  return new Promise((resolve, reject) => {
    const salt = crypto.randomBytes(16);
    crypto.scrypt(
      password,
      salt,
      64,
      { N: SCRYPT_COST, r: 8, p: 1 },
      (error, derivedKey) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(`scrypt$${salt.toString("hex")}$${derivedKey.toString("hex")}$${SCRYPT_COST}`);
      },
    );
  });
}

function ask(rl, question) {
  // readline.Interface.question() is callback-based across Node versions;
  // never await it directly — wrap it in a real Promise. Empty/EOF input
  // resolves to "" so validation reports clean field errors, never crashes.
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(String(answer ?? "").trim());
    });
  });
}

async function main() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      "ERROR: set GOOGLE_APPLICATION_CREDENTIALS to your service-account JSON path first.\n" +
        "Firebase Console -> Project settings -> Service accounts -> Generate new private key.",
    );
    process.exit(1);
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  // Interactive-only script: refuse non-TTY stdin with an actionable message
  // instead of failing later on empty/undefined answers.
  if (process.stdin.isTTY !== true) {
    rl.close();
    console.error(
      "ERROR: this bootstrap must run in an interactive terminal " +
        "(stdin is not a TTY). Open cmd/PowerShell directly and run:\n" +
        "  node scripts\\bootstrap_teacher.cjs",
    );
    process.exit(1);
  }

  console.log("=== Dr. Tarek Platform — one-time Teacher (Platform Owner) bootstrap ===");
  const fullName = await ask(rl, "full_name (this is your LOGIN name): ");
  const displayHandle = await ask(rl, "display_handle (public identity, e.g. Dr/tarekelaraby): ");
  const phoneNumber = await ask(rl, "phone_number (Egypt format 01001234567): ");
  const password = await ask(
    rl,
    "password (8+ chars, upper+lower+digit+special — visible only in this terminal): ",
  );
  rl.close();

  const { errors, name, handle, phone } = validateInputs({
    fullName,
    displayHandle,
    phoneNumber,
    password,
  });
  if (errors.length > 0) {
    errors.forEach((e) => console.error("INVALID: " + e));
    process.exit(1);
  }

  admin.initializeApp();
  const auth = admin.auth();
  const db = admin.firestore();

  // ---- Guard 1: self-locking (Master Architecture §6 — exactly ONE teacher) ----
  const existingTeachers = await db
    .collection("users")
    .where("role", "==", "teacher")
    .limit(1)
    .get();
  if (!existingTeachers.empty) {
    console.error(
      "ABORT: a Teacher account already exists (users/" +
        existingTeachers.docs[0].id +
        "). This bootstrap can only ever run once.",
    );
    process.exit(1);
  }

  // ---- Guard 2: display_handle uniqueness (same check as the callable:
  //      trimmed exact match, index.ts:1875-1878) ----
  const handleSnap = await db
    .collection("users")
    .where("display_handle", "==", handle)
    .limit(2)
    .get();
  if (!handleSnap.empty) {
    console.error("ABORT: display_handle is already taken by another user.");
    process.exit(1);
  }

  let authUser = null;
  try {
    // 1) Auth user — mirrors registerNewStudent (no email, Custom Tokens flow).
    authUser = await auth.createUser({ displayName: name });

    // 2) Claims (15 §2.1: role:"teacher", approved:true).
    await auth.setCustomUserClaims(authUser.uid, { role: "teacher", approved: true });

    // 3) Atomic Firestore writes: users + user_secrets in ONE batch.
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    batch.set(db.collection("users").doc(authUser.uid), {
      id: authUser.uid,
      full_name: name,
      display_handle: handle,
      profile_photo: "",
      phone_number: phone,
      role: "teacher",
      student_type: null,
      grade: null,
      custom_group_id: null,
      custom_group_name: null,
      approval_status: "approved",
      account_status: "active",
      current_device_id: null,
      password_last_changed_at: now,
      force_password_change: false,
      is_deleted: false,
      deleted_at: null,
      deleted_by: null,
      created_at: now,
      updated_at: now,
      created_by: "bootstrap",
      updated_by: "bootstrap",
    });
    batch.set(db.collection("user_secrets").doc(authUser.uid), {
      user_id: authUser.uid,
      password_hash: await hashPassword(password),
      created_at: now,
      updated_at: now,
    });
    await batch.commit();

    console.log("");
    console.log("SUCCESS — Platform Owner created.");
    console.log("  Auth UID       :", authUser.uid);
    console.log("  Login name     :", name, "(type THIS on login screens)");
    console.log("  display_handle :", handle, "(public identity only — NOT a credential)");
    console.log("The script is now permanently locked for this project.");
  } catch (error) {
    console.error("FAILED:", error.message);
    if (authUser) {
      // Roll back the Auth user so no inconsistent half-owner remains
      // (same cleanup discipline as registerNewStudent's error path).
      try {
        await auth.deleteUser(authUser.uid);
        console.error("Rolled back the partially created Auth user:", authUser.uid);
      } catch (rollbackError) {
        console.error(
          "CRITICAL: rollback failed — manually delete Auth UID:",
          authUser.uid,
          "(" + rollbackError.message + ")",
        );
      }
    }
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("Bootstrap failed:", error.message);
  process.exitCode = 1;
});
