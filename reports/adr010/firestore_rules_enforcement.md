# ADR-010 — Firestore Rules Enforcement (Mission 4, A6)

Status: **DONE** — implemented and verified in the rules emulator (14
assertions). Rules were NOT deployed (prohibited).

## 1. Change (only `lecture_resources`)

Before: `allow create, update: if canManageContent();` — any content manager
could write any field, including the association.

After:

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

Reads, deletion (`false`) and every other collection are untouched; no access
was broadened. The Admin SDK callable bypasses these rules by design, which is
why the trusted write path can persist the association.

Rationale per clause:

- **create: no `bunny_library_id`** — a client can never author the
  authorization-relevant value. New rows are pending until the callable runs.
- **create: `created_at` equals `request.time`** — the issuance gate
  distinguishes legacy from pending by server-assigned creation time, so the
  client must not be able to forge an old stamp. Every authoring path writes
  `FieldValue.serverTimestamp()`, which Rules resolve to `request.time`; a
  concrete/back-dated timestamp is denied.
- **update: library id unchanged** — cannot add, change or remove it.
- **update: `resource_type` unchanged** — prevents turning a PDF row into a
  video row with a pointer, and prevents demoting a verified video row.
- **update: `bunny_video_id` unchanged OR the row is unassociated** — a VERIFIED
  row's pointer can only be swapped by the server callable (which re-verifies);
  a pending/legacy row may still be authored by mobile/Dashboard clients, and
  doing so leaves it pending (unplayable) until verification.

## 2. Proof (emulator, `security-tests/adr010_association_rules.test.js`)

Passing assertions:

1. content manager creates a pending video row (no association) — allowed
2. create WITH `bunny_library_id` — denied
3. create WITHOUT `created_at` — denied
3b. create with a forged/back-dated `created_at` — denied (`!= request.time`)
4. admin without `admin_content` — denied
5. add `bunny_library_id` to a pending row — denied
6. change a stored `bunny_library_id` — denied
7. remove a stored `bunny_library_id` — denied
8. swap the Video ID under a verified association — denied
9. change `resource_type` — denied
10. unrelated update on a verified row — allowed
11. pending row may still have its Video ID authored — allowed
12. PDF row update — allowed
13. trusted server (Admin SDK) persists the association — allowed
14. staff read unchanged — allowed

Command:

```
cd security-tests
firebase emulators:exec --only firestore --project dr-tarek-platform-rules-test \
  "node adr010_association_rules.test.js"
```

Result: exit 0, `adr010_association_rules: 15 assertions passed`.

## 3. Client consequences (handled, not ignored)

- **Dashboard**: no longer writes either field; it calls the callable
  (`bunny_association_gateway.dart`) after its batch, which is what makes a
  video row playable.
- **Mobile admin authoring**: `admin_content_remote_data_source_impl` drops any
  client library id, defers a Video ID change on a verified row to the callable,
  and calls the callable after save.
- Deploying these rules without the callable would leave new video rows
  pending (unplayable). That is the intended fail-closed direction, but the
  Functions deployment must ship first — recorded in the final report.

## 4. Rule-test script

`security-tests/package.json` now runs both suites:
`node rules.test.js && node adr010_association_rules.test.js`.

## 5. Agent 2 verification (independent re-run)

Command:

```
cd security-tests
firebase emulators:exec --only firestore --project dr-tarek-platform-rules-test \
  "node adr010_association_rules.test.js"
```

Result: **PASS**, exit 0, `adr010_association_rules: 15 assertions passed`
(the `PERMISSION_DENIED` lines in the log are the expected `assertFails`
outcomes). The full `security-tests` suite (`npm test`, both files) also
passes with the storage emulator enabled:
`Firestore and Storage rules tests passed` + `15 assertions passed`.

One client write path was found and fixed during this verification:
`publishQuickLecture` still created the video row with `bunny_library_id`,
which this rule now denies. It no longer writes the association; it creates a
pending row and calls the server gateway afterwards
(see `server_side_verified_association.md` §7). Four Dashboard tests now prove
that behaviour.

Rules were not deployed and no production project was contacted.

