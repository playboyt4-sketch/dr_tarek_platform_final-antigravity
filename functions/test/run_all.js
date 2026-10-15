/**
 * Aggregate emulator-suite runner.
 *
 * Replaces the old `&&`-chained `npm test` sequence, which silently stopped
 * at the first failing file (hiding every suite after it — e.g. everything
 * past password_reset.test.js since commit 328c354). This runner executes
 * EVERY file in `FILES` regardless of earlier failures, prints a per-file
 * PASS/FAIL line plus a final summary, and exits nonzero iff any file
 * failed — so CI surfaces all failures instead of only the first.
 *
 * Roster is intentionally identical to the legacy chain (order preserved);
 * adding/removing suites is a separate, deliberate change.
 *
 * Offline (mock/pure, no-emulator) suites verified individually during the
 * follow-up audit are appended after the emulator suites; they run under
 * the same invocation harmlessly since they never touch the network.
 * rolling_window_policy stays covered by `test:pure` only (no duplicate).
 *
 * Usage (inside `firebase emulators:exec`, cwd = functions/):
 *   node test/run_all.js
 */
const {spawnSync} = require("node:child_process");

const FILES = [
  "test/wait_for_triggers.js",
  "test/change_student_grade.test.js",
  "test/academic_periods.test.js",
  "test/login_throttle.test.js",
  "test/device_limits.test.js",
  "test/password_reset.test.js",
  "test/exam_grading.test.js",
  "test/final_decisions_addendum.test.js",
  "test/guest_migration.test.js",
  "test/issuance_lecture_matcher.test.js",
  "test/resource_delivery.test.js",
  "test/progress_percentage.test.js",
  "test/sections_12_13.test.js",
  "test/issuance_lecture_identity.test.js",
  "test/security_event.test.js",
  "test/payment_logged.test.js",
  "test/payment_correction.test.js",
  "test/plan_feature.test.js",
  "test/result_release.test.js",
  "test/device_change.test.js",
  "test/subject_authorization.test.js",
  "test/protected_content.test.js",
  "test/playback_session.test.js",
  "test/first_video_backfill.test.js",
  "test/offline_drm.test.js",
  "test/free_plan_activation.test.js",
  "test/admin_claims_merge.test.js",
  "test/change_password_throttle.test.js",
  "test/content_audit.test.js",
  "test/delete_owner_auth.test.js",
  "test/enumeration.test.js",
  "test/lecture_access.test.js",
  "test/lock_event.test.js",
  "test/membership_audit.test.js",
  "test/migrate_teacher_to_doctor.test.js",
  "test/payment_idempotency.test.js",
  "test/registration_throttle.test.js",
  "test/reset_claim.test.js",
  "test/set_plan_feature_permissions.test.js",
  "test/staff_login_throttle.test.js",
  "test/student_login_throttle.test.js",
  "test/subject_pricing.test.js",
];

const results = [];
for (const file of FILES) {
  // eslint-disable-next-line no-console
  console.log(`\n===== RUN ${file} =====`);
  const outcome = spawnSync("node", [file], {stdio: "inherit"});
  const pass = outcome.status === 0;
  results.push({file, pass});
  // eslint-disable-next-line no-console
  console.log(`===== ${pass ? "PASS" : "FAIL"} ${file} (exit ${outcome.status}) =====`);
}

const failed = results.filter((r) => !r.pass);
// eslint-disable-next-line no-console
console.log("\n===== SUITE SUMMARY =====");
for (const r of results) {
  // eslint-disable-next-line no-console
  console.log(`${r.pass ? "PASS" : "FAIL"}  ${r.file}`);
}
// eslint-disable-next-line no-console
console.log(`\n${results.length - failed.length}/${results.length} files passed.`);
if (failed.length > 0) {
  // eslint-disable-next-line no-console
  console.log(`Failing files: ${failed.map((r) => r.file).join(", ")}`);
  process.exit(1);
}
