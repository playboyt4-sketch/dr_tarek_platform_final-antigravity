/**
 * First-video backfill tests (Phase 4).
 *
 * Part 1 — pure unit tests over the script-local canonical helpers in
 * scripts/backfill_first_video.cjs (no Firestore, no emulator needed;
 * the module has no side effects on require).
 *
 * Part 2 — emulator end-to-end: seeds lectures/resources, executes the
 * script with --apply as a child process (it honors FIRESTORE_EMULATOR_HOST
 * like every migration script), then asserts first_video documents,
 * unrelated-field preservation, and rerun idempotency.
 *
 * Run inside `firebase emulators:exec` (firestore only):
 *   firebase emulators:exec --project demo-tarek-platform --only firestore,auth \
 *     "node test/first_video_backfill.test.js"
 * NEVER against production (the script defaults to dry-run; this file
 * always passes --apply explicitly and only under the emulator).
 */
const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const test = require("firebase-functions-test")();
const admin = require("firebase-admin");

// Unlike suites that call test.wrap() first (which lazily initializes the
// Admin app), this file uses admin.firestore() directly for seeding, so
// initialize explicitly. Under emulators:exec the emulator env routes it
// to the Firestore emulator; nothing touches production.
try {
  admin.app();
} catch (error) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || "demo-test",
  });
}

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-test";

const backfill = require("../../scripts/backfill_first_video.cjs");

let passed = 0;
function check(name, fn) {
  try {
    const result = fn();
    if (result && typeof result.then === "function") {
      return result.then(
        () => {
          passed += 1;
          console.log(`ok - ${name}`);
        },
        (error) => {
          console.error(`FAIL - ${name}`);
          console.error(error);
          process.exitCode = 1;
        },
      );
    }
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
  return undefined;
}

// ---- Part 1: pure canonical semantics --------------------------------
check("eligible video passes", () => {
  assert.equal(
    backfill.isFirstVideoEligible("v1", {
      resource_type: "video",
      is_visible: true,
      is_deleted: false,
      bunny_video_id: "bunny-1",
      display_order: 0,
    }),
    true,
  );
});

check("invisible / deleted / wrong-type fail", () => {
  const base = {
    resource_type: "video",
    is_visible: true,
    is_deleted: false,
    bunny_video_id: "bunny-1",
  };
  assert.equal(backfill.isFirstVideoEligible("v", {...base, is_visible: false}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, is_visible: null}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, is_deleted: true}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, resource_type: "pdf"}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, resource_type: "attachment"}), false);
});

check("missing / empty / blank bunny id fails", () => {
  const base = {resource_type: "video", is_visible: true, is_deleted: false};
  assert.equal(backfill.isFirstVideoEligible("v", {...base}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, bunny_video_id: null}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, bunny_video_id: ""}), false);
  assert.equal(backfill.isFirstVideoEligible("v", {...base, bunny_video_id: "   "}), false);
  assert.equal(backfill.isFirstVideoEligible("v", null), false);
  assert.equal(backfill.isFirstVideoEligible("v", 42), false);
});

check("lowest display_order wins; id breaks ties", () => {
  const pick = (docs) =>
    backfill.selectFirstVideo(docs.map(([id, data]) => ({id, data})));
  assert.equal(
    pick([["v9", {resource_type: "video", is_visible: true, bunny_video_id: "b9", display_order: 9}], ["v2", {resource_type: "video", is_visible: true, bunny_video_id: "b2", display_order: 2}]]).id,
    "v2",
  );
  assert.equal(
    pick([["v-b", {resource_type: "video", is_visible: true, bunny_video_id: "bb", display_order: 3}], ["v-a", {resource_type: "video", is_visible: true, bunny_video_id: "ba", display_order: 3}]]).id,
    "v-a",
  );
  assert.equal(pick([]), null);
  assert.equal(
    pick([["p", {resource_type: "pdf", is_visible: true, display_order: 0}]]),
    null,
  );
});

check("missing display_order defaults to zero, not NaN", () => {
  const winner = backfill.selectFirstVideo([
    {id: "v", data: {resource_type: "video", is_visible: true, bunny_video_id: "b"}},
  ]);
  assert.equal(winner.id, "v");
  assert.equal(backfill.firstVideoFields(winner).display_order, 0);
});

check("firstVideoFields carries identity only, thumbnails when authoritative", () => {
  const fields = backfill.firstVideoFields({
    id: "res-1",
    data: {
      bunny_video_id: "  bunny-1  ",
      title: " V ",
      display_order: 2,
      thumbnail: "thumbs/r.jpg",
      thumbnail_storage_provider: "firebase",
    },
  });
  assert.deepEqual(fields, {
    resource_id: "res-1",
    bunny_video_id: "bunny-1",
    title: "V",
    display_order: 2,
    thumbnail_path: "thumbs/r.jpg",
    thumbnail_storage_provider: "firebase",
  });
  const bare = backfill.firstVideoFields({
    id: "res-2",
    data: {bunny_video_id: "bunny-2", title: null, thumbnail: ""},
  });
  assert.equal(bare.thumbnail_path, null);
  assert.equal(bare.thumbnail_storage_provider, null);
  assert.ok(!("resource_url" in bare) && !("storage_path" in bare));
});

check("sameFirstVideo compares normalized values", () => {
  assert.equal(backfill.sameFirstVideo(null, null), true);
  assert.equal(backfill.sameFirstVideo({resource_id: "a"}, null), false);
  assert.equal(backfill.sameFirstVideo(null, {resource_id: "a"}), false);
  const full = {
    resource_id: "r", bunny_video_id: "b", title: "t", display_order: 1,
    thumbnail_path: null, thumbnail_storage_provider: null,
  };
  assert.equal(backfill.sameFirstVideo({...full}, {...full}), true);
  assert.equal(
    backfill.sameFirstVideo({...full, display_order: 1}, {...full, display_order: 2}),
    false,
  );
});

// ---- Part 2: emulator end-to-end --------------------------------------
async function seed(db) {
  const lectures = [
    "bf_lec1", "bf_lec2", "bf_lec3", "bf_lec4", "bf_lec5",
    "bf_lec6", "bf_lec7", "bf_lec8",
  ];
  for (const id of lectures) {
    await db.collection("lectures").doc(id).set({
      subject_id: "bf_sub",
      section_id: "bf_sec",
      title: `Lecture ${id}`,
      status: "published",
      is_deleted: false,
      display_order: 1,
    });
  }
  // Stale pointers that must be repaired.
  await db.collection("lectures").doc("bf_lec1").update({
    first_video: {resource_id: "stale", bunny_video_id: "stale"},
  });
  await db.collection("lectures").doc("bf_lec6").update({
    first_video: {resource_id: "stale", bunny_video_id: "stale"},
  });
  const res = async (id, lectureId, patch) => {
    await db.collection("lecture_resources").doc(id).set({
      lecture_id: lectureId,
      resource_type: "video",
      title: `R ${id}`,
      display_order: 0,
      bunny_video_id: "bunny-default",
      thumbnail: null,
      is_visible: true,
      visibility: true,
      is_deleted: false,
      ...patch,
    });
  };
  await res("bf_v9", "bf_lec1", {display_order: 9, bunny_video_id: "bunny-9"});
  await res("bf_v2", "bf_lec1", {display_order: 2, bunny_video_id: "bunny-2"});
  await res("bf_hidden", "bf_lec2", {display_order: 0, bunny_video_id: "bunny-h"});
  await db.collection("lecture_resources").doc("bf_hidden").update({is_visible: false});
  await res("bf_vis", "bf_lec2", {display_order: 1, bunny_video_id: "bunny-v"});
  await res("bf_del", "bf_lec3", {display_order: 0, bunny_video_id: "bunny-d"});
  await db.collection("lecture_resources").doc("bf_del").update({is_deleted: true});
  await res("bf_live", "bf_lec3", {display_order: 3, bunny_video_id: "bunny-l"});
  await res("bf_empty", "bf_lec4", {display_order: 0, bunny_video_id: ""});
  await res("bf_null", "bf_lec4", {display_order: 1, bunny_video_id: null});
  await res("bf_ok", "bf_lec4", {display_order: 4, bunny_video_id: "bunny-ok"});
  await res("bf_zzz", "bf_lec5", {display_order: 2, bunny_video_id: "bunny-z"});
  await res("bf_aaa", "bf_lec5", {display_order: 2, bunny_video_id: "bunny-a"});
  await res("bf_pdf", "bf_lec6", {resource_type: "pdf"});
  // bf_lec7: no resources at all.
  await res("bf_thumb", "bf_lec8", {
    display_order: 0,
    bunny_video_id: "bunny-t",
    thumbnail: "thumbs/bf.jpg",
    thumbnail_storage_provider: "bunny",
  });
}

function runScript(args) {
  const script = path.join(__dirname, "..", "..", "scripts", "backfill_first_video.cjs");
  return spawnSync("node", [script, ...args], {encoding: "utf8"});
}

async function run() {
  const db = admin.firestore();
  await seed(db);

  const first = runScript(["--apply"]);
  assert.equal(first.status, 0, `script --apply failed:\n${first.stdout}\n${first.stderr}`);
  const out = first.stdout;
  // NOTE: under the unified runner the emulator is shared with earlier
  // suites, so other lectures may exist and be (correctly) backfilled too.
  // Assert minimums for our seeded matrix, not absolute totals.
  const countOf = (label) => {
    const match = out.match(new RegExp(`${label}: (\\d+)`));
    assert.ok(match, `summary missing "${label}" in:\n${out}`);
    return parseInt(match[1], 10);
  };
  assert.ok(countOf("lectures scanned") >= 8);
  assert.ok(countOf("first_video assigned") >= 6);
  assert.ok(countOf("first_video cleared") >= 1);

  const fv = async (lectureId) => {
    const snap = await db.collection("lectures").doc(lectureId).get();
    return snap.data()?.first_video ?? null;
  };
  assert.equal((await fv("bf_lec1")).resource_id, "bf_v2");
  assert.equal((await fv("bf_lec1")).bunny_video_id, "bunny-2");
  assert.equal((await fv("bf_lec2")).resource_id, "bf_vis");
  assert.equal((await fv("bf_lec3")).resource_id, "bf_live");
  assert.equal((await fv("bf_lec4")).resource_id, "bf_ok");
  assert.equal((await fv("bf_lec5")).resource_id, "bf_aaa");
  assert.equal(await fv("bf_lec6"), null);
  assert.equal(await fv("bf_lec7"), null);
  const thumb = await fv("bf_lec8");
  assert.equal(thumb.thumbnail_path, "thumbs/bf.jpg");
  assert.equal(thumb.thumbnail_storage_provider, "bunny");

  // Unrelated lecture fields untouched.
  const lec1 = (await db.collection("lectures").doc("bf_lec1").get()).data();
  assert.equal(lec1.title, "Lecture bf_lec1");
  assert.equal(lec1.status, "published");
  assert.equal(lec1.subject_id, "bf_sub");

  // Rerun converges: everything already correct → zero writes.
  const second = runScript(["--apply"]);
  assert.equal(second.status, 0, `rerun failed:\n${second.stdout}\n${second.stderr}`);
  assert.ok(
    second.stdout.includes("lectures updated: 0"),
    `rerun not idempotent:\n${second.stdout}`,
  );
  console.log("ok - emulator end-to-end: selection, repair, preservation, idempotency");
  passed += 1;

  test.cleanup();
  console.log(`first_video_backfill tests passed (${passed} groups).`);
}

run().catch((error) => {
  console.error("Test failed:", error);
  process.exit(1);
});
