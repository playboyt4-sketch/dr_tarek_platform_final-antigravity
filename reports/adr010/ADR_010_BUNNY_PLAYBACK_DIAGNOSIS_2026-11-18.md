# ADR-010 - Bunny Playback Failure Diagnosis ("Video playback is not configured")

- Date: 2026-11-18
- Mode: read-only investigation (no source edits, no deploys, no config changes)
- Environment reported by owner: Staging
- Environment actually exercised: **Production** (`dr-tarek-platform`)
- Verdict: data + deployment defect, not a Bunny defect and not a backend logic defect

---

## A. Exact source file and line triggering the message

`lib/features/video_streaming/data/services/video_source_resolver.dart:655`

```
648: String _staticMessageFor(String code) {
649:   return switch (code) {
...
654:     'failed-precondition' =>
655:       'Video playback is not configured. Please contact support.',
```

The string exists in exactly one place in the repository (full-tree literal search).
It is produced only through `classifyVideoSourceError(...)` (same file, L609), which is
called from exactly one site: L385, inside the `on FirebaseFunctionsException catch`
of `generateBunnySignedUrl` (L336-338). Therefore the displayed text is a client-side
rendering of a **server-side `failed-precondition`** result. The client never decides
this message on its own.

---

## B. Full playback call chain (actual function names)

Client:

1. `VideoStreamingScreen` -> `lib/features/video_streaming/presentation/screens/video_streaming_screen.dart:88`
   builds the controller with `sourceResolver: ref.read(videoSourceResolverProvider)`.
2. `videoSourceResolverProvider` -> `lib/features/video_streaming/presentation/providers/video_streaming_providers.dart:10-11`
   returns `VideoSourceResolver(functions: FirebaseFunctions.instance)`.
3. `VideoPlaybackController.initialize()` -> `video_playback_controller.dart:268`
   -> `_loadEngine(...)` L647
   -> `sourceResolver.resolve(...)` L676.
4. `VideoSourceResolver.resolve(...)` -> `video_source_resolver.dart:295`
   -> `functions.httpsCallable('generateBunnySignedUrl').call(payload)` L336-338
   (payload: `videoId`, `lectureId`, `subjectId`, `quality`, `deviceId`).
5. On failure: `on FirebaseFunctionsException` L380 -> `classifyVideoSourceError(error.code, ...)` L385
   -> `_staticMessageFor('failed-precondition')` L645 -> L655.
6. `VideoPlaybackController` catch L358-369 sets
   `playbackStatus = PlayerPlaybackStatus.error` and `errorMessage = error.message` (L366-367).
7. `video_overlay_controls.dart:126` renders `controller.errorMessage`.

Server (`functions/src/index.ts`):

8. `generateBunnySignedUrl` L4588 (onCall, secrets: `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY`).
9. `requireAuthenticated(request)` L4596 - passed (log line "Callable request verification passed").
10. `videoId` validation L4606-4612 - passed.
11. Resource lookup by video id + lecture - passed (single match).
12. **Gate L4713-4728**: `mayResolveBunnyLibraryForPlayback({createdAtMs, storedLibraryId, cutoverMs})`
    -> throws L4724-4727 `failed-precondition` "Video resource library association is pending verification."
13. Later steps never ran: `resolveIssuanceBunnyLibrary` L1745, tier resolution, quality resolution,
    `beginOrTakeoverSession`, token signing, and the identity log at L4991-4995 (absent from logs,
    consistent with an early exit).

---

## C. Exact failing condition and observed runtime value

Pure predicate: `functions/src/core/video/bunny_library_association.ts:225-233`

```
export function mayResolveBunnyLibraryForPlayback(input) {
  const stored = normalizeBunnyLibraryId(input.storedLibraryId);
  if (stored !== null) return true;                       // associated -> allowed
  return !isBunnyAssociationRequired(input.createdAtMs, input.cutoverMs);
}
```

with `isBunnyAssociationRequired` (L208-215): `createdAtMs >= cutoverMs`
and cutover default `BUNNY_ASSOCIATION_CUTOVER_DEFAULT = "2026-11-13T00:00:00.000Z"`
(L46), used because `BUNNY_ASSOCIATION_CUTOVER` is not set in Production.

Observed values for the failing request:

| Input | Observed value |
|---|---|
| `resource.bunny_library_id` | `null` (field absent) |
| `resource.created_at` | `2026-11-18T16:03:04.178Z` |
| cutover | `2026-11-13T00:00:00.000Z` |
| `storedLibraryId !== null` | `false` |
| `createdAtMs >= cutoverMs` | `true` |
| `mayResolveBunnyLibraryForPlayback(...)` | **`false`** -> throw |

Failing resource (no credentials involved):

- `lecture_resources/I36lvn3FGRPGCX3YKVLw`
- `bunny_video_id = 47561140-5966-4e0f-8851-83c78ce5bb92`
- `bunny_library_id` = **absent**
- `lecture_id = FjOezlpdF4gDoNfmZp44` (exists, `subject_id = RcuJQaqvJTMT40G105UI`, `section_id = AaM9s6Ufi4siImW8XZoa`, not deleted)
- `created_by = updated_by = 2B1pvLZ0p5W3hwoXlBi1rUtp0Iy2`
- `resource_url = ""`, `storage_provider = null`, `storage_path = null`, `thumbnail = null`
- `display_order = 1`, `is_visible = true`, `is_deleted = false`

This is the only post-cutover video row in Production. The other 6 video rows with a
`bunny_video_id` were created 2026-09-28 / 2026-11-04 (before the cutover) and remain
eligible through the documented legacy default-library fallback; none of them has a
`bunny_library_id` either.

---

## D. Root cause, with evidence

**Root cause:** a video row was authored after the ADR-010 cutover without a verified
library association, and the deployed Dashboard build is incapable of creating that
association. Playback is then refused by design.

Evidence chain:

1. **Server rejection is real and comes from Production.**
   `gcloud logging` for `dr-tarek-platform`, service `generatebunnysignedurl`,
   revision `generatebunnysignedurl-00036-ruw`:
   - `2026-11-18T16:04:39` HTTP **400**, `POST https://us-central1-dr-tarek-platform.cloudfunctions.net/generateBunnySignedUrl`
   - `2026-11-18T16:04:47` HTTP **400**, same URL
   - `userAgent: com.drtarek.platform/1.0.0 iPhone/27.2.1 hw/iPhone15_2`, `remoteIp 154.238.6.240`
   - `"Callable request verification passed"` present, identity log line absent.
   Firebase callables map `failed-precondition` to HTTP 400, matching the observed status.

2. **The deployed Production function contains this exact gate.**
   Deployed source archive `gs://gcf-v2-sources-606744934510-us-central1/generateBunnySignedUrl/function-source.zip`
   contains `mayResolveBunnyLibraryForPlayback`, `resolveBunnyAssociationCutoverMs`,
   `BUNNY_ASSOCIATION_CUTOVER_DEFAULT`, the literal `2026-11-13`, and
   "pending verification" - so this is not a stale-code mismatch.

3. **The row was created 1 min 43 s before the failed call.**
   `createTime = 2026-11-18T16:03:04.212559Z`, failure at `16:04:39`.
   Data was created through the Dashboard authoring flow, then played immediately.

4. **The association callables were never invoked.**
   Production logs, last 6 h: zero requests to `validatebunnyvideoassociation`
   and zero to `associatebunnyvideotolibrary`. So no association attempt failed -
   none was ever made.

5. **The deployed Dashboard bundle cannot make that call.**
   The dashboard is served from its own site, `https://dr-tarek-dashboard.web.app`
   (`<title>drtarek_dashboard</title>`), while `https://dr-tarek-platform.web.app`
   (`<title>Dr. Tarek El Araby Platform</title>`) is the student app. Both bundles were
   downloaded completely (4,217,801 and 5,229,583 bytes; each ends with the Dart bootstrap
   `...dartMainRunner(s,[])}else{s([])}})})()`) and string-probed:

   | Symbol | dashboard bundle | student bundle |
   |---|---|---|
   | `associateBunnyVideoToLibrary` | **ABSENT** | ABSENT |
   | `validateBunnyVideoAssociation` | **ABSENT** | ABSENT |
   | `listEligibleBunnyLibraries` | ABSENT | ABSENT |
   | `registerBunnyLibrary` | ABSENT | ABSENT |
   | `BunnyAssociationGateway` | **ABSENT** | ABSENT |
   | `bunny_library_id` | **ABSENT** | ABSENT |
   | `Add New Video` | **ABSENT** | ABSENT |
   | `bunny_video_id` | PRESENT | PRESENT |
   | `generateBunnySignedUrl` | ABSENT | PRESENT |

   The deployed dashboard build therefore predates both the Option C association gateway and
   the current authoring overlays (`dashboard/.../add_video_resource_overlay.dart:126`,
   `add_lecture_resources.dart:304`), whose strings are also absent from it.

   The working tree does contain the association gateway
   (`dashboard/lib/features/students/data/bunny_association_gateway.dart:54,84`) and the
   post-create hook (`subject_details_provider.dart:925-948`, called from L915), so the
   deployed Hosting build predates the Option C authoring code. Consistent with
   `dashboard/.firebase/hosting.YnVpbGRcd2Vi.cache` mtime `2026-11-08`.

6. **Row shape confirms the older writer.**
   The row carries `resource_url = ""` and `storage_provider = null`, fields that the
   current working-tree writers do not emit
   (`dashboard/.../quick_upload_modal.dart:435-455` writes `bunny_video_id`,
   `storage_path`, `thumbnail`, `duration`, but not `resource_url`/`storage_provider`).
   The deployed build's create path therefore differs from the working tree.

7. **The "Staging" test never touched Staging.**
   - Staging `generatebunnysignedurl`: **zero** invocations in the last 2 days;
     zero `failed-precondition` text in Staging logs over 3 days.
   - The Flutter app is hard-wired to Production:
     `lib/firebase_options.dart` L53/L62/L70 `projectId: 'dr-tarek-platform'` (sender `606744934510`),
     `ios/Runner/GoogleService-Info.plist` `PROJECT_ID=dr-tarek-platform`,
     `android/app/google-services.json` `project_id=dr-tarek-platform`.
   - The failing request's `requestUrl` is the Production host, and its UA is the native iOS app.

Ruled out (in code order, before/after the gate):

- Not authentication, App Check, or callable verification: "Callable request verification passed".
- Not `not-found` (row exists), not `ambiguous` (single row for that video id), not
  "not linked to a lecture" (`lecture_id` present, lecture document exists with `subject_id`/`section_id`).
- Not plan/permission: those checks are at L4770-4799, i.e. **after** the association gate, so they were never reached.
- Not Bunny library configuration, secrets, signing key, or playback URL template: execution
  stopped at L4724, before `resolveIssuanceBunnyLibrary` (L1745) and before any token signing.
- Not client player initialization: the URL was never minted, so no player was configured.

---

## E. Smallest correct fix

Two layers; the first restores the broken lecture, the second removes the recurrence.

1. **Immediate (data repair, no deploy):** for
   `(resourceId=I36lvn3FGRPGCX3YKVLw, lectureId=FjOezlpdF4gDoNfmZp44, libraryId=736742, videoId=47561140-5966-4e0f-8851-83c78ce5bb92)`
   run the already-deployed Production callables in order:
   `validateBunnyVideoAssociation` then `associateBunnyVideoToLibrary`
   (as an authorized admin actor). This writes the server-owned `bunny_library_id`
   and makes `mayResolveBunnyLibraryForPlayback` return `true`.
   Equivalent manual write is not acceptable: Firestore rules deny client writes to
   `bunny_library_id` (`firestore.rules:303-335`), by design.

2. **Durable (deployment):** publish the Option C Dashboard authoring build to Production
   Hosting, so every new video row is associated at creation time
   (`dashboard/.../subject_details_provider.dart:915,925` / `quick_upload_modal.dart:505-515`).
   This requires the G1-G6 Production authorization already tracked in
   `reports/adr010/ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_MANIFEST.md`.

No backend code change is required: the gate is behaving exactly as specified.

---

## F. Fault domain

- **Data-related (primary):** `lecture_resources/I36lvn3FGRPGCX3YKVLw` lacks
  `bunny_library_id` and was created after the association cutover.
- **Deployment/configuration (contributing cause):** the live Dashboard Hosting bundle
  predates the Option C association gateway, so it cannot satisfy the new write contract.
- **Not Bunny:** no Bunny API call was attempted; library `736742` was never consulted.
- **Not backend logic:** the deployed function correctly refused a pending row.
- **Environment mix-up (process, not code):** the reported "Staging" test executed against Production.

---

## G. Exact test that proves the fix

After step E.1, with the same student account and the same iPhone build:

1. Play lecture `FjOezlpdF4gDoNfmZp44` / video `47561140-5966-4e0f-8851-83c78ce5bb92`.
2. Expect: `generateBunnySignedUrl` returns HTTP 200 and the player starts.
3. Server-side proof: Production `generatebunnysignedurl` log shows the identity line
   `generateBunnySignedUrl identity requestedLecture=FjOezlpdF4gDoNfmZp44 ... library=736742`,
   and `lecture_resources/I36lvn3FGRPGCX3YKVLw.bunny_library_id == "736742"`.
4. Negative control: create a new video lecture through the Dashboard and play it.
   - With the current (old) Hosting build it must fail with the same message and the new row must have no `bunny_library_id`.
   - After E.2 it must succeed, and the row must carry `bunny_library_id` plus a
     `validateBunnyVideoAssociation` / `associateBunnyVideoToLibrary` invocation in the logs.

Regression check to keep the design intact: a post-cutover row with `bunny_library_id`
removed must still return HTTP 400 with "association is pending verification"
(i.e. do not "fix" this by relaxing the gate or by backfilling all rows blindly).

---

## H. Browser reproduction attempt (Chrome browse bridge, 2026-11-18 18:2x UTC)

Requested flow: open the Staging student app in the user's Chrome and reproduce the error.

Findings:

1. **Tabs:** only the agent-owned Figma tab was visible. No student tab was lent to the
   agent, so no existing authenticated session was reachable through the bridge.
2. **No Staging web deployment exists.**
   - `dr-tarek-staging` Hosting site exists in project `dr-tarek-staging`
     (`firebase hosting:sites:list`), but `https://dr-tarek-staging.web.app` returns
     HTTP **404** on both GET and HEAD: the site has no release.
   - There is no other Staging site or alias; `staging.dr-tarek-platform.web.app` does not resolve.
3. **The only runnable clients are Production.** `https://dr-tarek-platform.web.app`
   is the student web app and is compiled against `dr-tarek-platform`; the mobile builds
   are equally hard-wired (see section D.7).
4. **No local staging build is running** (no Flutter web dev server on any listening port).

Consequence: reproducing the failure in the browser would require driving Production, which
the task rules prohibit, and no authorized Staging session exists to drive instead.
The failure is therefore evidenced from server logs, deployed artefacts and data, not from a
browser console trace. **Missing requirement:** a Staging-configured client build plus an
authorized test account (or explicit owner authorization to exercise the Production web app
read-only for this single lecture).

---

## Appendix - Evidence index (read-only artefacts)

- Production 400 entry: `D:\Temp\opencode\prod_400_entry.json`
- Hosting bundle probes: `D:\Temp\opencode\hosting_probe\dr-tarek-dashboard.js` (4,217,801 bytes),
  `D:\Temp\opencode\hosting_probe\dr-tarek-platform.js` (5,229,583 bytes)
- Deployed Production source: `D:\Temp\opencode\prod_src_gen\` (`function-source.zip` + extracted)
- Staging logs: zero `generatebunnysignedurl` invocations (2 d), zero `failed-precondition` (3 d)
- Production census: 14 `lecture_resources` (13 video), 7 with `bunny_video_id`, 0 with `bunny_library_id`,
  exactly 1 post-cutover video row (`I36lvn3FGRPGCX3YKVLw`)
