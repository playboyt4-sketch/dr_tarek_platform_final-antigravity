/**
 * delete_owner_auth.test.js — deleteAccountByOwner canonical authorization.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors (no purge is ever reached — deleteUser stays uncalled):
 *  1. unauthenticated -> unauthenticated.
 *  2. student token -> permission-denied (token claim, not Firestore doc).
 *  3. admin token -> permission-denied (no delegation for destructive wipe).
 *  4. doctor without password -> invalid-argument (gate passed).
 *  5. doctor deleting self -> invalid-argument (must use deleteMyAccount).
 *  6. doctor deleting doctor target -> permission-denied (correct password).
 *  7. doctor with wrong password -> permission-denied (owner password gate).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};
const deletedAuthUsers = [];

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    get: async () => {
      if (store[key] === undefined) return { exists: false };
      return { exists: true, data: () => store[key] };
    },
    set: async (data, options) => {
      if (options && options.merge && store[key] !== undefined) {
        store[key] = { ...store[key], ...data };
      } else {
        store[key] = { ...data };
      }
    },
    update: async (data) => {
      if (store[key] !== undefined) store[key] = { ...store[key], ...data };
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
      add: async () => ({}),
    }),
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
  Timestamp: {
    now: () => ({ toMillis: () => Date.now() }),
    fromDate: (d) => ({ toMillis: () => d.getTime(), toDate: () => d }),
    fromMillis: (ms) => ({ toMillis: () => ms, toDate: () => new Date(ms) }),
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {},
    createCustomToken: async () => "mock-token",
    createUser: async () => ({ uid: "new-uid" }),
    deleteUser: async (uid) => {
      deletedAuthUsers.push(uid);
    },
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

const deleteAccountByOwner = test.wrap(functions.deleteAccountByOwner);

function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

async function attempt(auth, data) {
  return deleteAccountByOwner({ data, auth });
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
  async function expectCode(name, auth, data, code) {
    try {
      await attempt(auth, data);
      fail(name, "expected failure, got success");
    } catch (err) {
      if (err.code === code) ok(name);
      else fail(name, `expected ${code}, got ${err.code}: ${err.message}`);
    }
  }

  store["users/doctor-1"] = { role: "doctor" };
  store["users/admin-1"] = { role: "admin" };
  store["users/student-1"] = { role: "student" };
  store["users/doctor-2"] = { role: "doctor" };
  store["user_secrets/doctor-1"] = { password_hash: fixtureHash("OwnerPass1!") };

  const doctorAuth = { uid: "doctor-1", token: { role: "doctor" } };

  // 1: unauthenticated.
  await expectCode("unauthenticated -> denied", null, { targetUid: "student-1", password: "x" }, "unauthenticated");

  // 2: student token denied even though a Firestore doc exists.
  await expectCode(
    "student token -> permission-denied",
    { uid: "student-1", token: { role: "student" } },
    { targetUid: "admin-1", password: "x" },
    "permission-denied",
  );

  // 3: admin token denied (no delegation for destructive wipe).
  await expectCode(
    "admin token -> permission-denied",
    { uid: "admin-1", token: { role: "admin" } },
    { targetUid: "student-1", password: "x" },
    "permission-denied",
  );

  // 4: doctor gate passes shape validation next (missing password).
  await expectCode(
    "doctor without password -> invalid-argument",
    doctorAuth,
    { targetUid: "student-1" },
    "invalid-argument",
  );

  // 5: self-delete redirected.
  await expectCode(
    "doctor self-delete -> invalid-argument",
    doctorAuth,
    { targetUid: "doctor-1", password: "OwnerPass1!" },
    "invalid-argument",
  );

  // 6: doctor target refused (correct owner password reaches target check).
  await expectCode(
    "doctor target -> permission-denied",
    doctorAuth,
    { targetUid: "doctor-2", password: "OwnerPass1!" },
    "permission-denied",
  );

  // 7: wrong owner password rejected (pre-existing verifyPasswordForDeletion
  // contract: unauthenticated "Invalid password." — unchanged by this task).
  await expectCode(
    "wrong owner password -> unauthenticated",
    doctorAuth,
    { targetUid: "student-1", password: "Wrong1!" },
    "unauthenticated",
  );

  // Purge never reached in any denial path.
  if (deletedAuthUsers.length === 0) ok("no Auth deletion on any denial path");
  else fail("purge-leak", JSON.stringify(deletedAuthUsers));

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("delete_owner_auth tests FAILED");
    process.exit(1);
  }
  console.log(`delete_owner_auth.test: PASS - All ${passed} checks passed.`);
}

run();
