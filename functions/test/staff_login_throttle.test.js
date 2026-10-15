/**
 * staff_login_throttle.test.js — IP anti-spray protection for
 * verifyStaffPassword (Doctor/Admin path only).
 *
 * Approved policy: max 5 failed staff logins per caller IP; 6th rejected;
 * lock duration follows the existing ladder (5 fails -> 10 minutes).
 * Complements (never replaces) the per-name staff_login throttle.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1-5.  failures across different names from one IP -> generic
 *         unauthenticated (not throttled).
 *  6.    6th failure -> resource-exhausted (throttled).
 *  7.    lock duration ~10 minutes (existing ladder).
 *  8.    expired lock -> allowed again.
 *  9.    per-name staff_login throttle intact (3 same-name fails -> lock).
 *  10.   success clears per-name throttle but preserves the IP budget.
 *  11.   student login unaffected by staff IP exhaustion.
 *  12.   ambiguous-name behavior unchanged (failed-precondition, no budget).
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};

function docRef(collPath, docId) {
  const key = `${collPath}/${docId}`;
  return {
    id: docId,
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
    delete: async () => {
      delete store[key];
    },
  };
}

let USERS = [];

function usersQuery(field, op, value) {
  const docs = USERS.filter((u) => {
    if (op === "==") return u.data[field] === value;
    if (op === "in") return Array.isArray(value) && value.includes(u.data[field]);
    return false;
  }).map((u) => ({ id: u.id, data: () => u.data, ref: docRef("users", u.id) }));
  return {
    limit: () => ({ get: async () => ({ empty: docs.length === 0, docs }) }),
    get: async () => ({ empty: docs.length === 0, docs }),
  };
}

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => {
      if (collPath === "users") return { where: usersQuery, doc: (id) => docRef(collPath, id), add: async () => ({}) };
      return {
        where: () => ({
          limit: () => ({ get: async () => ({ empty: true, docs: [] }) }),
          get: async () => ({ empty: true, docs: [] }),
        }),
        doc: (docId) => docRef(collPath, docId),
        add: async () => ({}),
      };
    },
    runTransaction: async (fn) =>
      fn({
        get: (ref) => ref.get(),
        update: (ref, data) => ref.update(data),
        set: (ref, data, options) => ref.set(data, options),
      }),
    batch: () => ({ set: () => {}, update: () => {}, delete: () => {}, commit: async () => {} }),
  }),
  FieldValue: { serverTimestamp: () => ({}), delete: () => ({ __delete: true }) },
  Timestamp: class MockTimestamp {
    constructor(ms) {
      this.ms = ms;
    }
    toMillis() {
      return this.ms;
    }
    toDate() {
      return new Date(this.ms);
    }
    static now() {
      return new MockTimestamp(Date.now());
    }
    static fromDate(d) {
      return new MockTimestamp(d.getTime());
    }
    static fromMillis(ms) {
      return new MockTimestamp(ms);
    }
  },
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({ customClaims: {} }),
    setCustomUserClaims: async () => {},
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

const verifyStaffPassword = test.wrap(functions.verifyStaffPassword);
const verifyPhonePassword = test.wrap(functions.verifyPhonePassword);

function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

function throttleDocId(scope, key) {
  return crypto.createHash("sha256").update(`${scope}:${key}`).digest("hex");
}

async function staffAttempt(name, password, ip) {
  try {
    await verifyStaffPassword({
      data: { displayName: name, password },
      auth: null,
      rawRequest: ip ? { ip } : {},
    });
    return null;
  } catch (err) {
    return err;
  }
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

  USERS = [
    { id: "doc-1", data: { full_name: "Dr Owner", role: "doctor", account_status: "active" } },
  ];
  store["user_secrets/doc-1"] = { password_hash: fixtureHash("OwnerPass1!") };

  const IP = "10.30.0.1";
  const names = ["Nobody A", "Nobody B", "Nobody C", "Nobody D", "Nobody E", "Nobody F"];

  // 1-5: failures across different names share one IP budget, processed.
  for (let i = 0; i < 5; i++) {
    const err = await staffAttempt(names[i], "Wrong1!", IP);
    if (!err) fail(`fail${i + 1}`, "expected failure, got success");
    else if (err.code === "resource-exhausted") fail(`fail${i + 1}`, `throttled too early: ${err.message}`);
    else if (err.code !== "unauthenticated") fail(`fail${i + 1}`, `unexpected ${err.code}`);
  }
  ok("failures 1-5 distributed -> unauthenticated (not throttled)");

  // 6: sixth failure -> throttled.
  const err6 = await staffAttempt(names[5], "Wrong1!", IP);
  if (err6 && err6.code === "resource-exhausted") ok("failure 6 -> resource-exhausted (throttled)");
  else fail("throttled", `expected resource-exhausted, got ${err6 && err6.code}`);

  // 7: lock duration follows the existing ladder (5 fails -> ~10 minutes).
  const doc = store[`login_throttle/${throttleDocId("staff_login_ip", IP)}`];
  const remainingMs = doc.locked_until.toMillis() - Date.now();
  if (remainingMs > 9 * 60 * 1000 && remainingMs <= 10 * 60 * 1000) {
    ok(`lock duration ~10min ladder (${Math.round(remainingMs / 1000)}s remaining)`);
  } else {
    fail("duration", `expected ~10min, got ${remainingMs}ms`);
  }

  // 8: expired lock -> allowed again.
  store[`login_throttle/${throttleDocId("staff_login_ip", IP)}`] = {
    ...doc,
    locked_until: { toMillis: () => Date.now() - 1000, toDate: () => new Date(Date.now() - 1000) },
  };
  const errExp = await staffAttempt("Nobody G", "Wrong1!", IP);
  if (errExp && errExp.code === "unauthenticated") ok("expired lock -> processed again");
  else fail("expired", `unexpected ${errExp && errExp.code}`);

  // 9: per-name staff_login throttle intact (isolated IP).
  const IP_NAME = "10.30.0.2";
  for (let i = 0; i < 3; i++) {
    const err = await staffAttempt("Same Guy", "Wrong1!", IP_NAME);
    if (!err || err.code !== "unauthenticated") fail(`name-fail${i + 1}`, `unexpected ${err && err.code}`);
  }
  const errName = await staffAttempt("Same Guy", "Wrong1!", IP_NAME);
  if (errName && errName.code === "resource-exhausted") ok("per-name throttle intact (3 fails -> locked)");
  else fail("name-lock", `unexpected ${errName && errName.code}`);

  // 10: success clears per-name throttle but preserves the IP budget.
  USERS.push({ id: "adm-1", data: { full_name: "Admin One", role: "admin", account_status: "active" } });
  store["user_secrets/adm-1"] = { password_hash: fixtureHash("AdminPass1!") };
  const IP_OK = "10.30.0.3";
  await staffAttempt("Admin One", "Wrong1!", IP_OK);
  await staffAttempt("Admin One", "Wrong1!", IP_OK);
  const nameDocBefore = `login_throttle/${throttleDocId("staff_login", "admin one")}`;
  if (store[nameDocBefore] === undefined) fail("setup", "per-name doc missing before success");
  try {
    const res = await verifyStaffPassword({
      data: { displayName: "Admin One", password: "AdminPass1!" },
      auth: null,
      rawRequest: { ip: IP_OK },
    });
    if (res && res.token === "mock-token") ok("correct staff password succeeds when not locked");
    else fail("success", JSON.stringify(res));
  } catch (err) {
    fail("success", `${err.code}: ${err.message}`);
  }
  if (store[nameDocBefore] === undefined) ok("success clears per-name throttle");
  else fail("clear-name", "per-name doc still present");
  const ipDoc = store[`login_throttle/${throttleDocId("staff_login_ip", IP_OK)}`];
  if (ipDoc !== undefined && ipDoc.fail_count === 2) ok("success preserves IP budget (fail_count 2)");
  else fail("ip-preserved", JSON.stringify(ipDoc));

  // 11: student login unaffected by staff IP exhaustion.
  try {
    await verifyPhonePassword({
      data: { phoneNumber: "01009999999", password: "Wrong1!" },
      auth: null,
      rawRequest: { ip: IP },
    });
    fail("student", "expected failure, got success");
  } catch (err) {
    if (err.code === "unauthenticated") ok("student login unaffected by staff IP budget");
    else fail("student", `unexpected ${err.code}: ${err.message}`);
  }

  // 12: ambiguous-name behavior unchanged.
  USERS.push({ id: "amb-1", data: { full_name: "Same Name", role: "admin", account_status: "active" } });
  USERS.push({ id: "amb-2", data: { full_name: "Same Name", role: "admin", account_status: "active" } });
  const errAmb = await staffAttempt("Same Name", "Wrong1!", "10.30.0.4");
  if (errAmb && errAmb.code === "failed-precondition") ok("ambiguous-name -> failed-precondition (unchanged)");
  else fail("ambiguous", `${errAmb && errAmb.code}: ${errAmb && errAmb.message}`);

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("staff_login_throttle tests FAILED");
    process.exit(1);
  }
  console.log(`staff_login_throttle.test: PASS - All ${passed} checks passed.`);
}

run();
