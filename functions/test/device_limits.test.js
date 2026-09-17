/**
 * Device registry tests (ADR-004).
 *
 * `onLoginAttempt` is registry/audit only: it records the calling device,
 * always succeeds for a valid session, and never evicts, rejects, or writes
 * authorization truth (`current_device_id` / `active_device` are retired).
 */
const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-test';

// The functions/index.js will initialize the admin app natively.
let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const wrapped = test.wrap(functions.onLoginAttempt);

async function run() {
    console.log("Starting device_limits tests against emulator...");

    // Setup test data
    const db = admin.firestore();
    const userId = "test_user_device_limits";

    await db.collection("users").doc(userId).set({
        name: "Test User",
        role: "student",
        approval_status: "approved"
    });

    const authContext = {
        uid: userId,
        token: { role: "student" }
    };

    // Clean up before test
    const oldDevices = await db.collection("devices").where("user_id", "==", userId).get();
    for (const d of oldDevices.docs) await d.ref.delete();

    async function registryRows() {
        return (await db.collection("devices").where("user_id", "==", userId).get()).docs;
    }

    console.log("Testing new device registration...");
    const res1 = await wrapped({ data: { userId, deviceId: "dev1", platform: "android" }, auth: authContext });
    assert.equal(res1.allowed, true);
    assert.equal(res1.status, "new_device");
    assert.ok(res1.deviceDocumentId, "Registry document id must be returned");

    console.log("Testing existing device re-registration...");
    const res2 = await wrapped({ data: { userId, deviceId: "dev1", platform: "android", osVersion: "14" }, auth: authContext });
    assert.equal(res2.allowed, true);
    assert.equal(res2.status, "existing_device");
    assert.equal(res2.deviceDocumentId, res1.deviceDocumentId, "Same device must map to one registry row");
    assert.equal((await registryRows()).length, 1);

    console.log("Testing many devices: no eviction, no rejection...");
    const res3 = await wrapped({ data: { userId, deviceId: "dev2", platform: "ios" }, auth: authContext });
    const res4 = await wrapped({ data: { userId, deviceId: "dev3", platform: "web" }, auth: authContext });
    assert.equal(res3.allowed, true);
    assert.equal(res4.allowed, true);
    assert.equal((await registryRows()).length, 3, "Every device is recorded; none evicted");

    console.log("Testing registry carries no authorization truth...");
    const rows = await registryRows();
    assert.ok(rows.every((d) => !("active_device" in d.data())), "No active_device flag is written");
    const userDoc = await db.collection("users").doc(userId).get();
    assert.ok(!("current_device_id" in userDoc.data()), "No current_device_id pointer is written");
    const dev2 = rows.find((d) => d.data().device_id === "dev2");
    assert.equal(dev2.data().platform, "ios");
    assert.ok(dev2.data().last_login, "last_login is maintained for audit");

    console.log("Testing guards that remain...");
    try {
        await wrapped({ data: { userId, deviceId: "devX" }, auth: { uid: "someone-else", token: { role: "student" } } });
        throw new Error("expected permission-denied for identity mismatch");
    } catch (e) {
        assert.equal(e.code, "permission-denied");
    }
    try {
        await wrapped({ data: { userId }, auth: authContext });
        throw new Error("expected invalid-argument for missing deviceId");
    } catch (e) {
        assert.equal(e.code, "invalid-argument");
    }
    try {
        await wrapped(
            { data: { userId, deviceId: "devX" }, auth: { uid: userId, token: { role: "teacher" } } },
        );
        throw new Error("expected permission-denied for non-student role");
    } catch (e) {
        assert.equal(e.code, "permission-denied");
    }

    test.cleanup();
    console.log("device_limits.test: PASS - registry-only login attempts verified against Firestore Emulator");
}

run().catch(e => {
    console.error("Test failed:", e);
    process.exit(1);
});
