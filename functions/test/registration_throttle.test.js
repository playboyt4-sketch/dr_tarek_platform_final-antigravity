/**
 * registration_throttle.test.js — abuse protection for registerNewStudent.
 *
 * Approved policy: max 10 valid registration submissions per caller IP per
 * 15 minutes (sliding window); malformed requests never consume budget;
 * duplicate-phone already-exists contract unchanged; no permanent lock.
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1-9.  duplicate-phone attempts -> already-exists (contract intact).
 *  10.   valid new registration -> success (no incorrect lock).
 *  11.   11th valid attempt in window -> resource-exhausted (throttled).
 *  12.   expired window -> allowed again.
 *  13.   fresh IP unaffected by another IP's exhaustion.
 *  14.   malformed requests consume no budget.
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
    createUser: async () => ({ uid: "new-student-uid" }),
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

const registerNewStudent = test.wrap(functions.registerNewStudent);

const IP = "10.20.0.1";

function throttleKey(ip) {
  return `registration_throttle/${crypto.createHash("sha256").update(`registration:${ip}`).digest("hex")}`;
}

function validPayload(phone) {
  return {
    fullName: "Test Student",
    phoneNumber: phone,
    grade: "grade_one",
    password: "Aa1!bcde",
  };
}

async function attempt(data, ip) {
  return registerNewStudent({ data, auth: null, rawRequest: ip ? { ip } : {} });
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

  USERS = [{ id: "existing-1", data: { phone_number: "01001111111", role: "student" } }];

  // 1-9: duplicate-phone attempts follow the existing contract.
  for (let i = 0; i < 9; i++) {
    try {
      await attempt(validPayload("01001111111"), IP);
      fail(`dup${i + 1}`, "expected failure, got success");
    } catch (err) {
      if (err.code !== "already-exists") fail(`dup${i + 1}`, `unexpected ${err.code}: ${err.message}`);
    }
  }
  ok("attempts 1-9 duplicate -> already-exists (contract intact)");

  // 10: a valid new registration still succeeds (no incorrect lock).
  try {
    const res = await attempt(validPayload("01002222222"), IP);
    if (res && res.userId === "new-student-uid") ok("attempt 10 valid registration succeeds");
    else fail("success", JSON.stringify(res));
  } catch (err) {
    fail("success", `${err.code}: ${err.message}`);
  }

  // 11: eleventh valid attempt in window -> throttled.
  try {
    await attempt(validPayload("01003333333"), IP);
    fail("throttled", "expected throttle, got success");
  } catch (err) {
    if (err.code === "resource-exhausted") ok("attempt 11 -> resource-exhausted (throttled)");
    else fail("throttled", `expected resource-exhausted, got ${err.code}`);
  }

  // 12: expired window -> allowed again.
  const doc = store[throttleKey(IP)];
  const past = Date.now() - 20 * 60 * 1000;
  store[throttleKey(IP)] = {
    recent: doc.recent.map(() => ({ toMillis: () => past, toDate: () => new Date(past) })),
  };
  try {
    await attempt(validPayload("01001111111"), IP);
    fail("expired", "expected failure, got success");
  } catch (err) {
    if (err.code === "already-exists") ok("expired window -> processed again (already-exists)");
    else fail("expired", `unexpected ${err.code}: ${err.message}`);
  }

  // 13: fresh IP unaffected.
  try {
    await attempt(validPayload("01001111111"), "10.20.0.2");
    fail("fresh-ip", "expected failure, got success");
  } catch (err) {
    if (err.code === "already-exists") ok("fresh IP unaffected by other IP exhaustion");
    else fail("fresh-ip", `unexpected ${err.code}: ${err.message}`);
  }

  // 14: malformed requests consume no budget (fresh IP + invalid payloads,
  // then a valid attempt still processed).
  const IP_MAL = "10.20.0.3";
  for (const bad of [{}, { fullName: "x" }, { fullName: "x", phoneNumber: "bad", grade: "g", password: "Aa1!bcde" }]) {
    try {
      await attempt(bad, IP_MAL);
    } catch (err) {
      if (err.code !== "invalid-argument") fail("malformed", `unexpected ${err.code}`);
    }
  }
  if (store[throttleKey(IP_MAL)] === undefined) ok("malformed requests consume no budget");
  else fail("malformed", "throttle doc created for invalid payloads");
  try {
    await attempt(validPayload("01001111111"), IP_MAL);
    fail("post-malformed", "expected failure, got success");
  } catch (err) {
    if (err.code === "already-exists") ok("valid attempt after malformed still processed");
    else fail("post-malformed", `unexpected ${err.code}: ${err.message}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("registration_throttle tests FAILED");
    process.exit(1);
  }
  console.log(`registration_throttle.test: PASS - All ${passed} checks passed.`);
}

run();
