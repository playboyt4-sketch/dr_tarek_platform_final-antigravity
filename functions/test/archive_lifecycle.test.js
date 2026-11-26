/**
 * Pure unit tests for soft-delete / archive & restore lifecycle helpers.
 */
const assert = require("node:assert/strict");
const {
  isStudentArchiveEligibleRole,
  isArchivedRecord,
  buildStudentArchiveFields,
  buildStudentRestoreFields,
  buildSubjectArchiveFields,
  buildSubjectRestoreFields,
  buildLectureRestoreFields,
} = require("../lib/archive_lifecycle.js");

const SENTINEL = "__SERVER_TIMESTAMP__";

// Role eligibility: only students & new_students can be archived, never doctor/admin.
assert.equal(isStudentArchiveEligibleRole("student"), true);
assert.equal(isStudentArchiveEligibleRole("new_student"), true);
assert.equal(isStudentArchiveEligibleRole("admin"), false);
assert.equal(isStudentArchiveEligibleRole("doctor"), false);
assert.equal(isStudentArchiveEligibleRole(undefined), false);

// Archived detection accepts either is_archived or legacy is_deleted.
assert.equal(isArchivedRecord({is_archived: true}), true);
assert.equal(isArchivedRecord({is_deleted: true}), true);
assert.equal(isArchivedRecord({is_archived: false, is_deleted: false}), false);
assert.equal(isArchivedRecord(undefined), false);

// Archiving a student sets soft-delete metadata and disables account_status.
const archivedStudent = buildStudentArchiveFields({
  actorId: "admin_1",
  previousAccountStatus: "active",
  nowSentinel: SENTINEL,
});
assert.deepEqual(archivedStudent, {
  is_archived: true,
  is_deleted: true,
  deleted_at: SENTINEL,
  archived_at: SENTINEL,
  archived_by: "admin_1",
  archived_previous_account_status: "active",
  account_status: "disabled",
  updated_at: SENTINEL,
  updated_by: "admin_1",
});

// Restoring a student clears archive flags and restores active status even if
// previousAccountStatus was missing or disabled.
const restoredStudent = buildStudentRestoreFields({
  actorId: "admin_1",
  previousAccountStatus: "disabled",
  nowSentinel: SENTINEL,
});
assert.equal(restoredStudent.is_archived, false);
assert.equal(restoredStudent.is_deleted, false);
assert.equal(restoredStudent.deleted_at, null);
assert.equal(restoredStudent.archived_by, null);
assert.equal(restoredStudent.account_status, "active");

// Subject archive + restore fields match dashboard & student app queries.
const archivedSubject = buildSubjectArchiveFields({
  actorId: "doc_1",
  nowSentinel: SENTINEL,
});
assert.equal(archivedSubject.is_archived, true);
assert.equal(archivedSubject.is_deleted, true);
assert.equal(archivedSubject.deleted_at, SENTINEL);
assert.equal(archivedSubject.archived_by, "doc_1");

const restoredSubject = buildSubjectRestoreFields({
  actorId: "doc_1",
  nowSentinel: SENTINEL,
});
assert.equal(restoredSubject.is_archived, false);
assert.equal(restoredSubject.is_deleted, false);
assert.equal(restoredSubject.deleted_at, null);
assert.equal(restoredSubject.archived_by, null);

// Lecture restore turns an archived lecture back into draft cleanly.
const restoredLecture = buildLectureRestoreFields({
  actorId: "doc_1",
  previousStatus: "archived",
  nowSentinel: SENTINEL,
});
assert.equal(restoredLecture.is_archived, false);
assert.equal(restoredLecture.is_deleted, false);
assert.equal(restoredLecture.deleted_at, null);
assert.equal(restoredLecture.archived_by, null);
assert.equal(restoredLecture.status, "draft");

console.log("archive_lifecycle.test.js passed");
