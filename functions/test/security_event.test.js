/**
 * T-CF.13 onSecurityEvent — unit tests with mocked Admin SDK.
 *
 * Verifies: authenticated submission, unauthenticated rejection, invalid
 * event type / severity rejection, impersonation and actor-forgery
 * resistance (identity comes only from Auth context), separation of
 * security_events from analytics_events, server-generated timestamps,
 * and unchanged analytics behavior.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const writes = [];

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: (collPath) => ({
      doc: () => ({
        get: async () => ({exists: false}),
        update: async () => {},
        set: async () => {},
      }),
      where: (field, op, value) => {
        const query = {
          where: () => query,
          get: async () => {
            // One staff doctor exists so high-severity alerts fan out.
            if (collPath === "users" && field === "role" && value === "doctor") {
              return {
                empty: false,
                docs: [{id: "doctor-1", data: () => ({role: "doctor"})}],
              };
            }
            return {empty: true, docs: []};
          },
        };
        return query;
      },
      add: async (data) => {
        const id = `${collPath}-doc-${writes.length}`;
        writes.push({collection: collPath, id, data});
        return {id};
      },
    }),
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({customClaims: {}}),
    setCustomUserClaims: async () => {},
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
  if (id === "firebase-admin/auth") return {getAuth: adminMock.getAuth};
  if (id === "firebase-admin/messaging") return {getMessaging: adminMock.getMessaging};
  if (id === "firebase-admin/storage") return {getStorage: adminMock.getStorage};
  if (id === "firebase-admin/app") return {initializeApp: adminMock.initializeApp};
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const wrapped = test.wrap(functions.onSecurityEvent);

function calls(collection) {
  return writes.filter((w) => w.collection === collection);
}

async function run() {
  let passed = 0;
  async function checkPass(name, req) {
    try {
      const res = await wrapped(req);
      passed++;
      console.log(`ok - ${name}`);
      return res;
    } catch (err) {
      console.error(`FAIL - ${name}: expected success, got ${err.code}: ${err.message}`);
      process.exitCode = 1;
      return null;
    }
  }

  async function checkFail(name, req, code) {
    try {
      await wrapped(req);
      console.error(`FAIL - ${name}: expected failure, got success`);
      process.exitCode = 1;
    } catch (err) {
      if (code && err.code !== code) {
        console.error(`FAIL - ${name}: expected ${code}, got ${err.code}`);
        process.exitCode = 1;
        return;
      }
      passed++;
      console.log(`ok - ${name}`);
    }
  }

  const studentAuth = {uid: "student-sec-1", token: {role: "student"}};

  // 1. Authenticated valid event (screenshot, default severity).
  writes.length = 0;
  const res = await checkPass("Authenticated screenshot event", {
    data: {
      eventType: "screenshot",
      context: {lecture_id: "lec-1"},
      deviceInfo: {model: "Pixel", os_version: "14", app_version: "1.0.0"},
      screenshotDetected: true,
    },
    auth: studentAuth,
  });
  assert.equal(res.logged, true);
  assert.ok(res.securityEventId);
  const secDocs = calls("security_events");
  assert.equal(secDocs.length, 1);
  assert.equal(secDocs[0].data.user_id, "student-sec-1");
  assert.equal(secDocs[0].data.event_type, "screenshot");
  assert.equal(secDocs[0].data.severity, "medium");
  assert.equal(secDocs[0].data.action_taken, "warning");
  assert.ok(secDocs[0].data.created_at);
  console.log("ok - Security event stored with server fields");

  // 6+7. Separate analytics mirror with unchanged behavior.
  const analyticsDocs = calls("analytics_events");
  assert.equal(analyticsDocs.length, 1);
  assert.equal(analyticsDocs[0].data.event_type, "Security Event");
  assert.equal(analyticsDocs[0].data.user_id, "student-sec-1");
  assert.equal(analyticsDocs[0].data.reference_id, res.securityEventId);
  console.log("ok - Analytics mirror separate and intact");

  // 2. Unauthenticated rejected.
  await checkFail("Unauthenticated rejected", {data: {eventType: "screenshot"}}, "unauthenticated");

  // 3. Invalid event types rejected.
  await checkFail("Missing eventType rejected", {data: {}, auth: studentAuth}, "invalid-argument");
  await checkFail("Empty eventType rejected", {data: {eventType: "  "}, auth: studentAuth}, "invalid-argument");
  await checkFail("Non-string eventType rejected", {data: {eventType: 42}, auth: studentAuth}, "invalid-argument");
  await checkFail(
    "Oversized eventType rejected",
    {data: {eventType: "x".repeat(65)}, auth: studentAuth},
    "invalid-argument",
  );
  await checkFail("Bad severity rejected", {data: {eventType: "emulator", severity: "catastrophic"}, auth: studentAuth}, "invalid-argument");
  await checkFail("Non-string severity rejected", {data: {eventType: "emulator", severity: 3}, auth: studentAuth}, "invalid-argument");
  await checkFail("Empty severity rejected", {data: {eventType: "emulator", severity: "  "}, auth: studentAuth}, "invalid-argument");

  // Unsupported event types are rejected before any write or notification.
  writes.length = 0;
  await checkFail("Unsupported eventType rejected", {data: {eventType: "malware"}, auth: studentAuth}, "invalid-argument");
  await checkFail("Whitespace-padded unsupported eventType rejected", {data: {eventType: " malware "}, auth: studentAuth}, "invalid-argument");
  await checkFail("Device mismatch is not a security event", {data: {eventType: "device_mismatch"}, auth: studentAuth}, "invalid-argument");
  assert.equal(writes.length, 0);
  console.log("ok - Unsupported event types write nothing");

  // Rooted-device reporting is a documented integrity event.
  writes.length = 0;
  await checkPass("Rooted device event accepted", {
    data: {eventType: "rooted", severity: "low"},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.event_type, "rooted");
  assert.equal(calls("security_events")[0].data.action_taken, "warning");
  assert.equal(calls("notifications").length, 0);

  // Malformed payload containers degrade to documented empty maps.
  writes.length = 0;
  await checkPass("Malformed context and deviceInfo degrade safely", {
    data: {
      eventType: "emulator",
      context: [1, 2, 3],
      deviceInfo: "raw-device-string",
    },
    auth: studentAuth,
  });
  assert.deepEqual(calls("security_events")[0].data.context, {});
  assert.deepEqual(calls("security_events")[0].data.device_info, {});
  assert.equal(calls("security_events")[0].data.severity, "medium");
  assert.equal(calls("security_events")[0].data.action_taken, "warning");
  console.log("ok - Malformed payload containers normalized");

  // Severity is canonicalized before the allowlist check.
  writes.length = 0;
  await checkPass("Mixed-case severity normalized", {
    data: {eventType: "screen_record", severity: "HIGH"},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.severity, "high");
  assert.equal(calls("security_events")[0].data.action_taken, "notify_admin");
  assert.ok(calls("notifications").length >= 1);
  console.log("ok - Severity canonicalized and routed");

  // 4+5. Impersonation and actor forgery are ignored: identity is auth-derived.
  writes.length = 0;
  await checkPass("Forged identity fields ignored", {
    data: {
      eventType: "jailbreak",
      severity: "low",
      user_id: "victim-uid",
      userId: "victim-uid",
      role: "doctor",
      actor_id: "doctor-1",
      actor_role: "doctor",
      actionTaken: "logout",
    },
    auth: studentAuth,
  });
  const forged = calls("security_events");
  assert.equal(forged.length, 1);
  assert.equal(forged[0].data.user_id, "student-sec-1");
  assert.ok(!("actor_id" in forged[0].data));
  assert.ok(!("actor_role" in forged[0].data));
  assert.ok(!("role" in forged[0].data));
  assert.equal(forged[0].data.action_taken, "warning");
  console.log("ok - Impersonation and forgery neutralized");

  // High severity still routes to notify_admin without client control.
  writes.length = 0;
  await checkPass("Critical severity notifies", {
    data: {eventType: "screen_record", severity: "critical", screenRecordDetected: true},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.action_taken, "notify_admin");
  assert.ok(calls("notifications").length >= 1);
  console.log("ok - Critical path alerts staff");

  // The client cannot trigger staff alerts for a low-severity event by forging
  // the response field.
  writes.length = 0;
  await checkPass("Forged notify_admin action cannot trigger alerts", {
    data: {eventType: "jailbreak", severity: "low", actionTaken: "notify_admin"},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.action_taken, "warning");
  assert.equal(calls("notifications").length, 0);
  console.log("ok - Low severity cannot be escalated through actionTaken");

  // The client cannot suppress staff alerts for a critical event by forging
  // a weaker response field.
  writes.length = 0;
  await checkPass("Forged warning action cannot suppress alerts", {
    data: {eventType: "screen_record", severity: "critical", actionTaken: "warning"},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.action_taken, "notify_admin");
  const alertDocs = calls("notifications");
  assert.ok(alertDocs.length >= 1);
  assert.ok(alertDocs.every((doc) => doc.data.user_id === "doctor-1"));
  assert.ok(!alertDocs.some((doc) => doc.data.user_id === "victim-uid"));
  console.log("ok - Critical alerts cannot be suppressed or misrouted");

  // No forged client action is ever persisted as the server response.
  writes.length = 0;
  await checkPass("Forged stop action is not persisted", {
    data: {eventType: "jailbreak", severity: "medium", actionTaken: "stop"},
    auth: studentAuth,
  });
  assert.equal(calls("security_events")[0].data.action_taken, "warning");
  assert.ok(!Object.values(calls("security_events")[0].data).includes("stop"));
  console.log("ok - Client action values are never stored");

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("security_event tests FAILED");
    process.exit(1);
  }
  console.log(`security_event.test: PASS - All ${passed} checks passed.`);
}

run();
