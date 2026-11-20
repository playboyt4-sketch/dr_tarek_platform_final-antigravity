# ADR-010 — Agent 2 Handover Audit (Mission 4)

Audit performed before any edit. Read-only: no reset, no stash, no checkout,
no commit, no deploy.

## 1. Git baseline

| Item | Value |
|---|---|
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (`fix(ios): harden FCM token registration …`) |
| Branch | working tree on that commit, uncommitted |
| Tracked files modified | 28 |
| Untracked files | ADR-010 backend core, tests, reports, one ADR doc, Flutter/Dashboard additions |
| Production changes | **NONE** |

`git status --short` at handover (grouped):

- **CI / infra**: `.github/workflows/ci.yml`, `dashboard/.firebase/hosting.YnVpbGRcd2Vi.cache`
- **Firestore**: `firestore.rules`
- **Functions**: `functions/package.json`, `functions/src/index.ts`,
  `functions/test/{protected_content,playback_session,progress_percentage,run_all}.js`
- **Dashboard**: `join_applications_provider.dart`, `reviewing_applications_screen.dart`,
  `home_stats_provider.dart`, `quick_announcement_dialog.dart`, `quick_upload_modal.dart`,
  `grade_pending_requests_provider.dart`, `grade_students_provider.dart`,
  `subject_details_provider.dart`, `grade_pending_requests_screen.dart`,
  `add_lecture_overlay.dart`, `add_lecture_resources.dart`,
  `test/lecture_publish_visibility_test.dart`
- **Mobile**: `admin_content_remote_data_source_impl.dart`,
  `subject_learning_entities.dart`, `video_source_resolver.dart`,
  `playback_entities.dart`, `video_playback_controller.dart`
- **Security tests**: `security-tests/package.json`, `security-tests/rules.test.js`
- **Untracked**: `21_ADR_010_Multi_Library_Bunny_Stream.md`,
  `dashboard/lib/features/students/{data/bunny_association_gateway.dart,domain/bunny_library_association.dart,domain/bunny_library_catalog.dart,domain/live_student.dart}`,
  `dashboard/test/bunny_library_{association,dialog,persistence,selection}_test.dart`,
  `dashboard/test/live_student_filter_test.dart`,
  `functions/src/core/video/` (registry, migration, validation, association),
  `functions/src/scripts/backfill_bunny_library_id.ts`,
  `functions/test/bunny_*`, `functions/test/issuance_library_flow.test.js`,
  `reports/`, `security-tests/adr010_association_rules.test.js`,
  `test/features/video_streaming/`

### User modifications vs previous agent

The working tree mixes several missions' work. No file can be attributed to a
human edit with certainty, and nothing was discarded, stashed or reformatted.
The iOS/CI files (`.github/workflows/ci.yml`, hosting cache) and the unrelated
Dashboard providers (`join_applications_provider`, `home_stats_provider`,
`quick_announcement_dialog`, `grade_*`, `live_student.dart`,
`live_student_filter_test.dart`, `acceptance_notification.test.js`) are clearly
outside ADR-010 and were treated as pre-existing user/parallel work: **left
untouched**.

### Line endings

Measured at handover and preserved:

| File | Line endings |
|---|---|
| `functions/src/index.ts` | CRLF (9366 CRLF / 0 LF) — preserved |
| `dashboard/.../quick_upload_modal.dart` | CRLF — preserved |
| `functions/test/progress_percentage.test.js` | LF — preserved |
| `functions/test/bunny_association_flow.test.js` | LF (new file) |
| `dashboard/test/bunny_library_persistence_test.dart` | LF (new file) |

No mass formatting was performed.

## 2. Previous work verified in the repository (not trusted from reports)

| Claim | Verified |
|---|---|
| Registry + pure resolver + fail-closed | Yes — `functions/src/core/video/bunny_library_registry.ts` |
| Migration planner / dry-run CLI / no writes | Yes — `bunny_library_migration.ts`, `scripts/backfill_bunny_library_id.ts` |
| HMAC validation receipt + `validateBunnyVideoAssociation` | Yes — `bunny_video_validation.ts`, `index.ts:4914` |
| Server association callable | Yes — `associateBunnyVideoToLibrary`, `index.ts:5006` |
| Transactional persistence + `first_video` recompute | Yes — re-read inside transaction, trusted row projection |
| Rules deny client association writes | Yes — `firestore.rules` `lecture_resources` create/update |
| Playback gate for pending rows | Yes — `mayResolveBunnyLibraryForPlayback` at issuance + display media |
| Dashboard gateway + controller integration | Yes — `bunny_association_gateway.dart`, `subject_details_provider.dart` |
| Mobile authoring integration | Yes — `admin_content_remote_data_source_impl.dart` |
| Flutter additive parsing/hint | Yes — `VideoResource`, `FirstVideoRef`, `VideoSourceResolver` |
| Fixture repair (`pcont-vid-*`, `pbs-vid-A`) | Yes — valid GUIDs, guard untouched |
| `progress_percentage` fixture fix | Yes — `status: "published"`, `is_deleted: false`, `subject_id` |

## 3. Gaps found during the audit (and fixed in this session)

1. **Quick Upload still wrote `bunny_library_id` directly** in
   `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`.
   With the new Rules this create is denied, so Quick Upload would fail
   outright. The previous report claimed this path was migrated; it was not.
   Fixed: the client no longer writes the association; it calls the server
   gateway after the row/pointer write. Covered by four new Dashboard tests.
2. **`progress_percentage` failed when run standalone** (`Summary doc should
   be created`). Root cause was emulator trigger-delivery latency (~22 s)
   versus the test's 15 s poll — not the aggregation, which produced 50/1/2
   when delivered. Fixed by extending the poll to the documented 120 s trigger
   readiness budget; assertions unchanged.
3. **Missing emulator case for subject mismatch** in the association suite
   (A10 item 7). Added a resource/lecture subject-disagreement case.

## 4. Baseline checks reproduced at handover

| Check | Result |
|---|---|
| `cd functions && npm run build` | PASS (exit 0) |
| `npm run test:pure` | PASS (exit 0) |
| `protected_content.test.js` (emulator) | PASS — 20 scenarios |
| `playback_session.test.js` (emulator) | PASS — 18 scenarios |
| `progress_percentage.test.js` (standalone) | **FAIL** — `Summary doc should be created` (trigger delivery 22 s > 15 s poll) |
| `npm test` (full emulator suite) | PASS — 51/51 files |

The two historical legacy failures (`pcont-vid-V`, `pbs-vid-A`) are already
repaired in the working tree; the production VIDEO-ID-ONLY guard is untouched.

## 5. Safe next implementation point

1. Re-run the final full backend suite after the Quick Upload and timing fixes
   (done in `mission_4_final_report.md`).
2. Rules deployment order: Functions first, then Rules (otherwise new video
   rows stay pending/unplayable — fail-closed but a functional stop).
3. Do not activate `775315`; its credentials/template/pull-zone security are
   still incomplete.
