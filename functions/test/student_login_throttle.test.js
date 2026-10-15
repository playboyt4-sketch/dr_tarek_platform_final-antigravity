/**
 * student_login_throttle.test.js — pre-lookup anti-spray protection for
 * verifyPhonePassword (approved: max 5 FAILED logins per caller IP).
 *
 * Runs against compiled ../lib/index.js with an in-memory Firestore/Auth
 * mock (same pattern as password_reset.test.js). No emulator, no network.
 *
 * Verified behaviors:
 *  1-5. attempts 1-5 from one IP -> processed (unauthenticated, NOT throttled)
 *  6.   6th attempt in window -> resource-exhausted
 *  7.   expired lock -> allowed again
 *  8.   budget shared across different phones (spray), keyed by IP
 *  9.   per-account lockout (3 fails, user_secrets) unchanged
 *  10.  unknown phone vs wrong password indistinguishable
 *  11.  staff login unaffected by the student IP budget
 *  12.  registration unaffected
 *  13.  password reset unaffected
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const store = {};

const DELETE = { __delete: true };

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
    update: async () => {},
  };
}

// In-memory users table.
let USERS = [];

function matchesFilter(data, field, op, value) {
  if (op === "==") return data[field] === value;
  if (op === "in") return Array.isArray(value) && value.includes(data[field]);
  return false;
}

function usersQuery(field, op, value) {
  const docs = USERS.filter((u) => matchesFilter(u.data, field, op, value)).map(
    (u) => ({ id: u.id, data: () => u.data }),
  );
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
        where: () => ({ limit: () => ({ get: async () => ({ empty: true, docs: [] }) }), get: async () => ({ empty: true, docs: [] }) }),
        doc: (docId) => docRef(collPath, docId),
        add: async () => ({}),
      };
    },
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

const verifyPhonePassword = test.wrap(functions.verifyPhonePassword);
const verifyStaffPassword = test.wrap(functions.verifyStaffPassword);
const registerNewStudent = test.wrap(functions.registerNewStudent);
const submitPasswordResetRequest = test.wrap(functions.submitPasswordResetRequest);

// Fixture scrypt hash for password "Correct1!" in stored format.
function fixtureHash(password) {
  const salt = Buffer.from("00112233445566778899aabbccddeeff", "hex");
  const derived = crypto.scryptSync(password, salt, 64, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString("hex")}$${derived.toString("hex")}$16384`;
}

const KNOWN_PHONE = "01001234567";

function throttleDocId(ip) {
  return crypto.createHash("sha256").update(`student_login_ip:${ip}`).digest("hex");
}

async function attemptLogin(phone, password, ip) {
  return verifyPhonePassword({
    data: { phoneNumber: phone, password },
    auth: null,
    rawRequest: ip ? { ip } : {},
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

  USERS = [
    {
      id: "stu-1",
      data: {
        phone_number: KNOWN_PHONE,
        approval_status: "approved",
        account_status: "active",
        role: "student",
        student_type: "center_student",
      },
    },
    {
      id: "stu-2",
      data: {
        phone_number: "01001234568",
        approval_status: "approved",
        account_status: "active",
        role: "student",
        student_type: "center_student",
      },
    },
  ];
  store["user_secrets/stu-1"] = { password_hash: fixtureHash("Correct1!") };
  store["user_secrets/stu-2"] = { password_hash: fixtureHash("Correct1!") };

  const IP_SPRAY = "10.0.0.1";
  const sprayPhones = [
    "01010000001",
    "01010000002",
    "01010000003",
    "01010000004",
    "01010000005",
    "01010000006",
  ];

  // 1-5: first five failures across DIFFERENT unknown phones share one IP
  // budget and are processed (generic unauthenticated, not throttled).
  for (let i = 0; i < 5; i++) {
    try {
      await attemptLogin(sprayPhones[i], "Wrong1!", IP_SPRAY);
      fail(`attempt${i + 1}`, "expected failure, got success");
    } catch (err) {
      if (err.code === "resource-exhausted") {
        fail(`attempt${i + 1}`, `throttled too early: ${err.message}`);
      } else if (err.code !== "unauthenticated") {
        fail(`attempt${i + 1}`, `unexpected code ${err.code}`);
      } else {
        ok(`attempt${i + 1}/5 distributed -> unauthenticated (not throttled)`);
      }
    }
  }

  // 6: sixth failure within the window -> throttled.
  try {
    await attemptLogin(sprayPhones[5], "Wrong1!", IP_SPRAY);
    fail("attempt6", "expected throttle, got success");
  } catch (err) {
    if (err.code === "resource-exhausted") ok("attempt6/5 -> resource-exhausted (throttled)");
    else fail("attempt6", `expected resource-exhausted, got ${err.code}`);
  }

  // 7: after the lock expires -> allowed again.
  const key = `login_throttle/${throttleDocId(IP_SPRAY)}`;
  store[key] = {
    ...store[key],
    locked_until: { toMillis: () => Date.now() - 1000, toDate: () => new Date(Date.now() - 1000) },
  };
  try {
    await attemptLogin("01010000007", "Wrong1!", IP_SPRAY);
    fail("expired", "expected failure, got success");
  } catch (err) {
    if (err.code === "resource-exhausted") fail("expired", "still throttled after expiry");
    else if (err.code === "unauthenticated") ok("expired lock -> processed again");
    else fail("expired", `unexpected code ${err.code}`);
  }

  // 9: per-account lockout unchanged (isolated IP so only account gate fires).
  // Post enumeration-hardening, wrong passwords always return generic
  // (even when locked); the lock surfaces on the CORRECT password, which
  // still enforces the 3-strike ladder.
  const IP_ACCT = "10.0.0.2";
  for (let i = 0; i < 3; i++) {
    try {
      await attemptLogin(KNOWN_PHONE, "Wrong1!", IP_ACCT);
      fail(`account-fail${i + 1}`, "expected failure, got success");
    } catch (err) {
      if (err.code !== "unauthenticated") fail(`account-fail${i + 1}`, `unexpected code ${err.code}`);
    }
  }
  try {
    await attemptLogin(KNOWN_PHONE, "Wrong1!", IP_ACCT);
    fail("account-lock-wrong", "expected failure, got success");
  } catch (err) {
    if (err.code === "unauthenticated") {
      ok("locked account + wrong password -> generic (no oracle)");
    } else {
      fail("account-lock-wrong", `unexpected ${err.code}: ${err.message}`);
    }
  }
  try {
    await attemptLogin(KNOWN_PHONE, "Correct1!", IP_ACCT);
    fail("account-lock", "expected lock, got success");
  } catch (err) {
    if (err.code === "resource-exhausted" && /Account locked/.test(err.message)) {
      ok("per-account lockout unchanged (3 fails -> Account locked on correct)");
    } else {
      fail("account-lock", `unexpected ${err.code}: ${err.message}`);
    }
  }

  // 10: unknown phone vs wrong password indistinguishable.
  const IP_ORACLE = "10.0.0.3";
  let unknownErr;
  let wrongErr;
  try {
    await attemptLogin("01019999999", "Wrong1!", IP_ORACLE);
  } catch (err) {
    unknownErr = err;
  }
  try {
    // stu-2 (fresh account counters) isolates this check from the
    // per-account lockout exercised on stu-1 above.
    await attemptLogin("01001234568", "Wrong1!", IP_ORACLE);
  } catch (err) {
    wrongErr = err;
  }
  if (unknownErr && wrongErr && unknownErr.code === wrongErr.code && unknownErr.message === wrongErr.message) {
    ok("unknown phone == wrong password response (no oracle)");
  } else {
    fail("oracle", `unknown=${unknownErr && unknownErr.code}/${unknownErr && unknownErr.message} wrong=${wrongErr && wrongErr.code}/${wrongErr && wrongErr.message}`);
  }

  // 11: staff login unaffected — exhausted student IP budget, unknown staff
  // name must still return generic unauthenticated (not throttled).
  const IP_STAFF = "10.0.0.4";
  for (let i = 0; i < 6; i++) {
    try {
      await attemptLogin(`0102000000${i}`, "Wrong1!", IP_STAFF);
    } catch (err) {
      // Expected: first 5 unauthenticated, 6th throttled; ignore here.
    }
  }
  try {
    await verifyStaffPassword({
      data: { displayName: "Nobody Here", password: "Wrong1!" },
      auth: null,
      rawRequest: { ip: IP_STAFF },
    });
    fail("staff", "expected failure, got success");
  } catch (err) {
    if (err.code === "unauthenticated") ok("staff login unaffected by student IP budget");
    else fail("staff", `unexpected ${err.code}: ${err.message}`);
  }

  // 12: registration unaffected — duplicate phone still returns
  // already-exists (not throttled) from the exhausted IP.
  try {
    await registerNewStudent({
      data: { fullName: "Test", phoneNumber: KNOWN_PHONE, grade: "grade_one", password: "Aa1!bcde" },
      auth: null,
      rawRequest: { ip: IP_STAFF },
    });
    fail("registration", "expected failure, got success");
  } catch (err) {
    if (err.code === "already-exists") ok("registration unaffected (duplicate -> already-exists)");
    else fail("registration", `unexpected ${err.code}: ${err.message}`);
  }

  // 13: password reset unaffected — uniform submitted:true from exhausted IP.
  try {
    const res = await submitPasswordResetRequest({
      data: { phoneNumber: "01029999999" },
      auth: null,
      rawRequest: { ip: IP_STAFF },
    });
    if (res && res.submitted === true) ok("password reset unaffected (uniform submitted:true)");
    else fail("reset", `unexpected result ${JSON.stringify(res)}`);
  } catch (err) {
    fail("reset", `unexpected ${err.code}: ${err.message}`);
  }

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("student_login_throttle tests FAILED");
    process.exit(1);
  }
  console.log(`student_login_throttle.test: PASS - All ${passed} checks passed.`);
}

run();
