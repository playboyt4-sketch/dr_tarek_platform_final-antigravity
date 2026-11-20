# Mission 6 — Security Fix: Immutable `created_at` on `lecture_resources`

**Mission type:** narrowly scoped security remediation (Firestore Rules + focused tests)
**Repository:** `D:\antigravity\dr_tarek_platform_final`
**Baseline HEAD:** `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`
**Date:** 2026-11-13 (UTC)

---

## A. Initial state (before changes)

| Item | Value |
|---|---|
| Repository root | `D:/antigravity/dr_tarek_platform_final` |
| `git rev-parse HEAD` | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| `git status --short` | 28 modified tracked files + 24 untracked entries (52 total), **0 staged** |
| Mission 4 work present | Yes — ADR-010 functions, dashboard, mobile, rules, security tests |
| Mission 5 report present | Yes — `reports/adr010/mission_5_pre_deployment_audit.md` (untracked `reports/`) |

Files already modified before Mission 6 (unchanged by this mission unless listed in C):
`.github/workflows/ci.yml`, `firestore.rules`, `functions/package.json`,
`functions/src/index.ts`, `functions/test/{playback_session,progress_percentage,protected_content,run_all}.js`,
`lib/features/content_authoring/.../admin_content_remote_data_source_impl.dart`,
`lib/features/subject_navigation/.../subject_learning_entities.dart`,
`lib/features/video_streaming/...` (3 files), `security-tests/{package.json,rules.test.js}`,
13 dashboard files, plus 24 untracked ADR-010 files/directories.

The exact update rule at the start of the mission (`firestore.rules:317-324`) was:

```
allow update: if canManageContent()
  && request.resource.data.get('bunny_library_id', null) == resource.data.get('bunny_library_id', null)
  && request.resource.data.get('resource_type', '') == resource.data.get('resource_type', '')
  && (
    request.resource.data.get('bunny_video_id', null) == resource.data.get('bunny_video_id', null)
    || (resource.data.get('bunny_library_id', null) == null
      && request.resource.data.get('bunny_library_id', null) == null)
  );
```

---

## B. Vulnerability reproduction (independent, before the fix)

- **Rule location:** `firestore.rules:317-324` (update branch of
  `match /lecture_resources/{resourceId}`).
- **Root cause:** `created_at` is the only legacy/pending discriminator used by
  the issuance gate (`bunny_library_association.ts:173-179`,
  `index.ts:4537-4548`). The create rule requires
  `created_at == request.time` (`firestore.rules:314-316`), but the update rule
  placed no constraint on it.
- **Method:** `@firebase/rules-unit-testing` against the local Firestore
  emulator, loading the repository's actual `firestore.rules`. Probe script kept
  **outside** the repository at `D:\Temp\opencode\probe_backdate.js`. No
  production access, no credentials, no playback URLs.

Command:

```
$env:NODE_PATH="...\security-tests\node_modules"
npx firebase emulators:exec --only firestore --project audit-backdate-probe \
  "node D:\Temp\opencode\probe_backdate.js"
```

Observed output **before** the fix:

```
STEP1 create pending row: ALLOWED (expected)
STEP2 backdate created_at to 2020: ALLOWED  <-- BYPASS
STEP3 clear created_at to null: ALLOWED  <-- BYPASS
FINAL created_at: null library: undefined
```

Exit code `0`. The vulnerability is reproduced: a content manager could both
backdate and nullify `created_at` on an existing pending row.

---

## C. Implementation

### Files changed

| File | Change |
|---|---|
| `firestore.rules` | Added one authorization condition to the `lecture_resources` update rule (plus a 3-line explanatory comment). No other rule, collection, or branch touched. |
| `security-tests/adr010_association_rules.test.js` | Added focused regression tests A–E and an explicit Test F; imported `deleteField`; extended the header comment. No test removed or weakened. |
| `reports/adr010/mission_6_security_fix.md` | This report (new). |

### Exact condition added

`firestore.rules:317-329` now reads:

```
allow update: if canManageContent()
  && request.resource.data.get('bunny_library_id', null) == resource.data.get('bunny_library_id', null)
  && request.resource.data.get('resource_type', '') == resource.data.get('resource_type', '')
  // `created_at` is the issuance gate's only legacy/pending discriminator:
  // it must be immutable after creation, or a pending row could be
  // backdated/nulled into the legacy default-library fallback.
  && request.resource.data.get('created_at', null) == resource.data.get('created_at', null)
  && (
    request.resource.data.get('bunny_video_id', null) == resource.data.get('bunny_video_id', null)
    || (resource.data.get('bunny_library_id', null) == null
      && request.resource.data.get('bunny_library_id', null) == null)
  );
```

### Why it closes the bypass

In an `update`, `request.resource.data` is the complete post-write document and
`resource.data` is the stored document.

- **Backdating** → new timestamp ≠ stored timestamp → condition false → deny.
- **Nullification** → `get('created_at', null)` returns `null` ≠ stored
  timestamp → deny.
- **`deleteField()`** → the field is absent post-write, so `get(..., null)`
  returns `null` ≠ stored timestamp → deny.
- **Unchanged timestamp** → both sides are the same `Timestamp` value → the
  condition is true and the remaining existing conditions decide the write.
- **Legacy rows with no `created_at`** → both sides are `null` → the condition
  is true, preserving the documented legacy behavior.
- The condition is evaluated **in addition to** every pre-existing condition;
  no existing condition was removed, reordered in a weakening way, or relaxed.

The Admin SDK (association callable) bypasses Rules by design, so the server can
still write `bunny_video_id`/`bunny_library_id`; the callable never writes
`created_at`.

### Compatibility check

`created_at` was already mandatory on create and every legitimate authoring path
writes `FieldValue.serverTimestamp()`. No production write path updates
`created_at` after creation, so this condition does not break any legitimate
flow. This was verified by the pre-existing create tests and by the full
Firestore + Storage suite.

---

## D. Regression tests

All tests exercise the Firestore Emulator through
`@firebase/rules-unit-testing`; none inspect rule text.

| Test | Assertion name | Expected | Actual | Result |
|---|---|---|---|---|
| **A — Backdating** | `client cannot BACKDATE created_at on an existing row` | DENIED | DENIED (`assertFails` passed) | **PASS** |
| **B — Nullification** | `client cannot NULLIFY created_at` | DENIED | DENIED | **PASS** |
| **C — Field deletion** | `client cannot DELETE created_at with deleteField()` | DENIED | DENIED | **PASS** |
| **D — Unchanged timestamp** | `update that leaves created_at unchanged is still allowed` | ALLOWED (existing rules) | ALLOWED | **PASS** |
| **E — Unauthorized user** | `admin without admin_content cannot update resources` | DENIED | DENIED | **PASS** |
| **F — Creation** | `content manager can still create with serverTimestamp()` (plus the pre-existing create test) | ALLOWED | ALLOWED | **PASS** |

Additional pre-existing assertions in the same file still pass, including:
create without `bunny_library_id`, deny create with a library id, deny create
without `created_at`, deny forged-old `created_at` on create, association
immutability on update, verified-row Video ID immutability, `resource_type`
immutability, unrelated updates on verified/PDF/pending rows, trusted server
write, and staff reads.

The suite grew from **15** to **21** assertions.

---

## E. Validation results

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `npx firebase emulators:exec --only firestore --project dr-tarek-platform-rules-test "node security-tests/adr010_association_rules.test.js"` | **0** | `adr010_association_rules: 21 assertions passed` |
| 2 | `npx firebase emulators:exec --only firestore,storage --project dr-tarek-platform-rules-test "node security-tests/rules.test.js && node security-tests/adr010_association_rules.test.js"` | **0** | `Firestore and Storage rules tests passed.` + `adr010_association_rules: 21 assertions passed` |
| 3 | `cd functions && npm run test:pure` | **0** | registry 30, migration 37, playback 33, validation 26, association 37 assertions |
| 4 | Probe rerun after fix (`D:\Temp\opencode\probe_backdate.js`) | **0** | `STEP2 ... DENIED`, `STEP3 ... DENIED`; `FINAL created_at: Timestamp {...}` |
| 5 | `git diff --check` | **0** | no whitespace errors (CRLF advisories only) |

Logs: `D:\Temp\opencode\mission6_adr010_rules.log`,
`mission6_full_security.log`, `mission6_test_pure.log`.

**Emulator log note:** denied update attempts emit
`PERMISSION_DENIED ... evaluation error at L317:24` (the `canManageContent()`
call site) for both the new and the pre-existing denied-update tests. This
pattern pre-dates Mission 6 (the Mission 5 logs show the same artifact at the
then-current line) and is fail-closed. All permitted updates succeed, and the
probe confirms the deny is specifically caused by the `created_at` mismatch.

No failures occurred. No test was skipped or claimed without execution.

---

## F. Git integrity

| Item | Value |
|---|---|
| Final `git rev-parse HEAD` | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged) |
| Final `git status --short` | **identical set** to the initial state: 28 modified tracked + 24 untracked (52 entries) |
| Staged files | **0** |
| Commits / pushes | none |
| Deployments | none |
| Production data/config | untouched |
| Existing modifications preserved | yes — only `firestore.rules` gained the new condition; the untracked ADR-010 test file gained the new tests; all other files untouched |
| Line endings | `firestore.rules` remains 617 CRLF / 0 LF-only; the ADR-010 test file remains LF-only (250 LF / 0 CRLF), as before |
| Generated artifacts | `firestore-debug.log` created by the emulator runs was deleted after validation; no other generated file remains |
| New files | only `reports/adr010/mission_6_security_fix.md` (inside the already-untracked `reports/`) |

No `git reset`, `checkout`, `clean`, `rebase`, `stash`, staging, commit, push,
or deploy was executed.

---

## G. Remaining risks (documented, not fixed)

1. **Production is still vulnerable until Rules are deployed.** This mission
   changed the local rule file only. The bypass remains live in any environment
   running the previous Rules.
2. **Functions-first deployment window (Mission 5 H-3).** The playback gate
   trusts a non-null stored `bunny_library_id`
   (`bunny_library_association.ts:194-195`). If Functions are deployed before
   the fixed Rules, a content manager can still write `bunny_library_id`
   directly under the old Rules and persist an unverified association. Deploy
   the fixed Rules first (or atomically).
3. **`bunny_video_id` remains client-authorable on pending/legacy rows by
   design** (`firestore.rules:324-328`). This is the documented pointer-authoring
   flow, not a regression; the association callable re-verifies before a
   library is stored.
4. **The other Mission 5 findings remain open**, including the unmet ADR-010
   implementation gate (no backfill executor, 3 resources in inactive `775315`,
   7 resources without usable Video IDs), the missing Dashboard library picker,
   the elapsed default cutover, plain-`.env` Bunny API key, lint debt, and the
   unexecuted CI job. None was in Mission 6 scope.
5. **No `created_at` immutability test exists for server/Admin SDK writes**
   (not applicable — Admin SDK bypasses Rules) or for other collections that may
   use similar legacy/pending timestamps. Out of scope.
6. **Emulator denial logging quirk** (`evaluation error at L317:24` for denied
   updates) is cosmetic and fail-closed, but it can obscure the real deny reason
   in logs; a future test-harness improvement could surface the failing
   condition.

---

## Completion statement

- `created_at` update bypass: **closed and independently reproduced/verified**.
- Backdating / nullification / `deleteField()`: **DENIED**.
- Unchanged-timestamp updates: **still allowed**.
- Server-timestamp creation: **still allowed**.
- Focused tests: **21/21 passed**.
- Full Firestore + Storage security suite: **passed**.
- Unrelated source changes: **none**.
- Deployment / commit / push / staging: **none**.

**MISSION 6 — COMPLETE.**
