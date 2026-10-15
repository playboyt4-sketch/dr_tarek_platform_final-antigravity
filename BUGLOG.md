# BUGLOG — Dr. Tarek Platform (local stopgap)

> **Status of this file:** STOPGAP. Per `docs/notion/10_Bugs.md` §1,
> `10 Bugs` defines process/taxonomy only, not a live bug list, and no
> external tracker (Jira / Linear / GitHub Issues) has been confirmed yet
> (see `docs/notion/09_Tasks.md` Open Items). Until the team confirms a real
> issue tracker, this version-controlled file is the authoritative record of
> filed bugs. Fields follow the Bug Report Template (`10_Bugs.md` §5) and
> severities follow §3 (P0–P4); lifecycle states follow §4.
> Do NOT treat this file as an architecture document — it lives at the repo
> root deliberately, outside `docs/`.

---

## Closed

### BUG-AUTH-001 / SEC-AUTH-001 — App Check failure misclassified as wrong credentials (Registration)
- **Severity:** P1 (major flow broken on enforced App Check; painful workaround) + SEC-AUTH (security posture involved)
- **Category:** BUG-AUTH / SEC-AUTH · Layer: Data→Presentation mapping
- **Reporter:** platform engineer (browser DevTools observation) · **Date Reported:** 2026-09-18
- **Environment:** Flutter Web debug on `localhost`, Firebase project `dr-tarek-platform`, App Check enforced (`SECURE_CALL_OPTS`)
- **Feature:** Feature 01 — Authentication & Registration (final step: Set Password / Finish → `registerNewStudent`)
- **Description:** Any `registerNewStudent` failure caused by App Check rejection surfaced as "رقم الهاتف أو كلمة المرور غير صحيحة" (Login's copy). Root cause: `Failure._fromFunctionsException` mapped gRPC `unauthenticated` → `wrongCredentials` unconditionally, but Functions v2 `enforceAppCheck` rejections also arrive as `unauthenticated`.
- **Steps to Reproduce:** 1. `flutter run -d chrome` with unregistered debug token. 2. Complete wizard steps 1–5. 3. Press Finish.
- **Expected:** Neutral/transport-level Arabic error. **Actual:** Login's invalid-credentials copy.
- **Frequency:** Always (when App Check token invalid). **Regression:** No. **Workaround:** Register debug token in Console (operational).
- **Fix:** `FailureCode.appCheckFailed` + message-signal-first guard in `lib/core/errors/failure.dart`; canonical copy in `lib/core/errors/failure_messages.dart`; same guard in `mapFunctionErrorCode`; tests `test/core/errors/failure_appcheck_test.dart` (7 tests).
- **Status:** Closed (verified: `flutter analyze` clean, 19/19 error-mapper tests + 22/22 auth tests pass).

### BUG-AUTH-002 — Dashboard drift-copy of Failure hierarchy lacked the App Check fix
- **Severity:** P1 · **Category:** BUG-AUTH · **Date Reported:** 2026-09-18 (found during Task 1 of this session)
- **Feature:** Admin/Teacher Dashboard (separate package `drtarek_dashboard/`)
- **Description:** `dashboard/lib/core/errors/failure.dart` was an older drift-copy without `appCheckFailed`; dashboard callables could mis-map identically to BUG-AUTH-001. Diff vs canonical: same `Failure` class shape (no structural divergence), canonical is a strict superset — zero dashboard-only codes to preserve.
- **Fix (ported, NOT merged — see OPEN-001):** ported `appCheckFailed` + `_isAppCheckSignal` guards into the dashboard copy; added `appCheckFailed` arm to dashboard login `_messageFor`; added `dashboard/test/failure_mapping_test.dart` (3 tests).
- **Tests:** dashboard trio (`failure_mapping_test`, `login_controller_test`, `dashboard_login_screen_test`) 16/16 pass; `flutter analyze` in `dashboard/`: no errors (25 pre-existing info/warning only).
- **Status:** Closed (bug class fixed; SoT merge itself remains OPEN-001).

### BUG-AUTH-003 — Raw exceptions escaped `CustomTokenRemoteDataSource` / `StaffAuthRemoteDataSource`
- **Severity:** P2 · **Category:** BUG-AUTH · **Feature:** Feature 01 (Login, staff login, staff directory)
- **Description:** Both data sources let raw `FirebaseFunctionsException`/`StateError` escape, relying on render-time normalization — violating 08 §5.
- **Fix:** try/catch → `Failure.from` → throw (mirrors sibling `RegistrationRemoteDataSource`); missing-token `StateError` converted to `Failure(FailureCode.server)`. No `Either` introduced: repo has zero Either/dartz usage — the established contract is throw-`Failure` + `AsyncValue.guard`; inventing Either would violate §14.
- **Status:** Closed (contract unchanged, no call-site updates needed; verified via `flutter analyze` + existing auth suite).

### BUG-AUTH-004 — Raw `$e` interpolated into user-facing SnackBar in registration `_pickImage`
- **Severity:** P3 · **Category:** BUG-AUTH · **Feature:** Feature 01, Registration step 4 (photo)
- **Description:** `student_registration_wizard.dart` `_pickImage` showed `'فشل في اختيار الصورة الشخصية: $e'` (leaks technical/English text). (Sibling `new_student_photo_screen.dart` only `debugPrint`s — log-only, untouched.)
- **Fix:** `_showError(_friendlyError(e))` — reuses canonical mapping; no new Failure subtype, no invented validation limits.
- **Status:** Closed.

### BUG-AUTH-005 — Unreachable `wrongCredentials` branch in `student_profile_screen.dart:169`
- **Severity:** P4 · **Category:** dead code (08 §4) · **Feature:** Profile / delete-account dialog
- **Description:** Second `failure.code == FailureCode.wrongCredentials` check could never execute (first branch at :159 catches all). Confirmed genuinely dead, removed cleanly.
- **Status:** Closed (verified via `flutter analyze`).

---

## Open

### OPEN-001 — Dashboard Failure copy cannot be merged (dependency conflict) — P2
- **Description:** Deleting the duplicate and importing canonical via `dr_tarek_platform: path: ../` fails version solving: parent's `flutter_local_notifications_windows` chain pins `xml ^6.5.0` while dashboard's `pdf 3.13.0` requires `xml ^7.0.1` (exact resolver error recorded in session report). Reverted to port-and-document. Dashboard copy carries a sync warning comment.
- **Remediation options (team decision required):** (a) align `pdf`/`xml` versions across both packages; (b) upgrade parent `flutter_local_notifications` to an xml-7-compatible line; (c) extract a shared pure-Dart errors package. Until then, every canonical mapping change must be manually ported.

### OPEN-002 — Production reCAPTCHA Enterprise site key not supplied — P1 (release-blocking)
- **Description:** Prod/staging web boot requires `--dart-define=RECAPTCHA_SITE_KEY=…` (guard in `lib/main.dart`). Must be supplied by Platform Owner before any staging/prod web deploy. Never hardcode.

### OPEN-003 — Localhost debug token must be registered in Console — P2
- **Description:** Debug web prints the auto-generated App Check debug token to the browser console; it must be registered under Firebase Console → App Check → Manage Debug Tokens. Unregistered → 403s + `appCheckFailed` on every callable. Operational, per-developer.

### OPEN-004 — `AuthRepositoryImpl` still throws raw `StateError` (missing user/profile) — P3
- **Description:** `lib/features/authentication/data/repositories/auth_repository_impl.dart` `login`/`staffLogin` throw `StateError` when user/profile is null. UX-safe today (render-time `Failure.from` → generic), but violates 08 §5 layering. Out of Task 2 scope (data sources only) — left for a follow-up.

### OPEN-005 — Registration `_loadActiveGroups` swallows all errors to `[]` — P3
- **Description:** `student_registration_wizard.dart` `_loadActiveGroups` catches everything and returns an empty group list (silent failure, no user signal). Flagged, not changed (needs product decision on error UX).

### OPEN-006 — Client-side photo file-size/format validation missing (11 Assets §11) — P3
- **Description:** No approved client-side limit enforced; per constraints, none invented during BUG-AUTH-004. Needs architecture decision first.

### OPEN-007 — Dashboard suite has 28 pre-existing failures unrelated to auth — P2
- **Description:** `subject_details_test` (header centering), `subscription_screen_test` (finders), `add_lecture_test`, `subject_grade_context_sync_test` fail identically on the pristine tree (verified via `git stash` baseline 2026-09-18). Dashboard `flutter analyze`: 25 pre-existing info/warning (deprecated `withOpacity`, etc.). None touch the Failure hierarchy.

### OPEN-008 — No real issue tracker confirmed — P4 (process)
- **Description:** This file is a stopgap. Confirm Jira/Linear/GitHub Issues per `09_Tasks.md` Open Items, migrate these entries, then delete this file.

### OPEN-009 — `dashboard_shell_test` fails: "Upload Lecture" text missing — P2
- **Severity:** P2 (possible broken lecture-upload entry point in the dashboard shell; triage must first determine product-vs-stale-test — downgrade to P4 if the test is stale, upgrade if a product regression is confirmed)
- **Category:** BUG-UI · Layer: BUG-ADMIN (Teacher Dashboard shell, web)
- **Reporter:** AI coding agent (OpenCode session, neighboring-suite verification) · **Date Reported:** 2026-09-21
- **Environment:** Windows (win32), Flutter 3.44.4 stable / Dart 3.12.2, `dashboard/` package (`drtarek_dashboard`), `flutter test` with provider overrides (no Firebase backend)
- **Feature:** Feature 04 (Lecture) — admin/dashboard counterpart (shell "Upload Lecture" entry)
- **Description:** Test `renders home analytics composition with live data` (`dashboard/test/dashboard_shell_test.dart:177`) expects exactly one `Upload Lecture` widget; zero are found. Unconfirmed whether the shell no longer renders the entry (product bug) or the test expectation is stale (test bug).
- **Steps to Reproduce:** 1. `cd dashboard`. 2. `flutter test test/dashboard_shell_test.dart` (originally observed in a 5-file batch run). 3. Observe the failure at `dashboard_shell_test.dart:177`.
- **Expected Result:** Shell renders one "Upload Lecture" entry.
- **Actual Result:** `Expected: exactly one matching candidate / Actual: Found 0 widgets with text "Upload Lecture"`.
- **Screenshots / Logs:** Test log excerpt above (full log in session transcript 2026-09-21).
- **Frequency:** Observed 1/1 batch runs on 2026-09-21 (single observation — repeat runs needed).
- **Regression?** Unknown — baseline unavailable (see prerequisite). Note: OPEN-007's 2026-09-18 pristine-tree baseline does NOT list this suite, so the failure may post-date 2026-09-18 uncommitted work — unconfirmed.
- **Workaround:** None for the red suite signal. Product impact unconfirmed — manually verify in the live dashboard whether the upload entry point renders before treating as product regression.
- **Prerequisite for root-cause:** OPEN-011 (tree hygiene) — a clean baseline comparison was attempted and had to be abandoned (reverting 3 files broke compilation against the rest of the uncommitted tree).

### OPEN-010 — `subject_grade_context_sync_test` fails: 5px RenderFlex overflow in 215×159 box — P3
- **Severity:** P3 (5 px vertical clip, cosmetic/minor; test-observed in Subject Details admin screen)
- **Category:** BUG-UI · Layer: BUG-ADMIN (Teacher Dashboard Subject Details, web)
- **Reporter:** AI coding agent (OpenCode session, neighboring-suite verification) · **Date Reported:** 2026-09-21
- **Environment:** Windows (win32), Flutter 3.44.4 stable / Dart 3.12.2, `dashboard/` package, `flutter test` with provider overrides (no Firebase backend)
- **Feature:** Feature 03 (Subject Navigation) — admin/dashboard counterpart (Subject Details grade-context sync)
- **Description:** All 4 tests in group `Subject Details grade-context synchronization` fail with `A RenderFlex overflowed by 5.0 pixels on the bottom` (`BoxConstraints(w=215.0, h=159.0)`), plus cascading widget-inspector "deactivated widget's ancestor" noise from the error reporter.
- **Steps to Reproduce:** 1. `cd dashboard`. 2. `flutter test test/subject_grade_context_sync_test.dart` (fails standalone, not just in batch). 3. Observe 4/4 failures with the overflow assertion.
- **Expected Result:** No layout overflow; tests pass.
- **Actual Result:** 5.0 px bottom overflow in the 215×159 box on every test.
- **Screenshots / Logs:** Test log excerpts above (full log in session transcript 2026-09-21).
- **Frequency:** Always (2/2 runs on 2026-09-21: batch + standalone rerun).
- **Regression?** No new regression suspected — this suite is already recorded as failing on the pristine tree in OPEN-007 (verified via `git stash` baseline 2026-09-18). Caveats: exact failure-mode match to that baseline is unverified (old logs unavailable); the 2026-09-21 relabel change (3 tier-label strings + 1 caption on the Students-list screen, all `maxLines`+ellipsis bounded) has no mechanism to affect a 215×159 Subject-Details box.
- **Workaround:** None needed for product (5 px clip); suite stays red until fixed.

### OPEN-011 — Commit or shelve uncommitted work so future investigations can baseline-compare — P4 (process)
- **Description:** The 2026-09-21 relabel verification was blocked from a clean root-cause determination on OPEN-009/OPEN-010: reverting just the 3 touched files broke compilation because the rest of the uncommitted tree (Option B plan-summary work, new provider APIs, `mock_students.dart`) depends on the new code — there is no compilable baseline commit to compare against. Until the tree is committed (or the in-progress work is shelved to a branch), every future "is this a regression?" question will hit the same wall.
- **Recommendation:** Commit the current working tree (or move in-progress work to a feature branch leaving `main` green), so `git stash`-based pristine baselines work again as they did for OPEN-007. Do NOT bundle this with a fix for OPEN-009/OPEN-010 — filing only.
