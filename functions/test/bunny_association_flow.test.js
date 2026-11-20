/**
 * ADR-010 — server-side verified association through the REAL callables.
 *
 * Emulator suite (Firestore + Functions). Proves that `bunny_library_id` can
 * only be persisted by the trusted callable, that the receipt is bound to one
 * exact resource/lecture/library/video, that every failure mode fails closed,
 * that the write is idempotent and keeps `first_video` consistent, and that a
 * post-cutover resource without a verified association cannot play while a
 * genuine legacy row still can.
 *
 * No Bunny network call is made: receipts are signed locally with the same
 * fixture secret the callable verifies with, and the metadata callable is not
 * part of this suite (it is covered by bunny_library_validation_flow).
 */
const test = require("firebase-functions-test")();

// Emulator suites must stay offline: any Bunny request fails the suite.
const bunnyGuard =
  require("./bunny_network_guard").installBunnyNetworkGuard();
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const path = require("node:path");

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-test";
process.env.BUNNY_PLAYBACK_URL_TEMPLATE = "https://example.com/{video_id}/{quality}";
process.env.BUNNY_TOKEN_KEY = "fixture-signing-key";
process.env.BUNNY_STREAM_API_KEY = "fixture-api-key";
process.env.BUNNY_STREAM_LIBRARY_ID = "736742";
// Library 775315 must stay INACTIVE (no allow-list entry).
delete process.env.BUNNY_ACTIVE_LIBRARY_IDS;
delete process.env.BUNNY_ASSOCIATION_CUTOVER;

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

const receiptLib = require(path.join(
  __dirname,
  "..",
  "lib",
  "core",
  "video",
  "bunny_library_association.js",
));

const associate = test.wrap(functions.associateBunnyVideoToLibrary);
const issueUrl = test.wrap(functions.generateBunnySignedUrl);
const db = admin.firestore();
const SECRET = "fixture-signing-key";

const DOCTOR = {uid: "u_assoc_doctor", token: {role: "doctor"}};
const ADMIN_ALLOWED = {uid: "u_assoc_admin_ok", token: {role: "admin"}};
const ADMIN_DENIED = {uid: "u_assoc_admin_no", token: {role: "admin"}};

const GUID_A = "aaaaaaaa-1111-4111-8111-111111111111";
const GUID_B = "bbbbbbbb-2222-4222-8222-222222222222";

async function expectCode(promise, code, name) {
  try {
    await promise;
  } catch (error) {
    assert.equal(
      error.code,
      code,
      `${name}: expected ${code}, got ${error.code} (${error.message})`,
    );
    console.log(`ok - ${name} (denied ${code})`);
    return error;
  }
  assert.fail(`${name}: expected denial ${code}, call succeeded`);
}

function receiptFor({
  resourceId,
  lectureId,
  libraryId = "736742",
  videoId,
  ttlSeconds = 600,
  secret = SECRET,
  issuedAtSeconds = Math.floor(Date.now() / 1000),
}) {
  return receiptLib.signBunnyAssociationReceipt({
    secret,
    resourceId,
    lectureId,
    libraryId,
    videoId,
    issuedAtSeconds,
    ttlSeconds,
  });
}

async function seedResource({
  id,
  lectureId,
  subjectId = "subj_assoc",
  resourceType = "video",
  videoId = null,
  libraryId = null,
  createdAtMs = Date.parse("2026-12-01T00:00:00.000Z"),
  displayOrder = 1,
  isVisible = true,
}) {
  const data = {
    lecture_id: lectureId,
    subject_id: subjectId,
    resource_type: resourceType,
    title: `Resource ${id}`,
    display_order: displayOrder,
    is_visible: isVisible,
    visibility: isVisible,
    is_deleted: false,
    created_at: admin.firestore.Timestamp.fromMillis(createdAtMs),
    updated_at: admin.firestore.Timestamp.fromMillis(createdAtMs),
  };
  if (videoId !== null) data.bunny_video_id = videoId;
  if (libraryId !== null) data.bunny_library_id = libraryId;
  await db.collection("lecture_resources").doc(id).set(data);
}

async function seedLecture({id, subjectId = "subj_assoc", isDeleted = false}) {
  await db.collection("lectures").doc(id).set({
    subject_id: subjectId,
    section_id: "sec_assoc",
    title: `Lecture ${id}`,
    status: "published",
    is_deleted: isDeleted,
    first_video: null,
  });
}

async function run() {
  console.log("Starting bunny_association_flow tests against emulator...");
  let passed = 0;
  const ok = (name) => {
    passed++;
    console.log(`ok - ${name}`);
  };

  await db.collection("admin_permissions").doc(ADMIN_ALLOWED.uid).set({
    admin_id: ADMIN_ALLOWED.uid,
    is_active: true,
    permissions: {admin_content: true},
  });
  await db.collection("admin_permissions").doc(ADMIN_DENIED.uid).set({
    admin_id: ADMIN_DENIED.uid,
    is_active: true,
    permissions: {admin_students: true},
  });

  const lec = "assoc_lec_1";
  const res = "assoc_res_1";
  await seedLecture({id: lec});
  await seedResource({id: res, lectureId: lec});

  const base = {
    resourceId: res,
    lectureId: lec,
    libraryId: "736742",
    videoId: GUID_A,
  };

  // 1. Unauthenticated.
  await expectCode(
    associate({data: {...base, receipt: receiptFor({...base})}}),
    "unauthenticated",
    "unauthenticated caller",
  );

  // 2. Unauthorized admin (no admin_content delegation).
  await expectCode(
    associate({
      data: {...base, receipt: receiptFor({...base})},
      auth: ADMIN_DENIED,
    }),
    "permission-denied",
    "admin without content delegation",
  );

  // 3..4. Wrong ids.
  await expectCode(
    associate({
      data: {
        ...base,
        resourceId: "assoc_res_missing",
        receipt: receiptFor({resourceId: "assoc_res_missing", lectureId: lec, videoId: GUID_A}),
      },
      auth: DOCTOR,
    }),
    "not-found",
    "unknown resource id",
  );
  await expectCode(
    associate({
      data: {
        ...base,
        lectureId: "assoc_lec_missing",
        receipt: receiptFor({resourceId: res, lectureId: "assoc_lec_missing", videoId: GUID_A}),
      },
      auth: DOCTOR,
    }),
    "not-found",
    "unknown lecture id",
  );

  // 5. Resource belongs to another lecture than the one claimed.
  const lecOther = "assoc_lec_other";
  await seedLecture({id: lecOther});
  await expectCode(
    associate({
      data: {
        ...base,
        lectureId: lecOther,
        receipt: receiptFor({resourceId: res, lectureId: lecOther, videoId: GUID_A}),
      },
      auth: DOCTOR,
    }),
    "failed-precondition",
    "lecture mismatch",
  );

  // 5b. Resource and lecture disagree on the owning subject.
  const lecSubjectMismatch = "assoc_lec_subject_mismatch";
  const resSubjectMismatch = "assoc_res_subject_mismatch";
  await seedLecture({id: lecSubjectMismatch, subjectId: "subj_assoc_other"});
  await seedResource({
    id: resSubjectMismatch,
    lectureId: lecSubjectMismatch,
    subjectId: "subj_assoc",
  });
  await expectCode(
    associate({
      data: {
        ...base,
        resourceId: resSubjectMismatch,
        lectureId: lecSubjectMismatch,
        receipt: receiptFor({
          resourceId: resSubjectMismatch,
          lectureId: lecSubjectMismatch,
          videoId: GUID_A,
        }),
      },
      auth: DOCTOR,
    }),
    "failed-precondition",
    "subject mismatch",
  );

  // 6. Library problems.
  await expectCode(
    associate({
      data: {
        ...base,
        libraryId: "999999",
        receipt: receiptFor({...base, libraryId: "999999"}),
      },
      auth: DOCTOR,
    }),
    "invalid-argument",
    "unknown library",
  );
  await expectCode(
    associate({
      data: {
        ...base,
        libraryId: "775315",
        receipt: receiptFor({...base, libraryId: "775315"}),
      },
      auth: DOCTOR,
    }),
    "invalid-argument",
    "inactive library 775315",
  );

  // 7. Incomplete Stream configuration.
  const savedApiKey = process.env.BUNNY_STREAM_API_KEY;
  process.env.BUNNY_STREAM_API_KEY = "";
  try {
    await expectCode(
      associate({
        data: {...base, receipt: receiptFor({...base})},
        auth: DOCTOR,
      }),
      "invalid-argument",
      "incomplete Stream configuration",
    );
  } finally {
    process.env.BUNNY_STREAM_API_KEY = savedApiKey;
  }

  // 8. Invalid video id (URL).
  await expectCode(
    associate({
      data: {
        ...base,
        videoId: "https://iframe.mediadelivery.net/embed/736742/abc",
        receipt: receiptFor({...base}),
      },
      auth: DOCTOR,
    }),
    "invalid-argument",
    "URL instead of a bare Video ID",
  );

  // 9..12. Receipt binding.
  await expectCode(
    associate({
      data: {
        ...base,
        receipt: receiptFor({
          resourceId: res,
          lectureId: lec,
          videoId: GUID_A,
          issuedAtSeconds: Math.floor(Date.now() / 1000) - 3600,
        }),
      },
      auth: DOCTOR,
    }),
    "permission-denied",
    "expired receipt",
  );
  await expectCode(
    associate({
      data: {...base, receipt: {...receiptFor({...base}), signature: "AAAA"}},
      auth: DOCTOR,
    }),
    "permission-denied",
    "invalid HMAC signature",
  );
  await expectCode(
    associate({
      data: {
        ...base,
        receipt: receiptFor({resourceId: res, lectureId: lec, videoId: GUID_B}),
      },
      auth: DOCTOR,
    }),
    "permission-denied",
    "receipt issued for another Video ID",
  );
  await expectCode(
    associate({
      data: {
        ...base,
        receipt: receiptFor({
          resourceId: res,
          lectureId: lec,
          libraryId: "999999",
          videoId: GUID_A,
        }),
      },
      auth: DOCTOR,
    }),
    "permission-denied",
    "receipt issued for another library",
  );
  await expectCode(
    associate({
      data: {
        ...base,
        receipt: receiptFor({resourceId: "assoc_res_other", lectureId: lec, videoId: GUID_A}),
      },
      auth: DOCTOR,
    }),
    "permission-denied",
    "receipt issued for another resource",
  );
  await expectCode(
    associate({
      data: {...base, receipt: null},
      auth: DOCTOR,
    }),
    "permission-denied",
    "missing receipt",
  );

  // 13. Successful server-side persistence (delegated admin).
  const first = await associate({
    data: {...base, receipt: receiptFor({...base})},
    auth: ADMIN_ALLOWED,
  });
  assert.equal(first.status, "associated");
  const stored = (await db.collection("lecture_resources").doc(res).get()).data();
  assert.equal(stored.bunny_library_id, "736742");
  assert.equal(stored.bunny_video_id, GUID_A);
  assert.equal(stored.updated_by, ADMIN_ALLOWED.uid);
  ok("authorized content manager persists the association");

  // 14. First-video denormalization derives from the verified row.
  const lectureDoc = (await db.collection("lectures").doc(lec).get()).data();
  assert.equal(lectureDoc.first_video.resource_id, res);
  assert.equal(lectureDoc.first_video.bunny_video_id, GUID_A);
  assert.equal(lectureDoc.first_video.bunny_library_id, "736742");
  ok("first_video carries the verified association");

  // 15. Duplicate request is idempotent.
  const second = await associate({
    data: {...base, receipt: receiptFor({...base})},
    auth: DOCTOR,
  });
  assert.equal(second.status, "already_associated");
  const afterSecond = (await db.collection("lecture_resources").doc(res).get()).data();
  assert.equal(afterSecond.bunny_library_id, "736742");
  ok("duplicate request is idempotent");

  // 16. Verified row cannot be silently rebound to another Video ID.
  await expectCode(
    associate({
      data: {
        ...base,
        videoId: GUID_B,
        receipt: receiptFor({resourceId: res, lectureId: lec, videoId: GUID_B}),
      },
      auth: DOCTOR,
    }),
    "failed-precondition",
    "video change without explicit replacement",
  );

  // 17. Explicit, re-verified replacement works.
  const replaced = await associate({
    data: {
      ...base,
      videoId: GUID_B,
      replaceVideo: true,
      receipt: receiptFor({resourceId: res, lectureId: lec, videoId: GUID_B}),
    },
    auth: DOCTOR,
  });
  assert.equal(replaced.status, "associated");
  const replacedRow = (await db.collection("lecture_resources").doc(res).get()).data();
  assert.equal(replacedRow.bunny_video_id, GUID_B);
  assert.equal(replacedRow.bunny_library_id, "736742");
  ok("explicit replacement re-verifies and rewrites");

  // 18. PDF / external-link rows are never associated.
  await seedLecture({id: "assoc_lec_pdf"});
  await seedResource({
    id: "assoc_res_pdf",
    lectureId: "assoc_lec_pdf",
    resourceType: "pdf",
  });
  await expectCode(
    associate({
      data: {
        resourceId: "assoc_res_pdf",
        lectureId: "assoc_lec_pdf",
        libraryId: "736742",
        videoId: GUID_A,
        receipt: receiptFor({
          resourceId: "assoc_res_pdf",
          lectureId: "assoc_lec_pdf",
          videoId: GUID_A,
        }),
      },
      auth: DOCTOR,
    }),
    "invalid-argument",
    "non-video resource rejected",
  );

  // 19. Deleted resource / lecture are refused.
  await seedLecture({id: "assoc_lec_deleted", isDeleted: true});
  await seedResource({id: "assoc_res_deleted", lectureId: "assoc_lec_deleted"});
  await expectCode(
    associate({
      data: {
        resourceId: "assoc_res_deleted",
        lectureId: "assoc_lec_deleted",
        libraryId: "736742",
        videoId: GUID_A,
        receipt: receiptFor({
          resourceId: "assoc_res_deleted",
          lectureId: "assoc_lec_deleted",
          videoId: GUID_A,
        }),
      },
      auth: DOCTOR,
    }),
    "failed-precondition",
    "deleted lecture refused",
  );

  // 20. Pending (post-cutover, unassociated) row cannot play.
  const lecPending = "assoc_lec_pending";
  await seedLecture({id: lecPending});
  await seedResource({
    id: "assoc_res_pending",
    lectureId: lecPending,
    videoId: GUID_A,
    createdAtMs: Date.parse("2026-12-05T00:00:00.000Z"),
  });
  await db.collection("users").doc("u_assoc_student").set({
    role: "student",
    student_type: "center_student",
    approved: true,
    is_deleted: false,
  });
  const pendingError = await expectCode(
    issueUrl({
      data: {
        videoId: GUID_A,
        deviceId: "assoc-device-aaaaaaaaaaaa",
        lectureId: lecPending,
      },
      auth: {uid: "u_assoc_student", token: {role: "student", approved: true}},
    }),
    "failed-precondition",
    "pending resource cannot play",
  );
  assert.match(pendingError.message, /pending verification/);

  // 21. Genuine legacy row (pre-cutover) still passes the association gate.
  const lecLegacy = "assoc_lec_legacy";
  await seedLecture({id: lecLegacy});
  await seedResource({
    id: "assoc_res_legacy",
    lectureId: lecLegacy,
    videoId: GUID_B,
    createdAtMs: Date.parse("2026-01-01T00:00:00.000Z"),
  });
  let legacyError = null;
  try {
    await issueUrl({
      data: {
        videoId: GUID_B,
        deviceId: "assoc-device-bbbbbbbbbbbb",
        lectureId: lecLegacy,
      },
      auth: {uid: "u_assoc_student", token: {role: "student", approved: true}},
    });
  } catch (error) {
    legacyError = error;
  }
  assert.notEqual(legacyError, null, "legacy row should stop later (no entitlement)");
  assert.ok(
    !/pending verification/.test(legacyError.message),
    `legacy row must not hit the association gate (${legacyError.message})`,
  );
  ok("legacy row keeps the default-library compatibility path");

  bunnyGuard.assertNoBunnyCalls();
  console.log(`bunny_association_flow: ${passed} assertions passed`);
}

run().catch((error) => {
  console.error("Test failed:", error);
  process.exit(1);
});
