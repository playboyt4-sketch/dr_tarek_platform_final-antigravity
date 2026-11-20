# ADR-010 — `progress_percentage` Root Cause (Mission 4, Workstream C)

Status: **DONE** — two distinct failure layers were proven and fixed. No
aggregation logic, query, threshold or formula was changed.

## 1. The trigger under test

`recalculateSubjectProgress` (`onDocumentUpdated("lecture_progress/{progressId}")`)
fires only on a completion transition, then calls
`calculateAndSetSubjectProgress(db, studentId, lectureId)` (both in
`functions/src/index.ts`):

1. read `lectures/{lectureId}` → `section_id` (throws when missing),
2. read `subject_sections/{sectionId}` → `subject_id`,
3. list **all** `subject_sections` of that subject,
4. for every section, list `lectures` where `section_id == …` and keep only
   `is_deleted != true && status === "published"`,
5. count completed `lecture_progress` rows for the student among those ids
   (batched `in` queries of 30),
6. write `subject_progress_summary/{studentId}_{subjectId}`.

The trigger function has **zero diff at `HEAD`** (`git diff -U0` contains no
`calculateAndSetSubjectProgress`/`recalculateSubjectProgress` hunk), so the
aggregation itself was never modified by ADR-010 work.

## 2. Failure layer 1 — historical `total_lectures = 0` (fixture)

`functions/test/progress_percentage.test.js` at `HEAD` seeds 50 lectures with
**only** `section_id` and `title`:

```js
batch.set(db.collection("lectures").doc(`lec_prog_${i}`), {
  section_id: sectionId,
  title: `Lecture ${i}`,
});
```

Observed historically: the summary doc *was* created with
`total_lectures = 0`. The trigger ran; step 4 dropped every lecture because
`status` was `undefined`, while production lectures always carry `status`
(`draft`/`published`).

Classification: **test fixture inconsistency**. The aggregation was correct.

Fix (fixtures only):

```js
batch.set(db.collection("lectures").doc(`lec_prog_${i}`), {
  section_id: sectionId,
  subject_id: subjectId,
  title: `Lecture ${i}`,
  status: "published",   // the counted state
  is_deleted: false,
});
```

## 3. Failure layer 2 — standalone run `Summary doc should be created`

After the fixture fix, the standalone command still failed:

```
firebase emulators:exec --project demo-tarek-platform --only auth,firestore,functions \
  "node functions/test/progress_percentage.test.js"
→ Test failed: Error: Summary doc should be created   (exit 1)
```

The trigger log showed `recalculateSubjectProgress` executing **after** the
test had already given up. A deterministic diagnostic (same fixture, 120 s poll,
no assertions changed) measured:

```
[diag] writing completion at t=1845ms
[diag] summary appeared at t=23737ms
{ total_lectures: 50, completed_lectures: 1, completion_percentage: 2 }
```

Root cause: `firebase emulators:exec` starts the test command before Cloud
Functions triggers finish registering; cold trigger delivery took **~22 s**
while the test polled for **15 s**. The event was delivered, and the aggregation
computed the correct 50/1/2.

Classification: **asynchronous trigger timing** (test harness budget), not an
aggregation defect. The full `npm test` suite did not expose it because
`test/wait_for_triggers.js` runs first and warms delivery.

Fix (harness only): poll for up to **120 s**, matching the documented
trigger-readiness budget in `test/wait_for_triggers.js`. Assertions
(`50 / 1 / 2`) are unchanged; the test was not weakened or skipped.

## 4. Baseline comparison evidence (read-only)

No `git reset`, `stash`, checkout or worktree was used.

- `git show HEAD:functions/test/progress_percentage.test.js` → the baseline
  fixture is exactly the `section_id` + `title` version above (no `status`),
  so `total_lectures = 0` is reproducible from committed content.
- `git diff -U0 -- functions/src/index.ts` → no hunk touches the aggregation
  trigger or `calculateAndSetSubjectProgress`.
- Therefore the historical failure predates Mission 4 (fixture), and the
  standalone failure is an environment/timing issue (delivery budget).

## 5. Verification

| Command | Result |
|---|---|
| standalone `progress_percentage.test.js` (emulator, 120 s poll) | **PASS**, exit 0, `PASS - completion_percentage verified` |
| `npm test` (file inside the 51-file suite) | **PASS**, 51/51 |

## 6. Recommended follow-up (not implemented)

Two real aggregation observations for a future ticket (business rules, out of
scope):

1. It counts lectures across **all** sections of the subject, including
   sections the student cannot see, which can deflate completion percentage.
2. It resolves the subject from the lecture's section on every completion, so
   a lecture moved between sections changes historical denominators.
