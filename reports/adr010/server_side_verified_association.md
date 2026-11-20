# ADR-010 — Server-side Verified Association (Mission 4, Workstream A)

Status: **DONE (local implementation + emulator proof)**. No deployment, no
production writes, library `775315` still inactive.

## 1. Write-path audit (before any change)

| Path | Where it wrote `bunny_library_id` | Outcome |
|---|---|---|
| Add resource (subject details) | `SubjectDetailsController.createLectureFull` batch | client write (now removed) |
| Add resource (lecture form) | same provider create path | client write (now removed) |
| Edit resource | `updateLectureFull` `batch.update` | client write (now removed) |
| Edit with a changed Video ID | `updateLectureFull` | client wrote `bunny_video_id` (now server-only for verified rows) |
| Quick Upload | provider create path | client write (now removed) |
| Mobile admin authoring | `admin_content_remote_data_source_impl` | only wrote `bunny_video_id`; now calls the association callable |
| `lectures.first_video` | dashboard batch + scheduler | dashboard value is now a display pointer only; the association callable recomputes it from trusted rows |
| `firstVideoFieldsFromResources` (server) | scheduler / callable | trusted; includes the verified library id |

Every client write of the association was removed; the only remaining writer is
the Admin SDK callable (which bypasses Rules by design).

## 2. Security model

1. A client may submit: resource id, lecture id, requested library id, Video ID
   and a validation receipt. All are untrusted input.
2. The server resolves the library through the **registry** (unknown / inactive
   / incomplete configuration fail closed). A client library id never selects
   credentials directly; it is only the key the registry is asked about.
3. The server reads the resource and lecture documents (twice: before and
   inside the transaction) and rejects: missing/deleted resource or lecture,
   `resource_type != video`, `resource.lecture_id != lectureId`,
   `resource.subject_id != lecture.subject_id`, malformed Video ID, and a
   stored Video ID that differs without an explicit `replaceVideo: true`.
4. The receipt must verify for **exactly** (resourceId, lectureId, libraryId,
   videoId) and be unexpired. It is domain-separated
   (`adr010-association-v1`) from the earlier library+video receipt, so one
   receipt can never be replayed as the other.
5. Only then does it write `bunny_library_id` (plus `bunny_video_id` when
   binding/replacing) and recompute `lectures/{id}.first_video` from the
   trusted rows in the same transaction.

## 3. Callable contract

### `validateBunnyVideoAssociation` (extended)

Request: `{libraryId, videoId, resourceId?, lectureId?}`.
Authorization: **Doctor or delegated `admin_content`** (`requireContentManager`).
Response on success: `{status:"verified", reason:"ok", libraryId, videoId,
receipt}` where `receipt` is bound to the resource+lecture when both were
supplied (otherwise the legacy library+video receipt).
Non-success: `{status:"mismatch"|"unavailable"|"rejected", reason, libraryId,
videoId, receipt:null}`. No credentials, template, zone or key is returned.

### `associateBunnyVideoToLibrary` (new)

Request:

```
{
  resourceId: string,
  lectureId: string,
  libraryId: string,          // requested; registry-resolved server-side
  videoId: string,            // bare GUID
  replaceVideo?: boolean,     // explicit intent to rebind an existing Video ID
  receipt: {                  // from validateBunnyVideoAssociation
    resourceId, lectureId, libraryId, videoId, expiresAt, signature
  }
}
```

Authorization: Doctor or Admin with active `admin_permissions.admin_content`
(the same authority `firestore.rules` grants via `canManageContent`). No new
role or permission key was introduced; a Dashboard login alone is not enough.

Response: `{status:"associated"|"already_associated", resourceId, lectureId,
libraryId, videoId}` — nothing else, no secrets.

Errors: `unauthenticated` · `permission-denied` (authority or receipt) ·
`invalid-argument` (shape, Video ID, unknown/inactive/incomplete library) ·
`failed-precondition` (lecture/subject mismatch, deleted doc, video change
without `replaceVideo`) · `not-found`.

## 4. Lifecycle guarantee (A5)

`bunny_video_id` and `bunny_library_id` are **server-owned** for video rows:

- Clients create a row with neither value → the row is **pending** and cannot
  play (issuance requires a matching `bunny_video_id`, and the cutover gate
  refuses to resolve a library for a post-cutover row without an association).
- The server callable writes both values only after verification.
- A failed/absent verification therefore leaves an unplayable row — it is never
  silently downgraded to a legacy row, and the default-library fallback is
  never applied to it.

Legacy compatibility is preserved by an explicit creation-time cutover
(`BUNNY_ASSOCIATION_CUTOVER`, default `2026-11-13T00:00:00Z`): genuinely older
rows keep the default-library fallback; anything created at/after the cutover
must carry a verified association. `created_at` is server-assigned
(`serverTimestamp`) and Rules require it to equal `request.time`, so a client
cannot forge a "legacy" timestamp (neither by omitting the field nor by
back-dating it).

## 5. Idempotency & retries

The transaction rewrites the same values and re-derives `first_video`; a
repeated identical request returns `already_associated` instead of failing or
duplicating. Dashboard/mobile retries after a partial failure are therefore
safe.

## 6. Tests

| Suite | Assertions | Scope |
|---|---|---|
| `functions/test/bunny_library_association.test.js` (pure) | 37 | decision table, cutover gate, receipt binding/expiry/tamper/replay, write-field shape |
| `functions/test/bunny_association_flow.test.js` (emulator) | 19 logged checks + ~30 asserts | auth matrix, wrong resource/lecture/subject/video/library, unknown/inactive/incomplete, expired/tampered/foreign receipts, persistence, idempotency, explicit replacement, non-video, deleted, pending-cannot-play, legacy-still-plays |
| `security-tests/adr010_association_rules.test.js` | 15 | rules immutability + permitted updates + forged legacy stamp |

Not covered: a real Stream metadata call (no production credential; receipts
are signed with the fixture secret instead). Recorded as a limitation.

## 7. Agent 2 verification and repair

The handover audit re-ran the suites and found one write path that the earlier
report described as migrated but which still wrote the association directly:

- `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`
  `publishQuickLecture` wrote `bunny_library_id` in the resource create map.
  With the new Rules that create is denied (`create` requires a null
  association), so Quick Upload would have failed outright.

Repair (client):

- The create map now writes only `bunny_video_id` (a pointer on a pending row);
  `bunny_library_id` is not sent.
- After the resource and the `first_video` pointer are written, the function
  calls `BunnyAssociationGateway.associate(...)` (production call site injects
  `CallableBunnyAssociationGateway(FirebaseFunctions.instance)`).
- Ordering is deliberate: the server callable runs last, so its trusted
  recomputation of `first_video` (with the verified library) wins over the
  client pointer write.
- A gateway failure propagates to the author; the row stays pending and
  unplayable. It is never downgraded to a legacy default-library row.
- PDF-only quick upload never calls the gateway.

Coverage added in `dashboard/test/bunny_library_persistence_test.dart`:
client writes no association; gateway receives the default library; a
server-confirmed association lands on the row; a rejected association leaves
the row pending; PDF never calls the gateway.

The emulator suite also gained the missing **subject mismatch** case (A10 #7):
a resource whose `subject_id` disagrees with the lecture's is rejected with
`failed-precondition`.

## 8. Verified results (Agent 2)

| Check | Result |
|---|---|
| `cd functions && npm run build` | PASS (exit 0) |
| `npm run test:pure` | PASS (exit 0) |
| `npm test` (51 emulator/pure files) | PASS — 51/51 |
| `security-tests/adr010_association_rules.test.js` | PASS — 14 assertions |
| Dashboard `flutter analyze` | PASS — no issues |
| Dashboard ADR-010 + authoring tests (6 files) | PASS — 71 tests |
| Flutter `flutter analyze` | PASS — no issues |
| Flutter `video_resource_library_test.dart` | PASS — 6 tests |

## 9. Residual note (not a bypass)

`lectures.first_video` is still written by Dashboard/mobile clients as a
pointer (with the library value they staged). That value is **not** used to
select credentials: issuance re-reads `lecture_resources`, re-resolves the
library from the stored row, and refuses a pending row. On every successful
association the callable recomputes `first_video` from trusted rows, replacing
the client value. No client-written pointer can authorize playback.

