# ADR-010 — Mission 4 Security Review

Scope: server-verified association, rules enforcement, playback gate, client
integration, fixture repair, aggregation investigation. No production access,
no deployment, no secret change.

## 1. Client authority (removed)

- Dashboard no longer writes `bunny_library_id` **or** `bunny_video_id` for
  video rows: create/update batches write `null` and then call
  `validateBunnyVideoAssociation` → `associateBunnyVideoToLibrary`
  (`dashboard/lib/features/students/data/bunny_association_gateway.dart`).
- Mobile admin authoring drops any client library id, defers a Video ID change
  on a verified row to the callable, and calls the same two callables after
  save.
- **Agent 2 audit correction**: the Quick Upload path
  (`quick_upload_modal.dart`) still wrote `bunny_library_id` directly in its
  create map. Under the new Rules that create is denied, so the path was
  broken. Fixed: it now writes only the Video-ID pointer and calls the server
  gateway after the row/pointer write; a failure leaves a pending, unplayable
  row. Four Dashboard tests cover it.
- Rules make this structural, not just conventional: clients cannot create,
  change or remove `bunny_library_id`, cannot change `resource_type`, and
  cannot swap the Video ID of a verified row (proved by 15 rules assertions).
- `created_at` must equal `request.time` on create. The cutover gate uses that
  stamp to classify legacy vs pending, so a back-dated timestamp would let a
  client forge a "legacy" row and bypass verification. Back-dating is now
  denied; every authoring path writes `FieldValue.serverTimestamp()`.

## 2. Server authority

- `requireContentManager` (pre-existing helper, reused): Doctor or Admin with
  active `admin_permissions.admin_content` — exactly `canManageContent` in
  Rules. No new role, no new permission key, and Dashboard access alone is
  insufficient.
- Library resolution goes through the registry: unknown / inactive (`775315`) /
  incomplete configuration all fail closed; there is no fallback to another
  library.
- The receipt is HMAC-SHA256 over a domain-separated payload binding
  `(resourceId, lectureId, libraryId, videoId, expiresAt)`, verified in
  constant time, expiry enforced. Cross-resource, cross-lecture, cross-library,
  cross-video, tampered, foreign-secret and missing receipts are rejected —
  all exercised in the emulator.
- The write happens in a transaction that re-reads the resource and lecture, so
  a concurrent edit cannot slip a different Video ID past the checks.
- Response shape is closed: `{status, resourceId, lectureId, libraryId,
  videoId}`. No key, token, template, pull zone or signed URL is returned.

## 3. Playback gates

- `generateBunnySignedUrl`: after resolving the resource, a post-cutover row
  with no `bunny_library_id` is refused (`failed-precondition`, “pending
  verification”). Pre-cutover legacy rows keep the documented default-library
  fallback. Proved in the emulator: pending row denied, legacy row proceeds to
  the (unchanged) entitlement checks.
- `resolveBestEffortBunnyLibrary` (display media) applies the same gate, so a
  pending row cannot borrow the default library's zone even for a poster.
- `first_video` is only a pointer: issuance always re-reads the resource and
  re-resolves the library from the trusted record, so a client-written pointer
  can never select credentials. The association callable additionally recomputes
  `first_video` from trusted rows.

## 4. Library 775315

Still inactive: not in `BUNNY_ACTIVE_LIBRARY_IDS`, not selectable in the
catalog, rejected by validation (`inactive_library`) and by association
(`inactive_library`), and refused by issuance. No Bunny configuration touched.

## 5. Regression posture

- Entitlement, device binding, takeover, quality matrix, preview limits,
  rolling window, per-lecture deny, Feature Matrix: untouched (the same
  assertions still pass in `protected_content` / `playback_session`).
- PDF / external-link rows: never associated; creation and update paths
  unchanged in behaviour (rules test 12).
- Resource ordering and soft-delete semantics: unchanged.
- `progress_percentage`: aggregation untouched; only the fixture now writes
  `status: "published"`, which is what the code counts.

## 6. Pre-existing issues observed, NOT changed

1. Dashboard UI tests `subject_details_test` (header centering) and
   `subject_grade_context_sync_test` fail on unmodified UI code — unrelated to
   this mission, no ADR-010 file appears in their stacks.
2. `775315` pull zone still serves unsigned HLS.
3. Archived / `is_deleted` lectures remain issuable (out of scope).
4. Duplicate `6ffb23ad…` Video ID across two resources.
5. Seven placeholder video resources with empty `bunny_video_id`.
6. `BUNNY_STREAM_API_KEY` is still a plain env var rather than Secret Manager.

## 7. Deployment ordering (important)

Rules now deny client association writes while the callable is the only writer.
If Rules were deployed without the Functions, newly created video rows would
stay **pending (unplayable)** — fail-closed, but a functional stop. Correct
order: deploy Functions first, then Rules, then verify with the Dashboard.

## 8. Verdict

No security regression; the association is now server-verified end to end
(client → validation receipt → transactional write → playback gate). Remaining
items are deployment ordering and the pre-existing issues listed above.

## 9. Agent 2 independent verification

| Check | Result |
|---|---|
| `cd functions && npm run build` | PASS |
| `npm run test:pure` | PASS |
| `npm test` (51 files) | PASS — 51/51 |
| `security-tests/adr010_association_rules.test.js` | PASS — 15 assertions |
| `security-tests` full suite (`rules.test.js` + ADR-010) | PASS |
| Dashboard `flutter analyze` | PASS |
| Dashboard ADR-010/authoring tests (6 files) | PASS — 71 tests |
| Flutter `flutter analyze` | PASS |
| Flutter `video_resource_library_test.dart` | PASS — 6 tests |
| `subject_details_test` / `subject_grade_context_sync_test` | FAIL — pre-existing text-alignment assertions in unmodified `subject_details_screen.dart`; unrelated to ADR-010 |

Additional emulator coverage added: subject mismatch between the resource and
its lecture is rejected with `failed-precondition`.

