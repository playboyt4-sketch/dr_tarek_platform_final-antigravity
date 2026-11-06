/**
 * Lecture publication → resource visibility regression tests.
 *
 * Root cause covered: resources authored while a lecture is a draft are
 * stored hidden (`is_visible: false`). The student listing/serving gate only
 * returns visible rows, so publishing the lecture must republish those rows.
 * Before the fix the scheduler flipped only `lectures.status`, leaving every
 * row hidden and playback failing with
 * "No published video source found for this lecture".
 *
 * Part 1 — pure unit tests for the canonical first-video projection.
 * Part 2 — emulator end-to-end run of `publishDueLectures(now)`.
 *
 * Run inside `firebase emulators:exec --only firestore,auth ...`.
 * The end-to-end part is skipped automatically when no emulator host is set.
 */
const assert = require("node:assert/strict");

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

let passed = 0;
let failed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

function resource(id, overrides = {}) {
  return {
    id,
    data: {
      resource_type: "video",
      title: id,
      display_order: 0,
      bunny_video_id: "11111111-1111-4111-8111-111111111111",
      is_visible: true,
      is_deleted: false,
      ...overrides,
    },
  };
}

(async () => {
  console.log("=== firstVideoFieldsFromResources (pure) ===");
  await check("empty resources → null", () => {
    assert.equal(functions.firstVideoFieldsFromResources([]), null);
  });
  await check("skips non-video, hidden, deleted and empty Bunny ids", () => {
    const winner = functions.firstVideoFieldsFromResources([
      resource("pdf", {resource_type: "pdf"}),
      resource("hidden", {is_visible: false}),
      resource("deleted", {is_deleted: true}),
      resource("empty", {bunny_video_id: "   "}),
      resource("ok"),
    ]);
    assert.equal(winner.resource_id, "ok");
  });
  await check("lowest display_order wins", () => {
    const winner = functions.firstVideoFieldsFromResources([
      resource("later", {display_order: 5}),
      resource("first", {display_order: 1}),
    ]);
    assert.equal(winner.resource_id, "first");
    assert.equal(winner.display_order, 1);
  });
  await check("display_order tie breaks on document id ascending", () => {
    const winner = functions.firstVideoFieldsFromResources([
      resource("zzz", {display_order: 2}),
      resource("aaa", {display_order: 2}),
    ]);
    assert.equal(winner.resource_id, "aaa");
  });
  await check("serializes identity fields only", () => {
    const winner = functions.firstVideoFieldsFromResources([resource("v")]);
    assert.deepEqual(winner, {
      resource_id: "v",
      bunny_video_id: "11111111-1111-4111-8111-111111111111",
      title: "v",
      display_order: 0,
      thumbnail_path: null,
      thumbnail_storage_provider: null,
    });
  });
  await check("keeps the winner's raw poster path and provider", () => {
    const winner = functions.firstVideoFieldsFromResources([
      resource("v", {
        thumbnail: "lectures/v/poster.jpg",
        thumbnail_storage_provider: "bunny",
      }),
      resource("w", {display_order: 3}),
    ]);
    assert.equal(winner.thumbnail_path, "lectures/v/poster.jpg");
    assert.equal(winner.thumbnail_storage_provider, "bunny");
  });

  if (!EMULATOR_HOST) {
    console.log(
      "SKIP - publishDueLectures end-to-end (FIRESTORE_EMULATOR_HOST unset)",
    );
  } else {
    console.log("=== publishDueLectures (emulator) ===");
    const admin = require("firebase-admin");
    try {
      admin.app();
    } catch (error) {
      admin.initializeApp({projectId: process.env.GCLOUD_PROJECT});
    }
    const db = admin.firestore();

    await check("due lecture publishes its hidden resources", async () => {
      const lectureRef = db.collection("lectures").doc("visrepair_due");
      await lectureRef.set({
        subject_id: "sub-1",
        section_id: "sec-1",
        title: "Scheduled",
        display_order: 0,
        status: "draft",
        is_deleted: false,
        publish_date: new Date(Date.now() - 60_000),
      });
      await db.collection("lecture_resources").doc("visrepair_video").set({
        lecture_id: lectureRef.id,
        resource_type: "video",
        title: "V",
        display_order: 0,
        bunny_video_id: "11111111-1111-4111-8111-111111111111",
        is_visible: false,
        visibility: false,
        is_deleted: false,
      });
      await db.collection("lecture_resources").doc("visrepair_pdf").set({
        lecture_id: lectureRef.id,
        resource_type: "pdf",
        title: "P",
        display_order: 1,
        is_visible: false,
        visibility: false,
        is_deleted: false,
      });

      const count = await functions.publishDueLectures(Date.now());
      assert.ok(count >= 1, `expected at least one publish, got ${count}`);

      const lecture = (await lectureRef.get()).data();
      assert.equal(lecture.status, "published");
      assert.equal(lecture.first_video.resource_id, "visrepair_video");
      assert.equal(
        lecture.first_video.bunny_video_id,
        "11111111-1111-4111-8111-111111111111",
      );

      const video = (
        await db.collection("lecture_resources").doc("visrepair_video").get()
      ).data();
      assert.equal(video.is_visible, true);
      assert.equal(video.visibility, true);
      const pdf = (
        await db.collection("lecture_resources").doc("visrepair_pdf").get()
      ).data();
      assert.equal(pdf.is_visible, true);
    });

    await check("future scheduled lecture stays hidden", async () => {
      const lectureRef = db.collection("lectures").doc("visrepair_future");
      await lectureRef.set({
        subject_id: "sub-1",
        section_id: "sec-1",
        title: "Future",
        display_order: 0,
        status: "draft",
        is_deleted: false,
        publish_date: new Date(Date.now() + 60 * 60 * 1000),
      });
      await db.collection("lecture_resources").doc("visrepair_future_v").set({
        lecture_id: lectureRef.id,
        resource_type: "video",
        title: "V",
        display_order: 0,
        bunny_video_id: "22222222-2222-4222-8222-222222222222",
        is_visible: false,
        visibility: false,
        is_deleted: false,
      });

      await functions.publishDueLectures(Date.now());
      const lecture = (await lectureRef.get()).data();
      assert.equal(lecture.status, "draft");
      const video = (
        await db
          .collection("lecture_resources")
          .doc("visrepair_future_v")
          .get()
      ).data();
      assert.equal(video.is_visible, false);
    });
  }

  console.log(`\n${passed} passed, ${failed} failed`);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
