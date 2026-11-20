# FINAL — Bunny Multi-Library Management and Real Video Playback Closure

**Mission:** Close Bunny multi-library management and real Flutter video playback end-to-end on Staging, then prepare a Production release package awaiting owner approval.
**Date:** 2026-11-16
**Governing decision:** `docs/ADR-010` (approved). Draft / In-Review documents were not used to override approved decisions.
**Repository:** `D:\antigravity\dr_tarek_platform_final`
**Branch:** `ci/ios-staging-codemagic` — **HEAD `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`** (unchanged; nothing committed)

---

## 1. Mission objective and authorization boundary

Objective: prove, end to end on Staging, that (a) multiple Bunny Stream libraries are managed through the server-side catalog with per-library credentials, (b) association/validation/issuance remain fail-closed and library-scoped, and (c) a **real Flutter client plays a real Bunny video** — then package a Production release for owner approval.

Authorization actually exercised:

| Area | Authorization used | Effect |
| --- | --- | --- |
| Staging provisioning | Authorized (Staging-only) | Catalog doc, per-library secrets, env allow-list, synthetic dataset |
| Staging deployment | Authorized (Staging-only) | 7 Bunny callables redeployed to `dr-tarek-staging` |
| Staging IAM | Staging-only, least privilege | One self-scoped `roles/iam.serviceAccountTokenCreator` binding |
| Staging Auth | Staging-only additive | Identity Platform initialized so real login can be proven |
| Production | **Read-only, explicitly scoped** | Audit only; **no writes, no deploys, no secrets, no IAM** |

Production was never written to, deployed to, or reconfigured. `775315` was never activated.

---

## 2. Repository and environment baseline (Phase 0)

| Item | Value |
| --- | --- |
| Working tree at start and end | 63 status entries (31 modified, 32 untracked, 0 staged, 0 deleted) |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| Branch | `ci/ios-staging-codemagic` |
| Commits created | none |
| Source files modified by this mission | none (all harness scripts live outside the repo in `D:\Temp\opencode`) |
| Firebase alias default | `dr-tarek-platform` (Production) |
| Firebase alias staging | `dr-tarek-staging` |
| Project id discipline | every command passed `--project dr-tarek-staging` explicitly |

`gcloud` active project is Production, so every Staging call was pinned explicitly; this was verified in the output of each command.

---

## 3. Constraints and prohibitions observed

- No `git reset`, `git clean`, destructive checkout, stash/discard, commit or push.
- No Production secret creation, IAM change, Firestore write, Functions/Rules/Hosting deployment, or migration execution.
- No secret value appears in this report, in logs, or in terminal evidence. Credential provenance is described by HTTP status and metadata only.
- No credential, test identity, or evidence was fabricated; every status below came from an executed call.
- Draft/In-Review documentation did not override approved ADR-010 decisions; no architecture conflict was found that required a STOP.

---

## 4. Architecture under test

| Component | File | Role |
| --- | --- | --- |
| Library registry (pure) | `functions/src/core/video/bunny_library_registry.ts` | Maps a stored `bunny_library_id` to its env/secret identity; Mission 19 identity isolation |
| Secret resolver | `functions/src/core/video/bunny_library_secret_resolver.ts` | Reads only the requested library's secret, catalog-first, legacy-default fallback |
| Catalog contract | `functions/src/core/video/bunny_library_catalog.ts` | Validation + activation gate + client-safe projection |
| Catalog reader | `functions/src/core/video/bunny_library_catalog_reader.ts` | Eligible-library projection, deterministic order, emergency allow-list |
| Association | `functions/src/core/video/bunny_library_association.ts` | Shape planning, cutover gate, signed receipts |
| Callables | `functions/src/index.ts` | `listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `generateBunnySignedUrl`, `generateBunnyResourceUrl`, `getLectureResources`, `getSectionDisplayMedia` |

Mission 19 identity isolation is present in current source: a foreign default is skipped, and the default bypass is scoped to the environment's own canonical default only.

---

## 5. Staging catalog state

`bunny_libraries/780700` (Staging only), written once and read back:

| Field | Value |
| --- | --- |
| `status` | `active` |
| `token_auth_enabled` | `true` |
| `token_auth_verified` | `true` |
| `source` | `legacy_env` |
| credential references | deterministic `BUNNY_780700_STREAM_API_KEY` / `BUNNY_780700_TOKEN_KEY` |
| pull zone | `6807898` |
| playback host | `vz-b5f9cb68-f06.b-cdn.net` |

The document was contract-validated against `parseBunnyCatalogEntry` + the activation gate before deployment.

---

## 6. Staging secret provisioning and provenance

Created (Staging only): `BUNNY_780700_STREAM_API_KEY` v1 `ENABLED`, `BUNNY_780700_TOKEN_KEY` v1 `ENABLED`.
Each was granted `roles/secretmanager.secretAccessor` **per secret** to `13159003436-compute@developer.gserviceaccount.com`. Legacy secrets were left untouched.

Provenance was established without printing values:

| Probe | Result |
| --- | --- |
| Stream API key vs library `780700` | HTTP 200 |
| Stream API key vs `736742` | HTTP 401 |
| Stream API key vs `775315` | HTTP 401 |
| Token key: master playlist | HTTP 200 |
| Token key: variant playlist | HTTP 200 |
| Token key: segment `video0.ts` | HTTP 200, `131224` bytes, `video/mp2t` |
| Unsigned / wrong signature | HTTP 403 |

Conclusion: the Staging legacy secrets are authoritative for library `780700`; the per-library secrets are derived from them, not from Production.

---

## 7. IAM remediation for custom-token signing (Staging only)

Real login requires `createCustomToken`, which needs `iam.serviceAccounts.signBlob`.

Before: the runtime service account had no self-binding and every `verifyPhonePassword` call failed with
`Permission 'iam.serviceAccounts.signBlob' denied` (logged as `auth/insufficient-permission`).

Applied (Staging only, least privilege):

```
roles/iam.serviceAccountTokenCreator
  → member: serviceAccount:13159003436-compute@developer.gserviceaccount.com
  → resource: 13159003436-compute@developer.gserviceaccount.com (itself)
```

Verified policy afterwards contains exactly one binding, one role, one member (itself). No project-wide role was added. After IAM propagation, `verifyPhonePassword` succeeded for both identities.

Local ADC still cannot sign (user credentials, no `signBlob`), so all token minting was done by the deployed callable — which is also the real product path.

---

## 8. Staging Auth provisioning

The Staging project had only `hostingSite` provisioned; Identity Toolkit returned `CONFIGURATION_NOT_FOUND`, so no login was possible.

Action: `identitytoolkit.googleapis.com/v2/projects/dr-tarek-staging/identityPlatform:initializeAuth` → `{}` (additive, Staging-only).

No Production Auth resource was touched.

---

## 9. Staging deployment record

Deployed exactly seven callables, nothing else (no Hosting, no unrelated functions, no rules):

| Function | Update time (UTC) |
| --- | --- |
| `listEligibleBunnyLibraries` | 2026-11-16T11:27:02Z |
| `generateBunnySignedUrl` | 2026-11-16T11:27:05Z |
| `associateBunnyVideoToLibrary` | 2026-11-16T11:27:06Z |
| `getSectionDisplayMedia` | 2026-11-16T11:27:06Z |
| `generateBunnyResourceUrl` | 2026-11-16T11:27:06Z |
| `getLectureResources` | 2026-11-16T11:27:07Z |
| `validateBunnyVideoAssociation` | 2026-11-16T11:27:07Z |

All run as `13159003436-compute@developer.gserviceaccount.com`.

---

## 10. Post-deployment runtime verification

Runtime configuration read back from the deployed functions (no values printed beyond non-secret switches):

| Variable | `listEligibleBunnyLibraries` |
| --- | --- |
| `GCLOUD_PROJECT` | `dr-tarek-staging` |
| `BUNNY_STREAM_LIBRARY_ID` | `780700` |
| `BUNNY_DEFAULT_LIBRARY_ID` | `780700` |
| `BUNNY_ACTIVE_LIBRARY_IDS` | `780700` (emergency allow-list) |
| `APP_CHECK_ENFORCEMENT` | `false` |

Secret mounts are the legacy Bunny secrets only (`BUNNY_TOKEN_KEY:1`, `BUNNY_PLAYBACK_URL_TEMPLATE:1`, `BUNNY_STREAM_API_KEY:2`); no Production value is present in any Staging function.

Unauthenticated probes of `listEligibleBunnyLibraries` and `generateBunnySignedUrl` return **401** (fail closed).

Deployment-prelude note: the CLI also loaded the git-ignored `functions/.env` (Production dotenv). It was verified that its malformed content did **not** leak into the Staging deployment — the deployed env shows the correct Staging values above.

---

## 11. Synthetic Staging dataset (fixtures)

Staging Firestore contained only the catalog document, so a minimal, deterministic dataset was provisioned with the Admin SDK (idempotent `set(..., {merge:true})`):

| Kind | Ids |
| --- | --- |
| Identities | `stgdoctoradr01001` (01000000001), `stgstudentadr01001` (01000000002) |
| Content | `stg_subject_adr010` → `stg_section_adr010` → `stg_lecture_adr010` (+ `_b`, `_empty`) |
| Video resources | `stg_resource_adr010`, `stg_resource_adr010_b` (video `47561140-5966-4e0f-8851-83c78ce5bb92`, library `780700`) |
| Entitlement | plan `stg_plan_pro_adr010` + 6 plan features, subscription `stg_sub_adr010`, assignment `stgstudentadr01001_stg_subject_adr010` |

Read-back confirmed every document, 6 plan features, and the custom claims (`role`, `student_type`, `approved`) for both identities. Test passwords were generated locally and stored only in `D:\Temp\opencode\stg_*_pw.txt`; they are not reproduced here.

---

## 12. Server-side end-to-end verification

Both identities authenticated through the product's own `verifyPhonePassword` callable and exchanged the returned custom token through Identity Toolkit.

| Check | Result |
| --- | --- |
| Doctor login | `OK`, `userIdMatches=true` |
| Student login | `OK`, `userIdMatches=true` |
| `listEligibleBunnyLibraries` (doctor) | `200` → `[{"libraryId":"780700","displayName":"DrTarek Staging Test Library"}]` |
| `listEligibleBunnyLibraries` (student) | `403 PERMISSION_DENIED` |
| `listEligibleBunnyLibraries` (anonymous) | `401 UNAUTHENTICATED` |
| `validateBunnyVideoAssociation` `780700` | `200` `verified` / `ok` / receipt issued |
| `validateBunnyVideoAssociation` `736742` | `200` `unavailable` / `unknown_library` |
| `validateBunnyVideoAssociation` `775315` | `200` `unavailable` / `inactive_library` |
| `validateBunnyVideoAssociation` `999999` | `200` `unavailable` / `unknown_library` |
| `validateBunnyVideoAssociation` (student) | `403 PERMISSION_DENIED` |
| Bound receipt + `associateBunnyVideoToLibrary` | `200 already_associated` (library `780700`, correct video) |
| `getLectureResources` (student) | `200`, `count=1`, `libraryId=780700`, order `0` |
| `generateBunnySignedUrl` (student) | `200`, `quality=720p`, time-bounded token carried in the URL path |
| Cross-library hint `libraryId=736742` | `400 FAILED_PRECONDITION` `library_mismatch` |
| Foreign subject | `400 INVALID_ARGUMENT` `Subject does not match this video.` |

---

## 13. Authorization and identity negative controls

| Negative test | Expected | Observed |
| --- | --- | --- |
| Receipt bound to resource A replayed onto existing resource B | refuse | `403 PERMISSION_DENIED` "A valid verification receipt for this resource is required." |
| Correctly bound receipt for B | accept | `200 already_associated` |
| Forged receipt string | refuse | `403 PERMISSION_DENIED` (same message) |
| Same video id asserted against a lecture with no resource | refuse | `400 INVALID_ARGUMENT` "The requested lecture is not linked to this video." |
| Unknown video id with a real lecture | refuse | `400 INVALID_ARGUMENT` (same message) |
| Malformed device id (`short`) | refuse | `400 INVALID_ARGUMENT` "A valid device identifier is required." |

The lecture-scoped lookup result is the direct proof of the Mission 19 identity fix: a video that exists on another lecture can no longer be authorized through a different lecture.

---

## 14. CDN / token enforcement evidence

Server-side fetch of the issued URL (with the approved `Referer`):

| Resource | Status |
| --- | --- |
| Master `playlist.m3u8` | `200`, `322` bytes, `#EXTM3U` present |
| Variant `360p/video.m3u8`, `240p/video.m3u8` | `200` |
| Segment `video0.ts` | `200`, `131224` bytes |
| Same path without `bcdn_token` | `403` |

The token is a path component (`/bcdn_token=HS256-…&token_path=…&expires=…/playlist.m3u8`), so a leaked playlist URL is time-bounded.

---

## 15. Real Flutter playback evidence (primary proof)

Target selection: this machine exposes only Windows desktop, Chrome and Edge (`flutter devices`). The Windows target has no `video_player` platform implementation in this dependency set (`video_player` ships Android, AVFoundation and Web only), so the runnable, representative target is **Flutter web in real Chrome**. No mock player, no stubbed URL: the app's own `video_player` + `video_player_web_hls` stack drove a real `<video>` element.

Build: `flutter build web --debug --dart-define=ENV=staging` (Staging Firebase options selected by `Environment.optionsFor`), served locally on `127.0.0.1:8080`, driven in real Chrome via CDP.

Real product flow, no mocks: user-type screen → "current student" → phone/password → `verifyPhonePassword` → `signInWithCustomToken` → `#/student-home` → subject → lecture → player.

Observed on the live `<video>` element owned by the Flutter player:

| Evidence | Value |
| --- | --- |
| Source | `https://vz-b5f9cb68-f06.b-cdn.net/bcdn_token=HS256-…/playlist.m3u8` (token in path) |
| `readyState` | `4` (HAVE_ENOUGH_DATA) |
| `duration` | `4` s |
| Video dimensions | `640×360` |
| `paused` | `false` |
| `currentTime` samples | `1.3515 → 2.0728 → 2.8029 → 3.5484` |
| Advancement | `+0.721`, `+0.730`, `+0.745` s per `0.7` s sample (≈1× real time) |
| Rendered frame | SMPTE colour-bar test pattern visible in the captured screenshot |
| Watermark | `stgstudentadr01001` rendered by the app |

In-app network during that playback:

| Request | Status |
| --- | --- |
| `generateBunnySignedUrl` | `200` |
| `…/playlist.m3u8` | `200` |
| `…/240p/video.m3u8` | `200` |
| `…/240p/video0.ts` | `206` (range request, real media bytes) |
| `…/360p/video.m3u8` | `200` |

Screenshots captured: `shot_play_a.png`, `shot_play_b.png` (frame visible, no dialog), plus `shot_playing2.png` (frame + resume prompt).

---

## 16. Progress persistence and device binding

- The app displayed **"استئناف من حيث توقفت؟"** (resume where you left off?) with *from the beginning* / *continue* — proving it read the persisted position from Firestore.
- After playback, the **client-written** `lecture_progress/stgstudentadr01001_stg_lecture_adr010` contains `student_id`, `lecture_id`, `subject_id`, `position_seconds=4.032`, `duration_seconds=4.032`, `progress_percent=100`, `updated_at=2026-11-16T12:50:11Z`.
- Device binding: `subject_device_authorizations` for the student shows one `active` row created by the browser (`2026-11-16T12:48:21Z`) and one `revoked` row (the server-side test device).

Honest note on a test artifact: the plan allows `device.max_count=1`. My own server-side E2E had already consumed the single slot, so the first in-app attempt was correctly resolved as *guest* and the server refused it (`permission-denied`, `Guest preview is not enabled for this lecture.`); the client surfaced its generic "no permission / subscription ended" state. That is device enforcement working as designed, not a playback defect. The slot was released through the product's own doctor-only `resetStudentDevices` callable (`revokedCount: 1`), after which the browser claimed the slot and playback succeeded. No entitlement or device rule was weakened.

---

## 17. Regression and build validation

| Command | Result |
| --- | --- |
| `npm run build` (`tsc`) | exit 0 |
| `npm run test:pure` | exit 0 — all pure suites passing (resolver suite 40 checks, catalog reader suite 30 checks, identity-isolation cases incl. `staging explicit 736742 is rejected (allow-list cannot resurrect it)`) |
| Full suite (`FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test`) | **56/56 files passed, exit 0** |

Full-suite detail (final run, `functions/`, 2026-11-16):

```
> npm run build && firebase emulators:exec --project demo-tarek-platform --only firestore,functions,auth "node test/run_all.js"
...
===== SUITE SUMMARY =====
...
56/56 files passed.
```

The complete 56-file roster passed, including every ADR-010 suite:
`bunny_library_registry`, `bunny_default_library_config`, `bunny_library_catalog`,
`bunny_library_catalog_reader`, `bunny_library_migration`, `bunny_playback_regression` (33 checks),
`issuance_library_flow`, `bunny_library_validation_flow`, `bunny_library_association`,
`bunny_association_flow`, `bunny_library_catalog_flow`, `bunny_library_secret_resolver_flow`,
plus `wait_for_triggers` and the pre-existing product suites (device limits, guest migration,
progress percentage, protected content, offline DRM, payments, claims, throttles).

**Disclosed precondition (not a code change).** The Functions emulator refuses to load a function that
declares a secret when the local secret store has no value for it, which made
`test/wait_for_triggers.js` fail with `recalculateSubjectProgress did not deliver within 120s`
(`Failed to load function.`) in an intermediate run. That is an emulator environment precondition, not a
regression. It was fixed the documented way — a git-ignored, emulator-only
`functions/.secret.local` holding **placeholder** values (`emulator-not-a-real-*`), confirmed ignored by
`git check-ignore` (`functions/.gitignore:10:*.local`). No real credential is stored there, and the
repository status count is unchanged (63 entries). With that file present, `wait_for_triggers.js` passes:
`wait_for_triggers: PASS - recalculateSubjectProgress delivery proven.`

---

## 18. Production read-only verification

All reads were explicitly scoped to `dr-tarek-platform`; nothing was written.

| Check | Result |
| --- | --- |
| Production Bunny callables update times | unchanged since **2026-10-08** (no ADR-010 deployment) |
| `BUNNY_ACTIVE_LIBRARY_IDS` on Production | absent |
| `BUNNY_DEFAULT_LIBRARY_ID` on Production | absent |
| `bunny_libraries` collection | empty / absent |
| Production per-library secrets (`BUNNY_<id>_*`) | none |
| Production legacy secrets | `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_*`, `BUNNY_TOKEN_KEY` |

Conclusion: ADR-010 is **not active** in Production and Production behaviour is unchanged by this mission.

---

## 19. Production release prerequisites and security findings

Two findings must be resolved by the owner **before** any Production deployment. Both are pre-existing; neither was caused by this mission.

1. **Production has no `BUNNY_STREAM_API_KEY` secret.** `gcloud secrets describe` returns `NOT_FOUND`. The Production catalog/secrets prerequisite is therefore incomplete for a multi-library release.
2. **Production `APP_CHECK_ENFORCEMENT` is a corrupted, concatenated value.** It contains the text `false` followed by a Bunny-Stream-API-key-shaped string and `BUNNY_STREAM_LIBRARY_ID=736742` (value redacted here). Consequences:
   - `SECURE_CALL_OPTS` compares against the literal `"true"`, so enforcement is effectively off;
   - a Stream API key is stored in plaintext in a function environment variable, readable by anyone with function-describe rights;
   - the same malformed 3-line content exists in the git-ignored, untracked `functions/.env`.

   Recommended owner action (not executed): rotate that key, move it to Secret Manager, and reset `APP_CHECK_ENFORCEMENT` to exactly `true`/`false`.

Release package (awaiting approval) is therefore: Staging-verified code + Staging-verified IAM/secret pattern, with the Production prerequisites above still open.

---

## 20. Dashboard library-picker UI status — **BLOCKED**

The picker UI cannot be implemented or verified:

- the approved Figma nodes (`58011:1024`, `58335:1444`, `871:1074`, `58171:1964`) are not retrievable from this environment;
- no Figma credential is available (`FIGMA_TOKEN` / `FIGMA_API_TOKEN` unset), and the previously configured token was rejected with HTTP 401.

Per the mission rule, the UI is marked **BLOCKED** rather than invented. The server-side surface the UI needs is complete and verified: `listEligibleBunnyLibraries` returns exactly `{libraryId, displayName}` for `780700` to a doctor, and rejects students (403) and anonymous callers (401).

---

## 21. Residual risks and rollback

Residual risks:

- App Check is not enforced in Staging (`APP_CHECK_ENFORCEMENT=false`) and the generated web debug token is unregistered, so App Check token fetches return 403 client-side. This does not affect authorization (all callables still require auth), but it means client attestation is not part of this proof.
- Staging now contains synthetic identities and content created for this verification.
- The Production env finding in section 19 remains open until the owner acts.

Rollback (Staging only, no Production impact):

1. Delete `bunny_libraries/780700`.
2. Remove `BUNNY_ACTIVE_LIBRARY_IDS` from `functions/.env.dr-tarek-staging`.
3. Delete secrets `BUNNY_780700_STREAM_API_KEY` / `BUNNY_780700_TOKEN_KEY` and their accessor bindings.
4. Remove the self-scoped `roles/iam.serviceAccountTokenCreator` binding.
5. Delete the synthetic fixtures (`stg_*` ids and the two test identities).
6. Redeploy the seven callables from the previous revision if the code itself must be rolled back.

No rollback was performed; the Staging environment is left in the verified state.

---

## 22. Final status

# PARTIALLY COMPLETE — SPECIFIC BLOCKERS REMAIN

**Staging: fully verified end to end.** Multi-library management, per-library credential resolution,
fail-closed catalog/association gates, real signed-URL issuance, CDN token enforcement, and **real Flutter
video playback** (real `<video>`, real Bunny CDN bytes, advancing timeline, rendered frames, watermark,
persisted progress, device binding) all pass on `dr-tarek-staging`. Production was read-only and is
untouched by ADR-010.

**Specific blockers (each is external or owner-gated, none is a code defect):**

| # | Blocker | Nature | Owner action |
| --- | --- | --- | --- |
| 1 | Dashboard library-picker UI not built | Approved Figma nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` are not retrievable here; no Figma credential (`FIGMA_TOKEN`/`FIGMA_API_TOKEN` unset, prior token returned 401) | Provide Figma access or an approved design |
| 2 | Production has no `BUNNY_STREAM_API_KEY` secret | Pre-existing Production prerequisite for a multi-library release | Approve Production secret creation |
| 3 | Production `APP_CHECK_ENFORCEMENT` holds a corrupted, concatenated value embedding a Stream-API-key-shaped string and `BUNNY_STREAM_LIBRARY_ID=736742` | Pre-existing Production security finding (value redacted) | Approve rotation + Secret Manager move + reset to `true`/`false` |
| 4 | Production `bunny_libraries` catalog empty; Production Functions/Rules not deployed with ADR-010 | Intentionally not executed (prohibited without explicit approval) | Approve Production release |

Approvals still required from the owner:

1. Production secret creation for `BUNNY_STREAM_API_KEY` (and any per-library secrets) plus key rotation for the exposed key.
2. Production IAM / Firestore catalog writes (`bunny_libraries`) and the Production Functions deployment.
3. Approval or replacement of the dashboard picker design so the blocked UI can be built.

What is **not** blocking: Staging playback, entitlement, device binding, preview, DRM, quality tiers,
takeover, approval, and published-resource rules were all preserved and re-verified; `775315` was never
activated; no Staging/Production credential, host, or resource was mixed.
