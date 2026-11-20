# ADR-010 — Mission 4 Final Report (Agent 2)

Date: 2026-11-12 · Repository: `D:\antigravity\dr_tarek_platform_final`
Baseline HEAD: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged)
Production changes: **NONE** · Deployment: **NONE** · Commit/push: **NONE**

Workstream status: **A — DONE · B — DONE · C — DONE · Reports — DONE ·
CI execution — NOT RUN (no push authorized)**.

---

## 1. Handover findings

The repository already contained the bulk of Missions 1–4 as uncommitted work.
Everything claimed by the previous agent was verified directly in code and by
re-running the suites (`reports/adr010/agent_2_handover_audit.md`).

Three gaps were found and fixed in this session:

1. **Quick Upload still wrote `bunny_library_id` directly** (a client write the
   new Rules deny). It would have failed outright. Fixed to create a pending
   row and call the server gateway.
2. **`progress_percentage` failed standalone**: emulator trigger delivery took
   ~22 s versus the test's 15 s poll. The aggregation itself produced the
   correct 50/1/2. Poll extended to the documented 120 s readiness budget;
   assertions unchanged.
3. **Rules accepted any timestamp for `created_at`**, so a client could
   back-date a row to look "legacy" and bypass the verification gate. Now
   `created_at == request.time` is required, and the rules suite proves a
   forged stamp is denied.

A missing emulator case (subject mismatch, A10 #7) was added.

## 2. Verified previous implementation

| Area | State |
|---|---|
| Registry + fail-closed resolver (736742 default, 775315 defined but inactive) | verified |
| Pure migration planner + dry-run CLI (no write path) | verified |
| HMAC validation receipt + `validateBunnyVideoAssociation` | verified |
| Transactional association callable | verified |
| Dashboard gateway/controller integration | verified + Quick Upload repaired |
| Mobile authoring integration | verified |
| Flutter additive parsing + hint-only library | verified |
| Playback pending-row gate + display-media gate | verified |
| Legacy fixture repair (`pcont-vid-*`, `pbs-vid-A`) | verified |
| `progress_percentage` fixture (`status: published`) | verified |

## 3. Server callable

Name: **`associateBunnyVideoToLibrary`** (`functions/src/index.ts:5006`).

Supporting callable: **`validateBunnyVideoAssociation`** (`index.ts:4914`).

### Request

```jsonc
{
  "resourceId": "lecture_resources doc id",   // required
  "lectureId": "lectures doc id",             // required
  "libraryId": "736742",                      // required, registry-resolved
  "videoId": "bare-bunny-guid",               // required, GUID only
  "replaceVideo": false,                      // optional; explicit rebind intent
  "receipt": {                                // required, from validation
    "resourceId": "...",
    "lectureId": "...",
    "libraryId": "736742",
    "videoId": "...",
    "expiresAt": 1794500000,
    "signature": "base64url HMAC"
  }
}
```

### Response (closed shape, no credentials)

```jsonc
{ "status": "associated" | "already_associated",
  "resourceId": "...", "lectureId": "...",
  "libraryId": "736742", "videoId": "..." }
```

Errors: `unauthenticated`, `permission-denied`, `invalid-argument`,
`failed-precondition`, `not-found`.

### `validateBunnyVideoAssociation` contract

Request `{libraryId, videoId, resourceId?, lectureId?}` → on success
`{status:"verified", reason:"ok", libraryId, videoId, receipt}`; otherwise
`{status:"mismatch"|"unavailable"|"rejected", reason, libraryId, videoId,
receipt:null}`. When both `resourceId` and `lectureId` are supplied, the
receipt is bound to that pair (the Dashboard/mobile gateways always do this).

## 4. Authorization helpers and permissions

- Helper: `requireContentManager(request)` (pre-existing, reused).
- Authority: **Doctor (Platform Owner)** or an **Admin** whose
  `admin_permissions/{uid}` is `is_active: true` with
  `permissions.admin_content === true`.
- This is exactly the `canManageContent()` authority used by
  `firestore.rules`. No new role or permission key was introduced; a
  Dashboard login alone is not sufficient.
- Authorization is explicit in the callable because the Admin SDK bypasses
  Firestore Rules.

## 5. Receipt validation details

- HMAC-SHA256 over a domain-separated payload
  (`adr010-association-v1\nresourceId\nlectureId\nlibraryId\nvideoId\nexpiresAt`),
  base64url, verified with `timingSafeEqual` (constant time).
- TTL: 600 seconds (10 minutes).
- Rejected: expired, tampered signature, foreign secret, missing/malformed
  receipt, receipt for another resource, lecture, library or Video ID.
- Domain-separated from the earlier library+video receipt, so neither can be
  replayed as the other.
- A receipt authorizes exactly one association; it is not a general token.

## 6. Firestore persistence behavior

Inside a single transaction the callable:

1. re-reads `lecture_resources/{resourceId}` and `lectures/{lectureId}`;
2. re-runs the pure decision (`planBunnyAssociationWrite`): video type,
   resource/lecture identity, subject agreement, bare GUID, stored-video
   change only with `replaceVideo`, registry-active and fully configured
   library;
3. writes `bunny_library_id` (+ `bunny_video_id` when binding/replacing) with
   `merge: true`, `updated_at`/`updated_by`, preserving every unrelated field;
4. recomputes `lectures/{lectureId}.first_video` from the trusted rows in the
   same transaction.

Idempotent: an identical repeat returns `already_associated` and rewrites the
same values. A concurrent edit cannot slip a different Video ID past the
checks (fresh read inside the transaction).

## 7. Security Rules changes

`firestore.rules` → `match /lecture_resources/{resourceId}`:

```
allow create: if canManageContent()
  && request.resource.data.get('bunny_library_id', null) == null
  && request.resource.data.get('created_at', null) == request.time;

allow update: if canManageContent()
  && request.resource.data.get('bunny_library_id', null)
     == resource.data.get('bunny_library_id', null)
  && request.resource.data.get('resource_type', '')
     == resource.data.get('resource_type', '')
  && (
    request.resource.data.get('bunny_video_id', null)
      == resource.data.get('bunny_video_id', null)
    || (resource.data.get('bunny_library_id', null) == null
        && request.resource.data.get('bunny_library_id', null) == null)
  );
```

Reads, deletes (`false`) and all other collections are unchanged. No client
permission was broadened.

## 8. Proof clients cannot set/change the association

- Rules deny create-with-association, add, change, remove, and Video-ID swap
  under a verified association (15 assertions in
  `security-tests/adr010_association_rules.test.js`, all passing).
- Dashboard `SubjectDetailsController` writes neither field for video rows;
  it calls the gateway. Quick Upload now does the same.
- Mobile `AdminContentRemoteDataSourceImpl` removes `bunny_library_id` from
  every payload and defers a verified-row Video-ID change to the callable.
- Admin SDK writes bypass Rules by design, which is why the callable performs
  explicit authorization, document checks, registry resolution and receipt
  verification.

## 9. Proof unverified resources cannot play

- `generateBunnySignedUrl` refuses a post-cutover row with no verified
  `bunny_library_id` (`failed-precondition`, "pending verification"). Proved
  in the emulator (`bunny_association_flow` #20).
- `resolveBestEffortBunnyLibrary` (posters/previews) applies the same gate.
- Legacy (pre-cutover) rows keep the default-library fallback; the emulator
  proves the gate is not applied to them (#21).
- A failed association leaves a pending row: no `bunny_library_id`, and for
  Dashboard-created rows no `bunny_video_id` either — unplayable.

## 10. Legacy test fixture changes

- `pcont-vid-*` → deterministic GUIDs (`11111111-aaaa-4aaa-8aaa-0000000000xx`).
- `pbs-vid-A` → `22222222-bbbb-4bbb-8bbb-000000000001`.
- The production VIDEO-ID-ONLY guard is untouched; only fixtures changed.
- Two further fixture defects were corrected earlier (watch-window state
  isolation; GUID-shaped unknown id). Expected authorization outcomes were not
  changed.

## 11. Progress aggregation root cause

Two layers (details in `progress_percentage_root_cause.md`):

1. **Historical `total_lectures = 0`**: the fixture never wrote `status`, so
   the (correct) published-only filter dropped all 50 lectures. Fixed in the
   fixture (`status: "published"`, `is_deleted: false`, `subject_id`).
2. **Standalone `Summary doc should be created`**: emulator trigger delivery
   measured at ~22 s versus a 15 s poll. The computed summary was 50/1/2. Poll
   extended to 120 s (the documented readiness budget); assertions unchanged.

The aggregation function has zero diff at HEAD; no semantics were changed.

## 12. Baseline comparison evidence

Read-only only (`git show`, `git diff`); no reset/stash/checkout/worktree.

- `git show HEAD:functions/test/progress_percentage.test.js` → baseline
  fixture has only `section_id` + `title` (reproduces `total_lectures = 0`).
- `git diff -U0 -- functions/src/index.ts` → no hunk touches
  `calculateAndSetSubjectProgress`/`recalculateSubjectProgress`.
- `git show HEAD:functions/test/protected_content.test.js` /
  `playback_session.test.js` → baseline ids are `pcont-vid-*` / `pbs-vid-A`.
- `git diff -U0 -- functions/src/index.ts` → the VIDEO-ID-ONLY validation
  guard is unchanged.

## 13. Exact changed files (Agent 2 this session)

| File | Change |
|---|---|
| `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart` | removed direct association write; server gateway after create; imports |
| `dashboard/test/bunny_library_persistence_test.dart` | +4 quick-upload security tests |
| `functions/test/bunny_association_flow.test.js` | + subject-mismatch emulator case |
| `functions/test/progress_percentage.test.js` | poll 15 s → 120 s (assertions unchanged) |
| `firestore.rules` | `created_at == request.time` (anti-back-dating) |
| `security-tests/adr010_association_rules.test.js` | + forged-legacy denial (15 assertions) |
| `security-tests/rules.test.js` | fixtures use `serverTimestamp()` for the new equality rule |
| `reports/adr010/agent_2_handover_audit.md` | new |
| `reports/adr010/server_side_verified_association.md` | updated/verified |
| `reports/adr010/firestore_rules_enforcement.md` | updated/verified |
| `reports/adr010/legacy_test_fixture_repair.md` | updated/verified |
| `reports/adr010/progress_percentage_root_cause.md` | rewritten with both layers |
| `reports/adr010/mission_4_security_review.md` | updated/verified |
| `reports/adr010/mission_4_final_report.md` | new (this file) |

All other modified/untracked files were pre-existing work, verified and
preserved. CRLF state preserved (`functions/src/index.ts` CRLF;
`progress_percentage.test.js` LF).

## 14. Test commands and results

| Command | Result | Count |
|---|---|---|
| `cd functions && npm run build` | PASS (exit 0) | — |
| `cd functions && npm run test:pure` | PASS (exit 0) | all pure suites |
| `cd functions && npm test` | PASS (exit 0) | **51/51 files** |
| `firebase emulators:exec … "node test/protected_content.test.js"` | PASS (exit 0) | 20 scenarios |
| `firebase emulators:exec … "node test/playback_session.test.js"` | PASS (exit 0) | 18 scenarios |
| `firebase emulators:exec … "node test/progress_percentage.test.js"` | PASS (exit 0) | 50/1/2 |
| `security-tests/…/adr010_association_rules.test.js` | PASS (exit 0) | 15 assertions |
| `security-tests` full `npm test` (`--only firestore,storage`) | PASS (exit 0) | both suites |
| `cd dashboard && flutter analyze` | PASS | no issues |
| `cd dashboard && flutter test` (6 ADR-010/authoring files) | PASS (exit 0) | 71 tests |
| `flutter analyze` (root) | PASS | no issues |
| `flutter test test/features/video_streaming/video_resource_library_test.dart` | PASS (exit 0) | 6 tests |
| `.github/workflows/ci.yml` ADR-010 job | **NOT RUN** | no push authorized |
| `dashboard/test/subject_details_test.dart` + `subject_grade_context_sync_test.dart` | FAIL (pre-existing) | 7 unrelated text-alignment assertions |

## 15. Git baseline and final status

- HEAD unchanged: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`.
- 28 tracked files modified, same untracked set as handover plus the reports.
- No commit, no push, no deploy, no reset/stash/checkout, no mass formatting.

## 16. Production changes

**NONE.** No deployment, no Rules deploy, no Secret Manager change, no Bunny
configuration change, no production data access, no real playback URL issued,
no secret printed. Library `775315` remains inactive (absent from
`BUNNY_ACTIVE_LIBRARY_IDS`; rejected by validation, association and issuance).

## 17. Remaining blockers / preconditions

1. **Deployment order**: Functions first, then Rules. Rules without the
   callable make new video rows pending (fail-closed but a functional stop).
2. **Cutover timing**: default `BUNNY_ASSOCIATION_CUTOVER` is
   `2026-11-13T00:00:00Z`. Deploy on/after that instant, or set the env var to
   the deployment time. Before it, a *mobile-created* row whose association
   call failed could still use the legacy fallback (it has `bunny_video_id`);
   Dashboard-created rows cannot, because their `bunny_video_id` is written
   only by the server after verification.
3. Real Bunny Stream metadata was not called (no production credential; no
   external call by design). Receipts are tested with fixture secrets.
4. Pre-existing, unrelated: two Dashboard UI test files fail on text
   alignment in unmodified `subject_details_screen.dart`; archived lectures
   remain issuable; `775315` pull zone still serves unsigned HLS; duplicate
   Video ID `6ffb23ad…`; seven placeholder video rows; `BUNNY_STREAM_API_KEY`
   is a plain env var, not Secret Manager.

## 18. Recommended next task

1. Deploy Cloud Functions (contains `associateBunnyVideoToLibrary` and the
   gates) and set `BUNNY_ASSOCIATION_CUTOVER` to the deployment instant.
2. Deploy `firestore.rules`, then smoke-test Dashboard create / edit / quick
   upload / retry and a legacy edit.
3. Run the backfill CLI in dry-run against a production export; review the
   explicit mapping before any write.
4. Only then consider activating `775315` after its credentials, token
   authentication, playback template and pull-zone security are approved.
