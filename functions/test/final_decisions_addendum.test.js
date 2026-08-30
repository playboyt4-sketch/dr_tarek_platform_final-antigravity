/**
 * Pure-logic tests for the ratified FINAL_DECISIONS §11–15 addendum
 * functions (Part C preview policy + Part D scheduled auto-publish).
 * These run against the COMPILED output (functions/lib/index.js), mirroring
 * the existing node test convention in this repo.
 */
const assert = require("assert");
const {resolvePublicFreePreviewSeconds, pickDueLectures} = require("../lib/index.js");

function testPreviewPolicy() {
  // Gate not armed → not applicable.
  assert.strictEqual(
    resolvePublicFreePreviewSeconds({
      publicFreeEnabled: false,
      lectureMinutes: 10,
      planDefaultMinutes: 5,
    }),
    null,
    "disabled gate must return null",
  );

  // Per-lecture minutes win over the plan default.
  assert.strictEqual(
    resolvePublicFreePreviewSeconds({
      publicFreeEnabled: true,
      lectureMinutes: 7,
      planDefaultMinutes: 3,
    }),
    420,
    "lecture minutes must override the plan default",
  );

  // Null lecture minutes fall back to the plan default.
  assert.strictEqual(
    resolvePublicFreePreviewSeconds({
      publicFreeEnabled: true,
      lectureMinutes: null,
      planDefaultMinutes: 12,
    }),
    720,
    "plan default applies when lecture minutes are unset",
  );

  // Neither source set → zero cap (immediate upgrade wall, never unlimited).
  assert.strictEqual(
    resolvePublicFreePreviewSeconds({
      publicFreeEnabled: true,
      lectureMinutes: null,
      planDefaultMinutes: null,
    }),
    0,
    "missing configuration must cap at zero, not infinity",
  );

  console.log("preview policy tests passed.");
}

function testAutoPublishPicker() {
  const now = Date.now();
  const docs = [
    {id: "due-1", status: "draft", isDeleted: false, publishDateMs: now - 1000},
    {id: "due-2", status: "draft", isDeleted: false, publishDateMs: now - 60000},
    {id: "future", status: "draft", isDeleted: false, publishDateMs: now + 3600000},
    {id: "published", status: "published", isDeleted: false, publishDateMs: now - 1000},
    {id: "archived", status: "draft", isDeleted: true, publishDateMs: now - 1000},
    {id: "no-date", status: "draft", isDeleted: false, publishDateMs: null},
  ];

  const due = pickDueLectures(docs, now);
  assert.deepStrictEqual(
    due,
    ["due-1", "due-2"],
    "only past-due drafts flip; future/published/archived/undated stay",
  );

  // Boundary: publish_date exactly now IS due.
  assert.deepStrictEqual(
    pickDueLectures(
      [{id: "edge", status: "draft", isDeleted: false, publishDateMs: now}],
      now,
    ),
    ["edge"],
    "publish_date == now must be considered due",
  );

  console.log("auto-publish picker tests passed.");
}

testPreviewPolicy();
testAutoPublishPicker();
