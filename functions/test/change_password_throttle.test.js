/**
 * change_password_throttle.test.js — per-user throttle for the authenticated
 * changePassword flow (approved: max 5 failed attempts, 6th rejected,
 * existing 10-minute ladder duration, dedicated scope).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1-5.  wrong current password x5 -> permission-denied (allowed+recorded)
 *  6.    6th wrong current password -> resource-exhausted (throttled)
 *  7.    lock duration follows the existing ladder (~10 minutes for 5 fails)
 *  8.    expired lock -> allowed again
 *  9.    correct current password succeeds when not locked
 *  10.   success clears ONLY the changePassword throttle (login scopes kept)
 *  11.   student login throttle state unaffected
 *  12.   weak new password -> invalid-argument, consumes nothing
 *  13.   unauthenticated request consumes nothing
 *  14-16. existing behavior intact: {success:true}, Auth/hash/claims/doc
 *         rotation, force_password_change cleared, claims merged
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};
const DELETE = { __delete: true };

// Captured Auth/Firestore writes for behavior assertions.
const captured = {
  updateUser: [],
  setCustomUserClaims: [],
  usersUpdate: [],
  notifications: [],
};

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (options && options.merge && store[key] !== undefined) {
        const merged = { ...store[key] };
        for (const [k, v] of Object.entries(data)) {
          if (v && v.__delete) delete merged[k];
          else merged[k] = v;
        }
        store[key] = merged;
      } else {
        store[key] = { ...data };
      }
    },
    update: async (data) => {
      if (collPath === "users") captured.usersUpdate.push({ docId, data });
    },
    delete: async () => {
      delete store[key];
    },
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      where: () => ({
        limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
        get: async () => ({ empty: true, docs: [] }),
      }),
      doc: (docId) => docRef(collPath, docId),
      add: async (data) => {
        if (collPath === "notifications") captured.notifications.push(data);
        return {};
      },
    }),
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => DELETE },
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async (uid, props) => {
      captured.updateUser.push({ uid, props });
    },
    getUser: async (uid) => ({
      customClaims: store[`claims_${uid}`] ?? { role: "student", approved: true },
    }),
    setCustomUserClaims: async (uid, claims) => {
      captured.setCustomUserClaims.push({ uid, claims });
    },
    createCustomToken: async () => "mock-token",
    createUser: async () => ({ uid: "new-uid" }),
  }),
  getMessaging: () => ({}),
  getStorage: () => ({}),
};

const Module = require("node:module");
const originalRequire = Module.prototype.require;
Module.prototype.require = function (id) {
  if (id === "firebase-admin/firestore") {
    return {
      getFirestore: adminMock.getFirestore,
      FieldValue: adminMock.FieldValue,
      Timestamp: adminMock.Timestamp,
    };
  }
  if (id === "firebase-admin/auth") return { getAuth: adminMock.getAuth };
  if (id === "firebase-admin/messaging") return { getMessaging: adminMock.getMessaging };
  if (id === "firebase-admin/storage") return { getStorage: adminMock.getStorage };
  if (id === "firebase-admin/app") return { initializeApp: adminMock.initializeApp };
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const changePassword = test.wrap(functions.changePassword);

// Fixture scrypt hash for password "Correct1!" in stored format.
function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

function throttleDocId(scope, key) {
  return crypto.createHash("sha256").update(`${scope}:${key}`).digest("hex");
}

const UID = "user-1";
const STRONG_NEW = "NewPass1!";

async function attempt(uid, currentPassword, newPassword) {
  return changePassword({
    data: { currentPassword, newPassword: newPassword || STRONG_NEW },
    auth: uid ? { uid } : null,
  });
}

async function run() {
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };
  const fail = (name, detail) => {
    console.error(`FAIL - ${name}: ${detail}`);
    process.exitCode = 1;
  };

  store["user_secrets/user-1"] = { password_hash: fixtureHash("Correct1!") };

  // 1-5: five wrong attempts are processed (generic error, not throttled).
  for (let i = 0; i < 5; i++) {
    try {
      await attempt(UID, "Wrong1!");
      fail(`wrong${i + 1}`, "expected failure, got success");
    } catch (err) {
      if (err.code === "resource-exhausted") {
        fail(`wrong${i + 1}`, `throttled too early: ${err.message}`);
      } else if (err.code !== "permission-denied" || err.message !== "Current password is incorrect.") {
        fail(`wrong${i + 1}`, `unexpected ${err.code}: ${err.message}`);
      } else if (i === 0) {
        ok("wrong1/5 -> permission-denied, generic message preserved");
      } else {
        ok(`wrong${i + 1}/5 -> permission-denied (not throttled)`);
      }
    }
  }

  // 6: sixth wrong attempt -> throttled.
  try {
    await attempt(UID, "Wrong1!");
    fail("wrong6", "expected throttle, got success");
  } catch (err) {
    if (err.code === "resource-exhausted") ok("wrong6/5 -> resource-exhausted (throttled)");
    else fail("wrong6", `expected resource-exhausted, got ${err.code}`);
  }

  // 7: lock duration follows the existing ladder (5 fails -> ~10 minutes).
  const doc = store[`login_throttle/${throttleDocId("change_password", UID)}`];
  const remainingMs = doc.locked_until.toMillis() - Date.now();
  if (remainingMs > 9 * 60 * 1000 && remainingMs <= 10 * 60 * 1000) {
    ok(`lock duration ~10min ladder (${Math.round(remainingMs / 1000)}s remaining)`);
  } else {
    fail("duration", `expected ~10min, got ${remainingMs}ms`);
  }

  // 8: expired lock -> allowed again (processed, not throttled).
  store[`login_throttle/${throttleDocId("change_password", UID)}`] = {
    ...doc,
    locked_until: { toMillis: () => Date.now() - 1000, toDate: () => new Date(Date.now() - 1000) },
  };
  try {
    await attempt(UID, "Wrong1!");
    fail("expired", "expected failure, got success");
  } catch (err) {
    if (err.code === "resource-exhausted") fail("expired", "still throttled after expiry");
    else if (err.code === "permission-denied") ok("expired lock -> processed again");
    else fail("expired", `unexpected code ${err.code}`);
  }

  // 9/14/15/16: fresh user, correct current password succeeds with intact
  // behavior (Auth/hash/claims/doc rotation, flag cleared, claims merged).
  const UID2 = "user-2";
  store["user_secrets/user-2"] = {
    password_hash: fixtureHash("Correct1!"),
    failed_login_attempts: 2,
  };
  // Seed unrelated throttle state that success must NOT clear.
  store[`login_throttle/${throttleDocId("student_login_ip", "9.9.9.9")}`] = {
    scope: "student_login_ip",
    fail_count: 4,
  };
  try {
    const res = await changePassword({
      data: { currentPassword: "Correct1!", newPassword: STRONG_NEW },
      auth: { uid: UID2 },
    });
    if (res && res.success === true) ok("correct current password succeeds when not locked");
    else fail("success", `unexpected result ${JSON.stringify(res)}`);
  } catch (err) {
    fail("success", `unexpected ${err.code}: ${err.message}`);
  }

  const updated = captured.updateUser.find((c) => c.uid === UID2);
  if (updated && updated.props.password === STRONG_NEW) ok("Auth password rotated");
  else fail("Auth rotation", JSON.stringify(updated));

  const claims = captured.setCustomUserClaims.find((c) => c.uid === UID2);
  if (claims && claims.claims.force_password_change === false && claims.claims.role === "student" && claims.claims.approved === true) {
    ok("claims merged, force_password_change cleared");
  } else {
    fail("claims", JSON.stringify(claims));
  }

  const usersWrite = captured.usersUpdate.find((c) => c.docId === UID2);
  if (usersWrite && usersWrite.data.force_password_change === false) ok("Firestore flag cleared");
  else fail("firestore", JSON.stringify(usersWrite));

  if (store[`user_secrets/${UID2}`].password_hash !== fixtureHash("Correct1!")) {
    ok("user_secrets hash rotated");
  } else {
    fail("hash", "hash not rotated");
  }

  // 10/11: success cleared ONLY the changePassword scope; login scopes and
  // per-account login counters are untouched.
  if (store[`login_throttle/${throttleDocId("change_password", UID2)}`] === undefined) {
    ok("changePassword throttle cleared on success");
  } else {
    fail("clear", "own throttle doc still present");
  }
  if (store[`login_throttle/${throttleDocId("student_login_ip", "9.9.9.9")}`] !== undefined) {
    ok("student login IP throttle untouched");
  } else {
    fail("isolation", "foreign throttle doc deleted");
  }
  if (store["user_secrets/user-2"].failed_login_attempts === 2) {
    ok("per-account login counters untouched");
  } else {
    fail("isolation", "login counters altered");
  }

  // 12: weak new password -> invalid-argument, consumes nothing.
  const UID3 = "user-3";
  store["user_secrets/user-3"] = { password_hash: fixtureHash("Correct1!") };
  try {
    await attempt(UID3, "Correct1!", "short");
    fail("weak-new", "expected failure, got success");
  } catch (err) {
    if (err.code !== "invalid-argument") {
      fail("weak-new", `unexpected ${err.code}`);
    } else if (store[`login_throttle/${throttleDocId("change_password", UID3)}`] === undefined) {
      ok("weak new password rejected, budget untouched");
    } else {
      fail("weak-new", "failure recorded for policy rejection");
    }
  }

  // 13: unauthenticated request consumes nothing (rejected before any
  // throttle read/write; requireAuthenticated throws first).
  const throttleKeysBefore = Object.keys(store).filter((k) => k.startsWith("login_throttle/")).sort().join(",");
  try {
    await attempt(null, "Wrong1!");
    fail("unauth", "expected failure, got success");
  } catch (err) {
    if (err.code !== "unauthenticated") {
      fail("unauth", `unexpected ${err.code}`);
    } else {
      const throttleKeysAfter = Object.keys(store).filter((k) => k.startsWith("login_throttle/")).sort().join(",");
      if (throttleKeysAfter !== throttleKeysBefore) fail("unauth", "throttle state changed");
      else ok("unauthenticated request rejected, nothing recorded");
    }
  }

  // 17: clearing a FORCED state sends the Arabic success notification;
  // plain rotations stay silent (no spam). The earlier user-2 success ran
  // without a forced flag, so no notification may exist for it.
  const forcedNotesForUser2 = captured.notifications.filter(
    (n) => n.user_id === UID2,
  );
  if (forcedNotesForUser2.length === 0) {
    ok("plain rotation (no forced flag) sends no notification");
  } else {
    fail("silence", `unexpected notification for plain rotation: ${JSON.stringify(forcedNotesForUser2)}`);
  }

  const UID4 = "user-4";
  store["user_secrets/user-4"] = { password_hash: fixtureHash("Correct1!") };
  store["claims_user-4"] = { role: "student", approved: true, force_password_change: true };
  try {
    const res = await changePassword({
      data: { currentPassword: "Correct1!", newPassword: STRONG_NEW },
      auth: { uid: UID4 },
    });
    if (!res || res.success !== true) fail("forced-success", `unexpected result ${JSON.stringify(res)}`);
  } catch (err) {
    fail("forced-success", `unexpected ${err.code}: ${err.message}`);
  }
  const successNote = captured.notifications.find((n) => n.user_id === UID4);
  if (
    successNote &&
    successNote.title === "تم تغيير كلمة المرور بنجاح" &&
    successNote.is_read === false
  ) {
    ok("forced-state clear sends Arabic success notification");
  } else {
    fail("notify", `missing/incorrect success notification: ${JSON.stringify(successNote)}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("change_password_throttle tests FAILED");
    process.exit(1);
  }
  console.log(`change_password_throttle.test: PASS - All ${passed} checks passed.`);
}

run();
