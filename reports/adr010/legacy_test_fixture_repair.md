# ADR-010 — Legacy Test Fixture Repair (Mission 4, Workstream B)

Status: **DONE** — both suites now pass in the emulator; no production
validation, security check or expected verdict was changed.

## 1. Investigation

| Suite | Failure | Root cause |
|---|---|---|
| `test/protected_content.test.js` | `videoId must be a bare Bunny Video ID (GUID) — URLs are not accepted` at the first video case | fixtures used `pcont-vid-V` etc., which are not GUIDs; the VIDEO-ID-ONLY guard exists in `HEAD` and correctly rejects them |
| `test/playback_session.test.js` | same error with `pbs-vid-A` | same fixture-format problem |

Both files are unmodified at `HEAD`; the guard is unmodified too. The failures
were purely fixture format, exactly as reported after Mission 3.

## 2. Repair (fixtures only)

Deterministic GUID-shaped replacements, every dependent reference updated in
the same pass:

| Old fixture id | New value |
|---|---|
| `pcont-vid-V` | `11111111-aaaa-4aaa-8aaa-000000000001` |
| `pcont-vid-Deny` | `11111111-aaaa-4aaa-8aaa-000000000002` |
| `pcont-vid-NG` | `11111111-aaaa-4aaa-8aaa-000000000003` |
| `pcont-vid-G` | `11111111-aaaa-4aaa-8aaa-000000000004` |
| `pcont-vid-M` | `11111111-aaaa-4aaa-8aaa-000000000005` |
| `pcont-vid-P` | `11111111-aaaa-4aaa-8aaa-000000000006` |
| `pcont-vid-W0` | `11111111-aaaa-4aaa-8aaa-000000000007` |
| `pcont-vid-W2` | `11111111-aaaa-4aaa-8aaa-000000000008` |
| `pbs-vid-A` | `22222222-bbbb-4bbb-8bbb-000000000001` |

Zero occurrences of the old ids remain (`grep` count = 0 in both files).

## 3. Two further fixture defects surfaced after the format fix

Neither is a weakening; both made the assertions test what they claim:

1. `protected_content` "no-preview lecture denies Guest" received
   `resource-exhausted` because the earlier cases in the same file opened the
   24h rolling window for `STUDENT`, and the window check runs before the
   preview/entitlement verdict. Fix: delete `video_watch_windows/{STUDENT}`
   before that assertion (state isolation, like `resetWindow` in the other
   suites).
2. `protected_content` "unknown video is not Full" used the literal
   `pcont-nope`, which the format guard rejects as `invalid-argument` before the
   lookup, so the asserted `not-found` could never be observed. Fix: use a
   GUID-shaped unknown id (`99999999-aaaa-4aaa-8aaa-000000000099`).

No expected authorization outcome was changed; only fixture identity/state.

## 4. Results

| Command | Result |
|---|---|
| `firebase emulators:exec --project demo-tarek-platform --only auth,firestore,functions "node functions/test/protected_content.test.js"` | **PASS** — exit 0, `ok 18 - Failures never default to Full`, `all 20 scenarios verified` |
| same with `playback_session.test.js` | **PASS** — exit 0 |
| combined run with the new association suite | `bunny_association_flow` PASS, `protected_content` PASS, `playback_session` PASS, `progress_percentage` PASS |

No pure suite depends on these fixtures (the pure suites use their own
constants), so nothing else needed re-running for this workstream.

## 5. Agent 2 independent re-run

Reproduced and verified from the current working tree (no changes were needed
to this workstream):

| Command | Result |
|---|---|
| `npx firebase emulators:exec --project demo-tarek-platform --only auth,firestore,functions "node test/protected_content.test.js"` | **PASS**, exit 0, `all 20 scenarios verified` |
| same with `playback_session.test.js` | **PASS**, exit 0, `all 18 scenarios verified` |
| `npm test` (both files inside the 51-file suite) | **PASS**, 51/51 |

Baseline evidence (`git show HEAD:…`) confirms the historical fixture values
(`pcont-vid-V` … and `pbs-vid-A`) were not GUID-shaped, and the production
VIDEO-ID-ONLY guard has no diff: the guard was not weakened, only the fixtures
changed.

