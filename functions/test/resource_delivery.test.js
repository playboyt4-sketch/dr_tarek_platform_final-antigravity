/**
 * Unit tests for the storage-delivery completion (audit Fix 1 + Fix 2).
 *
 * Covers the exported pure policy helpers:
 *  - isDocumentResourceType: the pdf|attachment type gate that generalized
 *    resolvePdfAccess into resolveDocumentAccess (attachments were
 *    previously rejected outright by every delivery callable).
 *  - documentFeatureKeys: verifies the ratified per-capability key
 *    independence — attachments gate on dedicated attachment.access /
 *    attachment.download keys, never inheriting pdf.*.
 *  - isDirectThumbnailUrl: legacy full-URL thumbnails pass through
 *    unsigned; stored paths get provider-signed inside getLectureResources.
 *
 * The firebase-admin surface is stubbed exactly like academic_periods.test.js
 * so lib/index.js can be loaded without an emulator or real project.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({collection: () => { throw new Error("not used"); }}),
  getAuth: () => ({}),
  getMessaging: () => ({}),
  getStorage: () => ({}),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
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
  if (id === "firebase-admin/messaging") {
    return {getMessaging: adminMock.getMessaging};
  }
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

let passed = 0;
function check(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`FAIL - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

// ---- Fix 1: attachment type gate --------------------------------------
check("isDocumentResourceType accepts pdf and attachment", () => {
  assert.equal(functions.isDocumentResourceType("pdf"), true);
  assert.equal(functions.isDocumentResourceType("attachment"), true);
});
check("isDocumentResourceType rejects non-document types", () => {
  assert.equal(functions.isDocumentResourceType("video"), false);
  assert.equal(functions.isDocumentResourceType("external_link"), false);
  assert.equal(functions.isDocumentResourceType(""), false);
  assert.equal(functions.isDocumentResourceType(null), false);
  assert.equal(functions.isDocumentResourceType(undefined), false);
  assert.equal(functions.isDocumentResourceType(42), false);
});

// ---- Fix 1: feature-key independence (RATIFIED RULE) ------------------
// Every capability has its OWN independent Feature Matrix key — nothing is
// shared or inherited between content types. Attachments gate on dedicated
// attachment.* keys; PDFs keep pdf.*.
check("documentFeatureKeys returns DEDICATED keys per content type", () => {
  assert.deepEqual(functions.documentFeatureKeys("pdf"),
    {view: "pdf.access", download: "pdf.download"});
  assert.deepEqual(functions.documentFeatureKeys("attachment"),
    {view: "attachment.access", download: "attachment.download"});
});
check("attachments never inherit pdf.* keys", () => {
  const attachmentKeys = functions.documentFeatureKeys("attachment");
  assert.notEqual(attachmentKeys.view, functions.documentFeatureKeys("pdf").view);
  assert.notEqual(attachmentKeys.download, functions.documentFeatureKeys("pdf").download);
});

// ---- Fix 2: thumbnail passthrough policy ------------------------------
check("isDirectThumbnailUrl accepts legacy http(s) URLs", () => {
  assert.equal(functions.isDirectThumbnailUrl("https://example.com/t.jpg"), true);
  assert.equal(functions.isDirectThumbnailUrl("HTTP://cdn.example.com/x.png"), true);
});
check("isDirectThumbnailUrl rejects stored paths", () => {
  assert.equal(
    functions.isDirectThumbnailUrl("lecture_resources/lec-1/res-1/thumb.jpg"),
    false,
  );
  assert.equal(functions.isDirectThumbnailUrl(""), false);
});

test.cleanup();
if (process.exitCode === 1) {
  console.error("resource_delivery tests FAILED");
  process.exit(1);
}
console.log(`resource_delivery tests passed (${passed}/6 groups).`);
