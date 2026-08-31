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
    const maxDevices = 2;

    await db.collection("users").doc(userId).set({
        name: "Test User",
        approval_status: "approved"
    });

    const authContext = {
        uid: userId,
        token: { role: "student", max_devices: maxDevices }
    };

    // Helper to count active devices
    async function getActiveDevices() {
        const snap = await db.collection("devices")
            .where("user_id", "==", userId)
            .where("active_device", "==", true)
            .get();
        return snap.docs;
    }

    // Clean up before test
    const oldDevices = await db.collection("devices").where("user_id", "==", userId).get();
    for (const d of oldDevices.docs) await d.ref.delete();

    console.log("Testing new device login...");
    const res1 = await wrapped({ data: { userId, deviceId: "dev1", platform: "android" }, auth: authContext });
    assert.equal(res1.allowed, true);
    assert.equal(res1.status, "new_device");
    await new Promise(resolve => setTimeout(resolve, 500)); // sleep for timestamp differences

    const res2 = await wrapped({ data: { userId, deviceId: "dev2", platform: "ios" }, auth: authContext });
    assert.equal(res2.allowed, true);
    assert.equal(res2.status, "new_device");
    await new Promise(resolve => setTimeout(resolve, 500));

    // Limit is 2. Now add a third device.
    console.log("Testing third device login (limit 2)...");
    const res3 = await wrapped({ data: { userId, deviceId: "dev3", platform: "web" }, auth: authContext });
    assert.equal(res3.allowed, true);
    assert.equal(res3.status, "new_device");

    // Check that dev1 (the oldest) was deactivated.
    const activeDocs = await getActiveDevices();
    assert.equal(activeDocs.length, 2);
    
    const activeIds = activeDocs.map(d => d.data().device_id);
    assert.ok(!activeIds.includes("dev1"), "dev1 should have been deactivated");
    assert.ok(activeIds.includes("dev2"));
    assert.ok(activeIds.includes("dev3"));

    console.log("Testing existing device reconnecting...");
    const res4 = await wrapped({ data: { userId, deviceId: "dev2", platform: "ios" }, auth: authContext });
    assert.equal(res4.allowed, true);
    assert.equal(res4.status, "existing_device");

    test.cleanup();
    console.log("device_limits.test: PASS - reconnecting and new device deactivation logic verified against Firestore Emulator");
}

run().catch(e => {
    console.error("Test failed:", e);
    process.exit(1);
});
