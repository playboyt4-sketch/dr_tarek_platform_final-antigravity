# ADR-010 — Mission 7: Multi-Library Implementation Gate

Date: 2026-11-13
Mode: controlled local implementation + read-only verification. No deployment, no production
Firestore/Bunny change, no production backfill, no video upload, no activation of library `775315`.
Architecture under test: **Option C — Multi-Library Bunny Stream** (`21_ADR_010_Multi_Library_Bunny_Stream.md`).

**Final verdict: MISSION 7 — BLOCKED.**
Multi-library resolution, fail-closed behaviour, association verification and first-video consistency are
implemented and verified locally. The gate is not complete because library `775315` is not configured or
activated, production inventory cannot be independently re-verified in this environment, no approved
write-capable backfill executor exists, the Dashboard library picker has neither an approved Figma
specification nor a trusted backend catalog source, and the default association cutover instant has
already elapsed. Details in §C, §D, §E, §F, §H, §J.

---

## A. Baseline

| Item | Value |
|---|---|
| Repository root | `D:/antigravity/dr_tarek_platform_final` |
| HEAD (start and end) | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| Staged files | 0 |
| `git status --short` entries at start | 52 (28 modified tracked + 24 untracked) |
| `git status --short` entries at end | 55 (30 modified tracked + 25 untracked) |
| New status entries during Mission 7 | 3 (three tracked files edited, one new test file added) |
| Mission 6 `created_at` immutability | present — `firestore.rules:323` |

Pre-existing uncommitted work (ADR-010 core modules, Dashboard scaffolding, rules, video-streaming
client changes, CI workflow, reports) was preserved byte-for-byte except for the four paths listed in §K.
No file was reverted, reformatted, staged, committed, pushed, or deployed.

The Mission 7 delta is exactly:

1. `lib/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart` (modified)
2. `scripts/backfill_first_video.cjs` (modified)
3. `functions/test/first_video_backfill.test.js` (modified)
4. `test/features/content_authoring/lecture_first_video_fields_test.dart` (new)

No production code path in `functions/src/` and no Firestore/Storage rule was modified in Mission 7.

---

## B. Multi-Library Architecture

### B.1 Exact resolution path

1. **Storage.** `lecture_resources/{id}` carries the server-written association
   (`bunny_library_id`, `bunny_video_id`). Firestore Rules deny client writes to
   `bunny_library_id`; the Admin SDK bypasses Rules, so only callables can set it.
2. **Issuance entry.** `generateBunnySignedUrl` completes every authorization, entitlement, window and
   session verdict first, then calls `resolveIssuanceBunnyLibrary(resource, request.data.libraryId)`
   (`functions/src/index.ts:4803-4818`). Library resolution cannot change allow/deny precedence.
3. **Trusted resolution.** `resolveIssuanceBunnyLibrary` → `resolveBunnyLibraryForResource`
   (`functions/src/core/video/bunny_library_registry.ts:195-234`):
   - stored id → registry definition; unknown → `unknown_library`;
   - not active → `library_not_activated`;
   - stored id absent → legacy default fallback (disable-able via `BUNNY_LEGACY_LIBRARY_FALLBACK=false`),
     otherwise `legacy_fallback_disabled`.
4. **Credential isolation.** `resolveBunnyPlaybackRuntime(env, libraryId)`
   (`bunny_library_registry.ts:243-275`) reads *that library's* template and token-key env vars and fails
   with `incomplete_configuration` when either is blank. Signing then uses only the returned
   `playbackUrlTemplate` + `tokenKey` (`index.ts:4817-4860`).
5. **Stream metadata.** `resolveBunnyStreamApiRuntime` (`bunny_library_registry.ts:285-320`) resolves the
   per-library API key and API library id; poster cache identity is `${libraryId}:${videoId}`
   (`bunnyPosterCacheKey`, `bunny_library_registry.ts:128-133`).
6. **Display media.** Thumbnails/posters use the same resolver (`index.ts:1629-1697`, `1849-1864`).
7. **Client hint.** A client-supplied `libraryId` is compared with the stored value and a disagreement is
   `library_mismatch` (`bunny_library_registry.ts:205-207`). With no stored value the hint is discarded —
   it can never choose credentials.
8. **Read path.** `getLectureResources` returns `bunnyLibraryId` as additive metadata only
   (`index.ts:5404+`).

### B.2 Proof that resources resolve to different libraries

| Evidence (executed) | Result |
|---|---|
| `ok - default library stored on the resource resolves as resource-sourced` | pass |
| `ok - second library resolves once explicitly activated` | pass |
| `ok - activated second library signs with ITS OWN zone and key` | pass |
| `ok - default library never borrows another library's signing config` | pass |
| `ok - default library never borrows another library's API key` | pass |
| `ok - inactive library cannot be reached even with full credentials present` | pass |
| `ok - hint disagreeing with the stored library fails closed (no credential switch)` | pass |
| `ok - cache key is stable within a library` / `ok - unknown library is rejected` | pass |
| `ok - legacy row may resolve the default library` / `ok - verified row may resolve its library` / `ok - pending row may NOT resolve a library` | pass |
| `ok - unknown library id fails closed (denied failed-precondition)` | pass (real callable) |
| `ok - inactive library (775315) fails closed (denied failed-precondition)` | pass (real callable) |

Conclusion: resolution is per-resource and per-library, credentials are never shared across libraries,
and the client cannot redirect a resource to another library's signing material.

### B.3 Fail-closed matrix (registry)

| Condition | Reason | Playback |
|---|---|---|
| Stored id not in registry | `unknown_library` | refused |
| Registry library not in `BUNNY_ACTIVE_LIBRARY_IDS` | `library_not_activated` | refused |
| Template or token key blank | `incomplete_configuration` | refused |
| Client hint ≠ stored id | `library_mismatch` | refused |
| No stored id and fallback disabled | `legacy_fallback_disabled` | refused |
| No stored id, fallback enabled | `legacy_default` (736742) | allowed (migration window) |

---

## C. Library Capability Matrix

| Library | Stream API | Token Signing | Playback Host | Token Auth | Registry Status | Playback Eligible |
|---|---|---|---|---|---|---|
| `736742` (default) | CONFIGURED — `BUNNY_STREAM_API_KEY` + `BUNNY_STREAM_LIBRARY_ID` present in local `functions/.env` and staging env (names only inspected) | CONFIGURED in staging (`BUNNY_TOKEN_KEY`); **absent from local `functions/.env`**, so a local run fails closed | `vz-c6abe953-876.b-cdn.net` (verified by read-only CDN/Stream probes in the inventory report) | ENFORCED — HLS probe required a directory token (unsigned probe refused) | ACTIVE (default library, always active by design) | YES (when template + token key are present) |
| `775315` (content) | **NOT VERIFIED / NOT CONFIGURED** — no `BUNNY_775315_STREAM_API_KEY`; never verified with a library-scoped key in this mission | **NOT CONFIGURED** — no `BUNNY_775315_TOKEN_KEY`; no `BUNNY_775315_PLAYBACK_URL_TEMPLATE` | `vz-c850a9e1-eb4.b-cdn.net` (read-only Bunny dashboard + HLS probe evidence, prior inventory) | **NOT ENFORCED** — the pull zone served `playlist.m3u8` with HTTP 200 and no token | DEFINED, **NOT ACTIVATED** (absent from `BUNNY_ACTIVE_LIBRARY_IDS`) | **NO** |

`775315` activation checklist (prepared, deliberately **not executed**):

1. Create/confirm a Bunny Stream API key scoped to `775315`; store as `BUNNY_775315_STREAM_API_KEY`.
2. Enable Token Authentication on the `775315` Pull Zone; store the signing key as
   `BUNNY_775315_TOKEN_KEY` (must differ from `BUNNY_TOKEN_KEY`).
3. Record the exact playback template as `BUNNY_775315_PLAYBACK_URL_TEMPLATE`
   (host confirmed: `vz-c850a9e1-eb4.b-cdn.net`; template shape not yet verified).
4. Re-probe: unsigned HLS must be refused and correctly signed HLS must return
   `200 application/vnd.apple.mpegurl`; confirm hotlink/Referer policy.
5. Add `775315` to `BUNNY_ACTIVE_LIBRARY_IDS` in the target environment only, then verify a test
   resource resolves through `775315`'s own credentials.
6. Only then may Dashboard authoring offer `775315` as selectable.

All six steps are Owner/ops actions. This mission changed no Bunny account setting and no environment.

---

## D. Existing Video Inventory

Source: `reports/adr010/bunny_resource_inventory.md` / `.csv` (read-only production snapshot dated
2026-11-12). **Mission 7 could not re-verify production** (no production credentials in this
environment); the snapshot is therefore treated as *reported*, not *re-verified*. Current count remains
13 video resources — no evidence of a different count was available.

Stored `bunny_library_id` in the snapshot already equals the independently probed source library for
**all six** rows that carry a Video ID. No association write is required for those six.

| # | Resource ID | Lecture ID | Subject | Stored library | Stored Video ID | Source library (probe) | Publication / state | Association status | Recommended action |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `n2IpE7D3XslmNgBeeSeq` | `rtJ0JBuudn5beK6eB3Ue` | Accounting | `775315` | `7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31` | `775315` (HLS 200 only on its zone; 404 on `736742`) | published, resource live/visible | ASSOCIATED to inactive library → playback fails closed today | Keep. Activate `775315` per §C; do **not** migrate to `736742`. |
| 2 | `6xIQtr6XHq68FkHfkQ7C` | `nWwf4XGZJiQkUOofPhnQ` | Accounting | `775315` | `94710db9-8bd4-4c8e-ab21-4d68913dd9be` | `775315` (68:26 HLS) | published, live/visible | ASSOCIATED to inactive library → fails closed | Keep. Same activation path. |
| 3 | `mKzGszf8oiMQjkm0WzxW` | `QTAPgWN1vQcpZ8sgPjId` | Accounting | `775315` | `4dd8a3b0-4363-4f39-a21d-cb6bb7c2b99c` | `775315` (39:20 HLS) | published, live/visible | ASSOCIATED to inactive library → fails closed | Keep. Same activation path. |
| 4 | `TCmr0PTvUwVYrOkLzKyd` | `JyBPO388gp70DYdbddB4` | Accounting | `736742` | `6ffb23ad-f073-480d-9a68-43baaf9803d5` | `736742` (signed HLS 200) | lecture archived + deleted; resource live/visible | ASSOCIATED → playable | No library change. Archived/deleted issuance is a separate pre-existing issue (§J-8). |
| 5 | `iqfThonRycgDJ5xOdoKh` | `UG32WrckEwYnlCGA43Ux` | Accounting | `736742` | `6ffb23ad-f073-480d-9a68-43baaf9803d5` (**duplicate** of #4) | `736742` | lecture archived + deleted | ASSOCIATED; duplicate Video ID | No library change. Duplicate GUID flagged for Owner review; do not delete or merge. |
| 6 | `t9vPlLeXRlH5zG1UjPDE` | `9WJGceAhfYq6w0avq1RQ` | Accounting ethics | `736742` | `d0c31ca2-5bb0-4821-8f5d-64bde4bcc5de` | `736742` | published, live/visible | ASSOCIATED → playable | No action. |
| 7 | `1Lv5zsow5Ap5GJNaArcP` | `UNQPFUbQwwggZTH0JAj4` | Accounting ethics (test) | — | *(empty)* | none | published, live/visible | **UNRESOLVED** — placeholder row | Leave untouched. No video identity evidence exists; do not guess or upload. |
| 8 | `Ey3Nqi1zgTQ8hOpXOcYv` | `CvhGSQyEGAZfQ3NEQjK1` | Accounting | — | *(empty)* | none | lecture archived + deleted; resource live/visible | **UNRESOLVED** | Leave untouched. |
| 9 | `ICz33MA21JQSy9e8OJ7h` | `CvhGSQyEGAZfQ3NEQjK1` | Accounting | — | *(empty)* | none | lecture archived + deleted; resource deleted/hidden | **UNRESOLVED** | Leave untouched. |
| 10 | `YmV7LRp9diX9kUCn4PRT` | `cYI0V5VCA2yHVAJgkhPH` | Cost accounting (test) | — | *(empty)* | none | published, live/visible | **UNRESOLVED** | Leave untouched. |
| 11 | `ju1taw2UbenaC6FIrgFV` | `CAjfNajyccdQpsAwSE9L` | Companies (test) | — | *(empty)* | none | published, live/visible | **UNRESOLVED** | Leave untouched. |
| 12 | `qctAJDSdM9sxND9e2Ehq` | `J94QootP8CDYWBrwD28` | Accounting problems (test) | — | *(empty)* | none | published, live/visible | **UNRESOLVED** | Leave untouched. |
| 13 | `yjwx89srQkzr3d4PKdGe` | `lD3HNpB1mawsM0SAxI9H` | Government accounting (test) | — | *(empty)* | none | published, live/visible | **UNRESOLVED** | Leave untouched. |

Findings carried forward unchanged:

- No library was inferred from title, subject, grade, or ordering.
- No existing verified association was overwritten; no record was created, deleted, or re-uploaded.
- 7 rows are placeholders with an empty Video ID: they cannot play in any library and are explicitly
  documented as unresolved rather than guessed.
- 3 resources belonging to archived+deleted lectures remain issuable (pre-existing; out of ADR-010 scope).
- One Video ID is duplicated across two resource documents.

---

## E. Backfill

### E.1 Current behaviour (verified by reading and by tests)

- `functions/src/core/video/bunny_library_migration.ts` is a pure planner. It validates mapping entries
  against the same registry the runtime uses, rejects duplicate video/resource ids, rejects a stored
  library that disagrees with the mapping (`conflict`, never overwritten), skips non-video and empty
  `bunny_video_id` rows, and is idempotent (`unchanged` when already correct).
- `functions/src/scripts/backfill_bunny_library_id.ts` is read-only by construction: the pure
  execution-mode guard refuses `--apply` (exit code 3). It emits a plan JSON and a backup JSON.
- Test evidence: `bunny_library_migration tests passed (37)`, including
  `ok - stored library disagreeing with the mapping is a conflict, never overwritten`,
  `ok - mapping to an unactivated library is rejected`,
  `ok - conflicting stored library is never overwritten`.

### E.2 Safe write design (documented, not implemented)

A future executor must: run as a server-side admin process; require an explicit mapping file of
`(videoId, libraryId, resourceId, lectureId, subjectId)`; dry-run by default; re-verify each pair against
that library's Stream API immediately before writing; use a transaction/compare-and-set on the previously
read values; refuse on any drift, conflict, unknown/inactive/incomplete library, or pre-existing different
association; write only `bunny_library_id` (+ audit fields); never touch `bunny_video_id`, publication
state, ordering, subscription, or device-binding data; and emit an append-only audit record.

### E.3 Decision

**Not implemented.** Implementing it would require (a) an approved operational runbook and Owner
authorization for production data writes, (b) production credentials, and (c) an accepted audit-log
schema — i.e. decisions outside this mission's approved scope. It is also not currently required: all six
playable resources already carry the correct stored association (§D), and the seven remaining rows have no
Video ID to associate.

**No production backfill was executed. `--apply` was never run against production. No write-capable path
was added.**

---

## F. Dashboard Library Picker

### F.1 Existing implementation

| Component | State |
|---|---|
| `dashboard/lib/features/students/domain/bunny_library_association.dart` | Pure helpers: id normalization/validation, `bunnyLibraryIdForCreate` (defaults to `736742`), `bunnyLibraryIdForUpdate` (preserves stored value). |
| `dashboard/lib/features/students/domain/bunny_library_catalog.dart` | Static, non-secret catalog of 2 options: `736742` available+selectable, `775315` available but **not selectable**. Selection state machine (new / existing / legacy, Video-ID-change review). No rendering. |
| `dashboard/lib/features/students/data/bunny_association_gateway.dart` | `validateBunnyVideoAssociation` → `associateBunnyVideoToLibrary` with a resource-bound receipt. |
| `dashboard/.../subject_details_provider.dart` | Persists the association through the gateway; `firstVideoFields` includes `bunny_library_id`. |
| `dashboard/.../quick_upload_modal.dart:512` | `bunnyLibraryIdForCreate(resourceType: 'video')` → silently defaults to `736742`. |
| Visible picker widget | **Does not exist.** |

### F.2 Remaining gaps

1. **No visible picker** — BLOCKED pending an approved Figma specification. `docs/figma/` contains app and
   dashboard screen designs; no library-picker screen/specification exists. UI was not invented.
2. **No trusted backend catalog source** — the catalog is a client-side static list. A server endpoint
   returning eligible (active + fully configured) libraries would be a new callable/contract requiring an
   architectural decision; not added.
3. **Quick Upload cannot choose a library** — it always stages `736742`.
4. **Mobile authoring is single-library** — `admin_content_remote_data_source_impl.dart:75` hardcodes
   `_defaultBunnyLibraryId = '736742'` as the association fallback, so mobile cannot author into a second
   active library. This mirrors the server default and is safe today (only one library is active), but it
   is a real gap once `775315` is activated.
5. **Retry-after-failure** reuses the same default path; no library selection is possible after a failed
   association.

### F.3 Changes made

None. Mission 7 changed no Dashboard file.

### F.4 Tests executed

`cd dashboard && flutter test test/bunny_library_selection_test.dart test/bunny_library_association_test.dart test/bunny_library_dialog_test.dart test/bunny_library_persistence_test.dart`
→ exit 0, **54 tests passed** (catalog availability/selectability, legacy preservation, Video-ID-change
review, quick-upload default, serialization, gateway persistence).

---

## G. First Video Metadata

### G.1 Authority analysis

- `lectures/{id}.first_video` is a **denormalized display/fast-lane hint**, not a credential input.
- The authoritative association is `lecture_resources/{id}.bunny_library_id`. Issuance resolves the
  library from that stored resource document (`index.ts:4803-4818`) and compares any client hint; the
  `first_video` map is never used to choose credentials.
- Including `bunny_library_id` in the projection is explicitly permitted by ADR-010 (lines 67-69,
  additive/backward compatible) and is already produced by the server
  (`firstVideoFieldsFromResources`, `index.ts:8728+`; test `ok - first_video projection exposes bunny_library_id`).

### G.2 Implemented consistency fix

| File | Change |
|---|---|
| `lib/.../admin_content_remote_data_source_impl.dart` | New pure `lectureFirstVideoFields(...)`; `_syncLectureFirstVideo` now writes `bunny_library_id` from the winning resource row. |
| `scripts/backfill_first_video.cjs` | `firstVideoFields` emits `bunny_library_id` (trimmed, `null` when absent) and `sameFirstVideo` compares it, so a rerun cannot drop or flip the hint. |
| `functions/test/first_video_backfill.test.js` | Assertions updated for the new key, library-carrying row, and comparison sensitivity. |
| `test/features/content_authoring/lecture_first_video_fields_test.dart` | New 3-test regression file (verified hint, legacy null, identity-only shape / no URLs). |

No other lecture metadata was touched. The hint cannot bypass resource-level verification: the server
recomputes it and playback never reads it for credential selection.

### G.3 Tests executed

- `flutter test test/features/content_authoring/lecture_first_video_fields_test.dart` → exit 0, 3 tests.
- `flutter test test/features/content_authoring` → exit 0, 35 tests.
- `functions npm test` → `first_video_backfill tests passed (8 groups)`, including emulator end-to-end
  backfill with `bunny_library_id: "736742"` preserved.

---

## H. Cutover

| Item | Value |
|---|---|
| Source default | `BUNNY_ASSOCIATION_CUTOVER_DEFAULT = "2026-11-13T00:00:00.000Z"` (`bunny_library_association.ts:45`) |
| Local environment override | none — `functions/.env` holds only `APP_CHECK_ENFORCEMENT`, `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID`; `functions/.env.dr-tarek-staging` holds only default-library keys (names inspected, values not read into any report) |
| Malformed override behaviour | falls back to the default instant (`resolveBunnyAssociationCutoverMs`) |
| Classification | `created_at >= cutover` → association **required** (`isBunnyAssociationRequired`); unreadable/missing `created_at` → treated as **legacy** |
| Legacy rows | may use the default-library fallback (unless `BUNNY_LEGACY_LIBRARY_FALLBACK=false`) |
| Pending rows | post-cutover, no verified association → `mayResolveBunnyLibraryForPlayback` refuses |

**Boundary risk:** the default instant is 2026-11-13T00:00:00Z, i.e. the current date. Any resource created
today or later without a verified association is PENDING and will not play. Concretely:

- Dashboard new video / Quick Upload: default `736742` + validation callable → associated, fine.
- Mobile create: the client drops `bunny_library_id` and then calls the association callables with the
  default library. If validation fails (non-GUID placeholder, wrong library, inactive library, transient
  Stream API failure) the row already exists **without** an association and becomes unplayable until
  retried. This is the intended fail-closed behaviour, but it is an operational risk during the cutover day.
- Existing rows (all six playable ones) predate the cutover → unaffected.

**Required deployment-time procedure** (not executed; changing the default is not authorized here):

1. Before deploying, choose the cutover instant explicitly and set `BUNNY_ASSOCIATION_CUTOVER` in the
   target environment — either the actual deployment timestamp, or the timestamp of the last verified
   inventory/backfill. Do not rely on the built-in default once the date has passed.
2. Confirm no resource created at/after that instant lacks `bunny_library_id` (read-only query).
3. Keep `BUNNY_LEGACY_LIBRARY_FALLBACK=true` until every pre-cutover resource is verified.
4. Only after the inventory is fully resolved, set `BUNNY_LEGACY_LIBRARY_FALLBACK=false`.
5. Re-verify a legacy, a verified, and a pending row after deployment.

---

## I. Validation

All commands were run locally; none touched production.

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `cd functions && npm test` | 0 | **51/51 files passed**; ADR-010 suites: registry 30, migration 37, playback regression 33, issuance flow 11, validation flow 7, association 37, association flow 5, first-video backfill 8 groups |
| 2 | `flutter test test/features/content_authoring/lecture_first_video_fields_test.dart` | 0 | 3 tests |
| 3 | `flutter test test/features/content_authoring` | 0 | 35 tests |
| 4 | `flutter analyze` (repo root) | 0 | No issues found |
| 5 | `npx firebase emulators:exec --only firestore,storage --project dr-tarek-platform-rules-test "node security-tests/rules.test.js && node security-tests/adr010_association_rules.test.js"` | 0 | Firestore+Storage rules passed; `adr010_association_rules: 21 assertions passed` |
| 6 | `cd dashboard && flutter test <4 bunny test files>` | 0 | 54 tests |
| 7 | `git diff --check` | 0 | Clean (only pre-existing CRLF advisory warnings) |

Coverage of the required areas:

- Multi-library registry / resolution / fail-closed — suites 1 (registry, issuance flow).
- Association validation + transaction — suites 1 (validation flow, association, association flow).
- Playback gate + legacy/pending classification — suites 1 (playback regression, association).
- Firestore ADR-010 security + Mission 6 `created_at` immutability — suite 5.
- Dashboard association / picker scaffolding — suite 6.
- Flutter first-video consistency — suites 2, 3.
- First-video server/emulator backfill — suite 1.

**Not executed / not claimed:** CI (no push authorized), any deployment, any production probe or backfill,
`npm run lint` (known pre-existing red at HEAD from CRLF/lint debt unrelated to Mission 7), and any Bunny
network call against `775315`. No skipped tests were reported by the runners.

---

## J. Remaining Blockers

| # | Blocker | Classification |
|---|---|---|
| 1 | `775315` lacks a Stream API key, token-signing key, playback template and activation entry | **External Bunny account** + **Configuration** |
| 2 | `775315` Pull Zone does not enforce Token Authentication (unsigned HLS returns 200) — activating it as-is would issue URLs for a hotlinkable library | **External Bunny account** (security prerequisite) |
| 3 | Production inventory (13 rows) cannot be independently re-verified here; snapshot is 2026-11-12 and marked NOT RE-VERIFIED | **Production operational prerequisite** |
| 4 | No approved write-capable backfill executor / runbook / audit schema | **Documentation/approval** (+ Code once approved) |
| 5 | Dashboard picker has no approved Figma specification | **Documentation/approval** |
| 6 | No trusted backend endpoint lists eligible libraries; catalog is a hardcoded client list | **Documentation/approval** (contract decision) + **Code** |
| 7 | Mobile authoring hardcodes the `736742` fallback and cannot select another active library | **Code** (+ UX approval) |
| 8 | `BUNNY_ASSOCIATION_CUTOVER` default has elapsed; no explicit deployment instant chosen | **Production operational prerequisite** |
| 9 | `planBunnyAssociationWrite` receives the requested library as `storedLibraryId` and does not compare it with the resource's existing library — a same-GUID-in-two-libraries rebind would not be detected by the planner itself (mitigated by receipt binding and the single active library today) | **Code** (documented risk, not fixed — needs a decision) |
| 10 | Archived/deleted lectures remain issuable; duplicate Video ID exists | **Documentation/approval** (pre-existing, out of ADR-010 scope) |

Gate checklist:

| Completion condition | Status |
|---|---|
| Multi-library resolution verified | PASS (local tests) |
| Every resource reliably mapped or documented unresolved | PARTIAL — 6 mapped from a prior snapshot, 7 unresolved, snapshot not re-verifiable |
| Backfill safe and verified, or justified blocker documented | BLOCKED — justified blocker documented (§E) |
| Dashboard authoring no longer silently assumes one permanent library | FAIL — still defaults to `736742`; no picker |
| All creation paths respect server-side verification | PASS for verification; PARTIAL for library choice (mobile default-only) |
| First-video metadata does not undermine the association | PASS |
| Cutover understood and safe for the deployment sequence | FAIL — default instant elapsed; procedure not applied |
| Required local tests pass | PASS |

---

## K. Git Integrity

| Item | Value |
|---|---|
| Final HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged) |
| Staged files | 0 |
| Commits / pushes / tags | none |
| Deployments | none |
| Production reads/writes | none in this mission (no credentials used) |
| `git status --short` entries | 55 (30 modified + 25 untracked) |
| `git diff --check` | exit 0 |
| Generated emulator logs | `firestore-debug.log` (root and `functions/`) removed; both were git-ignored artifacts |

Files changed by Mission 7 only:

- `lib/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart`
- `scripts/backfill_first_video.cjs`
- `functions/test/first_video_backfill.test.js`
- `test/features/content_authoring/lecture_first_video_fields_test.dart` (new)
- `reports/adr010/mission_7_implementation_gate.md` (this report)

Every other modification in the working tree predates Mission 7 and was preserved.

---

## Verdict

**MISSION 7 — BLOCKED**

The multi-library core is real: playback resolves from the resource's stored, server-verified library,
per-library credentials are isolated, unknown/inactive/incomplete libraries fail closed, and a client hint
can never switch credentials. The first-video inconsistency is fixed and regression-tested.

The gate cannot close because the second library is not safely configurable yet (`775315` has no verified
Stream key, no token key, no template, no token-auth enforcement, no activation), the production inventory
cannot be independently re-verified in this environment, there is no approved write-capable backfill
executor, the Dashboard picker is blocked on Figma and a backend catalog contract, and the cutover instant
has already elapsed without an explicit deployment value. No production system was touched, and no
deployment planning is proposed here.
