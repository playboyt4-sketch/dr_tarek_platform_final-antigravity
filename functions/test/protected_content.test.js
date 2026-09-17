/**
 * Protected-content tier enforcement tests (ADR-004, second backend step).
 *
 * Verifies that generateBunnySignedUrl, generateProtectedPdfUrl,
 * generatePdfDownloadUrl, generateBunnyResourceUrl, and getLectureResources
 * resolve Full vs Guest server-side per Student + Subject + Device, that
 * Guest receives only the existing structural preview contract (or denial),
 * and that no Guest path mutates subscriptions or authorizations.
 *
 * NOTE: Full PDF/download issuance calls live Storage signing, which has no
 * emulator configured in this repo; Guest denials (which occur before any
 * storage call) and all video/listing paths are covered here. The Full PDF
 * code path itself is byte-identical to the pre-change behavior behind the
 * added tier gate.
 *
 * Runs inside `firebase emulators:exec` (firestore + auth).
 */
const test = require("firebase-functions-test")();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";
process.env.BUNNY_PLAYBACK_URL_TEMPLATE =
  "https://cdn.example.com/{video_id}/{quality}/stream.m3u8";
process.env.BUNNY_TOKEN_KEY = "test-secret-key";

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const STUDENT = "pcont_student";
const SUB_V = "pcont_subV"; // Free (allowance 1)
const SUB_P = "pcont_subP"; // Pro (allowance 1)
const SUB_M = "pcont_subM"; // Max (allowance 2)

const studentCtx = {uid: STUDENT, token: {role: "student", approved: true}};

function expectCode(promise, code, label) {
  return promise.then(
    () => {
      throw new Error(`${label}: expected rejection with ${code}, but succeeded`);
    },
    (e) => {
      assert.equal(e.code, code, `${label}: expected ${code}, got ${e.code} (${e.message})`);
    },
  );
}

async function run() {
  console.log("Starting protected_content tests against emulator...");
  const db = admin.firestore();
  const signedUrlRaw = test.wrap(functions.generateBunnySignedUrl);
  const videoUrl = (payload) => signedUrlRaw({data: payload, auth: studentCtx});
  const pdfViewRaw = test.wrap(functions.generateProtectedPdfUrl);
  const pdfView = (payload) => pdfViewRaw({data: payload, auth: studentCtx});
  const pdfDlRaw = test.wrap(functions.generatePdfDownloadUrl);
  const pdfDl = (payload) => pdfDlRaw({data: payload, auth: studentCtx});
  const resUrlRaw = test.wrap(functions.generateBunnyResourceUrl);
  const resUrl = (payload) => resUrlRaw({data: payload, auth: studentCtx});
  const listRaw = test.wrap(functions.getLectureResources);
  const list = (payload) => listRaw({data: payload, auth: studentCtx});

  await db.collection("users").doc(STUDENT).set({
    role: "student",
    student_type: "center_student",
    approval_status: "approved",
    account_status: "active",
  });

  const plans = {free: "pcont_plan_free", pro: "pcont_plan_pro", max: "pcont_plan_max"};
  await db.collection("plans").doc(plans.free).set({plan_key: "center_free", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.pro).set({plan_key: "center_pro", student_type: "center_student", is_active: true});
  await db.collection("plans").doc(plans.max).set({plan_key: "center_max", student_type: "center_student", is_active: true});
  const features = [
    [plans.free, "device.max_count", 1], [plans.pro, "device.max_count", 1], [plans.max, "device.max_count", 2],
    [plans.free, "video.access", true], [plans.pro, "video.access", true], [plans.max, "video.access", true],
    [plans.free, "video.quality.720p", true], [plans.pro, "video.quality.720p", true], [plans.max, "video.quality.720p", true],
    [plans.free, "pdf.access", true], [plans.pro, "pdf.access", true], [plans.max, "pdf.access", true],
    [plans.free, "pdf.download", true], [plans.pro, "pdf.download", true], [plans.max, "pdf.download", true],
    [plans.free, "attachment.access", true], [plans.pro, "attachment.access", true], [plans.max, "attachment.access", true],
  ];
  for (const [planId, key, value] of features) {
    await db.collection("plan_features").doc(`pcont_feat_${planId}_${key}`).set({
      plan_id: planId, feature_key: key, feature_value: value, enabled: true,
    });
  }

  const subjectPlan = {[SUB_V]: plans.free, [SUB_P]: plans.pro, [SUB_M]: plans.max};
  for (const [subjectId, planId] of Object.entries(subjectPlan)) {
    await db.collection("subjects").doc(subjectId).set({title: subjectId});
    await db.collection("subject_sections").doc(`pcont_sec_${subjectId}`).set({subject_id: subjectId});
    await db.collection("subject_access_assignments").doc(`${STUDENT}_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, enabled: true, is_deleted: false,
    });
    await db.collection("subscriptions").doc(`pcont_sub_${subjectId}`).set({
      student_id: STUDENT, subject_id: subjectId, plan_id: planId, status: "active",
    });
  }

  async function seedLecture(lectureId, subjectId, guestEnabled, guestMinutes) {
    await db.collection("lectures").doc(lectureId).set({
      subject_id: subjectId,
      section_id: `pcont_sec_${subjectId}`,
      status: "published",
      is_deleted: false,
      guest_enabled: guestEnabled,
      guest_preview_minutes: guestMinutes,
    });
  }
  // Lectures: V (Free, Guest preview 5min), P (Pro, Guest preview 3min),
  // M (Max, Guest preview enabled), NG (no Guest preview), DENY (explicit deny).
  await seedLecture("pcont_lecV", SUB_V, true, 5);
  await seedLecture("pcont_lecP", SUB_P, true, 3);
  await seedLecture("pcont_lecM", SUB_M, true, 4);
  await seedLecture("pcont_lecNG", SUB_V, false, null);
  await seedLecture("pcont_lecDeny", SUB_V, true, 5);
  await db.collection("lecture_access_grants").doc(`pcont_lecDeny_${STUDENT}`).set({
    lecture_id: "pcont_lecDeny", student_id: STUDENT, allowed: false, is_deleted: false,
  });

  await db.collection("lecture_resources").doc("pcont_vidV").set({
    lecture_id: "pcont_lecV", resource_type: "video", bunny_video_id: "pcont-vid-V",
    is_visible: true, display_order: 1,
  });
  await db.collection("lecture_resources").doc("pcont_pdfV").set({
    lecture_id: "pcont_lecV", resource_type: "pdf", storage_path: "docs/pcont-v.pdf",
    title: "V notes", is_visible: true, display_order: 2,
  });
  await db.collection("lecture_resources").doc("pcont_vidP").set({
    lecture_id: "pcont_lecP", resource_type: "video", bunny_video_id: "pcont-vid-P",
    is_visible: true, display_order: 1,
  });
  await db.collection("lecture_resources").doc("pcont_pdfP").set({
    lecture_id: "pcont_lecP", resource_type: "pdf", storage_path: "docs/pcont-p.pdf",
    title: "P notes", is_visible: true, display_order: 2,
  });
  await db.collection("lecture_resources").doc("pcont_vidM").set({
    lecture_id: "pcont_lecM", resource_type: "video", bunny_video_id: "pcont-vid-M",
    is_visible: true, display_order: 1,
  });
  await db.collection("lecture_resources").doc("pcont_attM").set({
    lecture_id: "pcont_lecM", resource_type: "attachment", storage_provider: "bunny",
    storage_path: "res/pcont-m.zip", title: "M pack", is_visible: true, display_order: 2,
  });
  await db.collection("lecture_resources").doc("pcont_vidDeny").set({
    lecture_id: "pcont_lecDeny", resource_type: "video", bunny_video_id: "pcont-vid-Deny",
    is_visible: true, display_order: 1,
  });
  await db.collection("lecture_resources").doc("pcont_vidNG").set({
    lecture_id: "pcont_lecNG", resource_type: "video", bunny_video_id: "pcont-vid-NG",
    is_visible: true, display_order: 1,
  });

  async function authzCount(subjectId) {
    return (await db.collection("subject_device_authorizations")
      .where("student_id", "==", STUDENT)
      .where("subject_id", "==", subjectId)
      .where("status", "==", "active").get()).size;
  }

  // 1. Full authorized Free device can access permitted video.
  const r1 = await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-A"});
  assert.ok(r1.url.includes("cdn.example.com"), "Signed URL issued");
  assert.equal(r1.quality, "720p");
  assert.ok(!("previewLimitSeconds" in r1), "Full response keeps its existing shape");
  console.log("ok 1 - Full Free video URL issued");

  // 2. Second Free device resolves Guest (limited preview URL, no record).
  const before2 = await authzCount(SUB_V);
  const r2 = await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-B"});
  assert.equal(r2.previewLimitSeconds, 300, "Guest preview from per-lecture minutes");
  assert.equal(await authzCount(SUB_V), before2, "Guest issuance binds nothing");
  console.log("ok 2 - Second Free device Guest with preview cap");

  // 3. Full authorized Pro device: full listing + video without preview cap.
  const l3 = await list({lectureId: "pcont_lecP", deviceId: "pcont-test-device-A"});
  assert.ok(l3.resources.some((r) => r.resourceType === "pdf"), "Full listing includes protected PDF");
  assert.equal(l3.guestPreview, null, "No preview cap on Full tier");
  const r3 = await videoUrl({videoId: "pcont-vid-P", deviceId: "pcont-test-device-A"});
  assert.ok(!("previewLimitSeconds" in r3), "Full video has no preview cap");
  console.log("ok 3 - Full Pro protected content intact");

  // 4. Second Pro device resolves Guest.
  const r4 = await videoUrl({videoId: "pcont-vid-P", deviceId: "pcont-test-device-B"});
  assert.equal(r4.previewLimitSeconds, 180, "Guest preview from per-lecture minutes");
  console.log("ok 4 - Second Pro device Guest");

  // 5/6. First two Max devices resolve Full.
  const r5 = await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-A"});
  const r6 = await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-B"});
  assert.ok(!("previewLimitSeconds" in r5) && !("previewLimitSeconds" in r6));
  console.log("ok 5/6 - First two Max devices Full");

  // 7. Third Max device Guest (preview, no record).
  const before7 = await authzCount(SUB_M);
  const r7 = await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-C"});
  assert.equal(r7.previewLimitSeconds, 240);
  assert.equal(await authzCount(SUB_M), before7);
  console.log("ok 7 - Third Max device Guest");

  // 8/9. Guest cannot receive protected PDF view, PDF download, or resource.
  // (devC holds nothing on SUB_P, so it resolves Guest there.)
  await expectCode(pdfView({resourceId: "pcont_pdfP", deviceId: "pcont-test-device-C"}), "permission-denied", "guest pdf view");
  await expectCode(pdfDl({resourceId: "pcont_pdfP", deviceId: "pcont-test-device-C"}), "permission-denied", "guest pdf download");
  await expectCode(resUrl({resourceId: "pcont_attM", deviceId: "pcont-test-device-C"}), "permission-denied", "guest resource");
  console.log("ok 8/9 - Guest denied protected PDF/download/resource");

  // 10/11. Explicit lecture deny blocks Full and Guest alike.
  await expectCode(videoUrl({videoId: "pcont-vid-Deny", deviceId: "pcont-test-device-A"}), "permission-denied", "deny blocks Full");
  await expectCode(videoUrl({videoId: "pcont-vid-Deny", deviceId: "pcont-test-device-ZZZ"}), "permission-denied", "deny blocks Guest");
  console.log("ok 10/11 - Explicit deny overrides both tiers");

  // Guest on a preview-disabled lecture is denied (never upgraded).
  await expectCode(videoUrl({videoId: "pcont-vid-NG", deviceId: "pcont-test-device-B"}), "permission-denied", "no-preview lecture denies Guest");

  // 12/13. Disabled assignment and inactive subscription block access.
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_V}`).update({enabled: false});
  await expectCode(videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-A"}), "permission-denied", "disabled assignment");
  await db.collection("subject_access_assignments").doc(`${STUDENT}_${SUB_V}`).update({enabled: true});
  await db.collection("subscriptions").doc(`pcont_sub_${SUB_V}`).update({status: "expired"});
  await expectCode(videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-A"}), "permission-denied", "expired subscription");
  await db.collection("subscriptions").doc(`pcont_sub_${SUB_V}`).update({status: "active"});
  console.log("ok 12/13 - Disabled assignment and expired subscription block");

  // 14. Subject A authorization does not authorize Subject B: devV holds
  // nothing anywhere (V slots are held by devA), so its P listing is Guest.
  const totalBefore14 = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).get()).size;
  await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-V"});
  assert.equal(
    (await db.collection("subject_device_authorizations").where("student_id", "==", STUDENT).get()).size,
    totalBefore14,
    "Guest resolutions create no records",
  );
  const l14 = await list({lectureId: "pcont_lecP", deviceId: "pcont-test-device-V"});
  assert.ok(!l14.resources.some((r) => r.resourceType === "pdf"), "Guest listing hides protected PDFs");
  assert.ok(l14.resources.some((r) => r.resourceType === "video"), "Guest listing keeps video");
  assert.ok(l14.guestPreview && l14.guestPreview.previewLimitSeconds === 180, "Guest listing carries preview cap");
  console.log("ok 14 - Tier-aware listing isolates Subjects");

  // 15. Higher plan does not uplift: reset, bind devM on Max subject M
  // (Full), bind devA on Free subject V (Full), then devM on V resolves
  // Guest even though it is Full on Max.
  const resetRaw = test.wrap(functions.resetStudentDevices);
  await resetRaw({data: {studentId: STUDENT, reason: "pcont-test15-setup"},
    auth: {uid: "pcont-teacher", token: {role: "teacher"}}});
  await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-M"});
  await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-A"});
  const r15 = await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-M"});
  assert.equal(r15.previewLimitSeconds, 300, "Max device is Guest on the Free subject");
  console.log("ok 15 - No cross-Subject uplift");

  // 16/17. Forgery attempts: fabricated tier/plan/allowance fields and
  // unknown devices never yield Full.
  const r16 = await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-forged", tier: "full", plan_id: "pcont_plan_max", max_devices: 99, subscription_status: "active"});
  assert.equal(r16.previewLimitSeconds, 300, "Client-supplied tier/plan fields ignored");
  // Fill the remaining Max slot first (post-reset state: devM holds one).
  await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-ZZZ"});
  const l17 = await list({lectureId: "pcont_lecM", deviceId: "pcont-test-device-V"});
  assert.ok(!l17.resources.some((r) => r.resourceType === "attachment"), "V-only device sees no Max attachments");
  console.log("ok 16/17 - Forgery impossible via client input");

  // 18. Authorization failure never defaults to Full.
  await expectCode(videoUrl({videoId: "pcont-nope", deviceId: "pcont-test-device-A"}), "not-found", "unknown video is not Full");
  await expectCode(pdfView({resourceId: "pcont_pdfV"}), "invalid-argument", "missing deviceId is not Full");
  console.log("ok 18 - Failures never default to Full");

  // 19. Existing legitimate Full-access behavior intact (no deviceId path).
  const l19 = await list({lectureId: "pcont_lecV"});
  assert.ok(l19.resources.some((r) => r.resourceType === "pdf"), "Legacy listing unchanged");
  console.log("ok 19 - Legacy behavior intact");

  // 20. Guest mutates nothing.
  const subsBefore = (await db.collection("subscriptions").where("student_id", "==", STUDENT).get())
    .docs.map((d) => ({id: d.id, ...d.data()}));
  const authzBefore = (await db.collection("subject_device_authorizations")
    .where("student_id", "==", STUDENT).get()).size;
  await videoUrl({videoId: "pcont-vid-V", deviceId: "pcont-test-device-B"});
  await videoUrl({videoId: "pcont-vid-M", deviceId: "pcont-test-device-C"});
  await pdfView({resourceId: "pcont_pdfM", deviceId: "pcont-test-device-C"}).catch(() => null);
  const subsAfter = (await db.collection("subscriptions").where("student_id", "==", STUDENT).get())
    .docs.map((d) => ({id: d.id, ...d.data()}));
  assert.deepEqual(subsAfter, subsBefore, "Subscriptions untouched by Guest");
  assert.equal(
    (await db.collection("subject_device_authorizations").where("student_id", "==", STUDENT).get()).size,
    authzBefore,
    "Authorizations untouched by Guest",
  );
  console.log("ok 20 - Guest mutates nothing");

  test.cleanup();
  console.log("protected_content.test: PASS - all 20 scenarios verified against Firestore Emulator");
}

run().catch((e) => {
  console.error("Test failed:", e);
  process.exit(1);
});
