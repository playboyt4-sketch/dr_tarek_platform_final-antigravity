const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = 'demo-test';
process.env.BUNNY_PLAYBACK_URL_TEMPLATE = 'https://example.com/{video_id}/{quality}';
process.env.BUNNY_TOKEN_KEY = 'test_key';

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const generateBunnySignedUrl = test.wrap(functions.generateBunnySignedUrl);
const db = admin.firestore();

async function run() {
  console.log("Starting sections_12_13 tests against emulator...");
  let passed = 0;

  try {
    const userId = "test_user_center";
    const subjectId = "subject_1";
    const planId = "plan_center_free";
    const lectureId1 = "lecture_1";
    const lectureId2 = "lecture_2";
    const videoId1 = "bunny_1";
    const videoId2 = "bunny_2";
    const deviceId = "test_device_123456789";

    await db.collection("users").doc(userId).set({
      student_type: "center_student",
      approval_status: "approved"
    });

    await db.collection("devices").doc(deviceId).set({
      user_id: userId,
      status: "active"
    });

    await db.collection("plans").doc(planId).set({
      student_type: "center_student",
      plan_key: "center_free",
      is_active: true
    });

    await db.collection("plan_features").doc("pf1").set({
      plan_id: planId,
      feature_key: "video.access",
      enabled: true
    });
    
    await db.collection("plan_features").doc("pf2").set({
      plan_id: planId,
      feature_key: "video.quality.720p",
      enabled: true
    });

    await db.collection("subscriptions").doc("sub1").set({
      student_id: userId,
      subject_id: subjectId,
      status: "active",
      plan_id: planId
    });
    
    await db.collection("subject_access_assignments").doc(`${userId}_${subjectId}`).set({
      student_id: userId,
      subject_id: subjectId,
      is_deleted: false,
      enabled: true,
      subscription_expires_at: admin.firestore.Timestamp.fromMillis(Date.now() + 100000000),
      entitlements: { "video.view": true }
    });

    await db.collection("lectures").doc(lectureId1).set({
      subject_id: subjectId,
      is_deleted: false,
      is_visible: true,
      status: "published"
    });

    await db.collection("lectures").doc(lectureId2).set({
      subject_id: subjectId,
      is_deleted: false,
      is_visible: true,
      status: "published"
    });

    await db.collection("lecture_resources").doc("res1").set({
      lecture_id: lectureId1,
      bunny_video_id: videoId1,
      resource_type: "video"
    });

    await db.collection("lecture_resources").doc("res2").set({
      lecture_id: lectureId2,
      bunny_video_id: videoId2,
      resource_type: "video"
    });

    // Test 1: No window -> allowed
    await db.collection("video_watch_windows").doc(userId).delete();
    await generateBunnySignedUrl({ data: { videoId: videoId1, deviceId }, auth: { uid: userId } });
    console.log("ok - No window -> allowed");
    passed++;

    // Test 2: Same lecture -> allowed
    await generateBunnySignedUrl({ data: { videoId: videoId1, deviceId }, auth: { uid: userId } });
    console.log("ok - Same lecture -> allowed");
    passed++;

    // Test 3: Different lecture -> rejected
    try {
      await generateBunnySignedUrl({ data: { videoId: videoId2, deviceId }, auth: { uid: userId } });
      assert.fail("Should have thrown resource-exhausted");
    } catch (e) {
      assert.equal(e.code, "resource-exhausted");
      console.log("ok - Different lecture -> rejected");
      passed++;
    }

    // Test 4: Expired window -> allowed (rolling)
    await db.collection("video_watch_windows").doc(userId).update({
      window_expires_at: admin.firestore.Timestamp.fromMillis(Date.now() - 1000)
    });
    await generateBunnySignedUrl({ data: { videoId: videoId2, deviceId }, auth: { uid: userId } });
    console.log("ok - Expired window -> allowed");
    passed++;

    // Test 5: Not gated for Center Pro
    await db.collection("plans").doc(planId).update({ plan_key: "center_pro" });
    await generateBunnySignedUrl({ data: { videoId: videoId1, deviceId }, auth: { uid: userId } });
    console.log("ok - Center Pro not gated");
    passed++;

    // Test 6: Race condition
    await db.collection("plans").doc(planId).update({ plan_key: "center_free" });
    await db.collection("video_watch_windows").doc(userId).delete();
    
    let successCount = 0;
    const req1 = generateBunnySignedUrl({ data: { videoId: videoId1, deviceId }, auth: { uid: userId } })
      .then(() => { successCount++; })
      .catch(() => {});
    const req2 = generateBunnySignedUrl({ data: { videoId: videoId2, deviceId }, auth: { uid: userId } })
      .then(() => { successCount++; })
      .catch(() => {});
      
    await Promise.all([req1, req2]);
    assert.equal(successCount, 1, "Exactly one concurrent request should succeed");
    console.log("ok - Race condition handled");
    passed++;

    console.log(`sections_12_13 tests passed (${passed}/6).`);
    process.exit(0);
  } catch (error) {
    console.error("FAIL", error);
    process.exitCode = 1;
  }
}

run();
