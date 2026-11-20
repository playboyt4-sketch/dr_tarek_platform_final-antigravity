# ADR-010 — Migration Tool Hardening (Mission 2, Workstream B)

Files: `functions/src/core/video/bunny_library_migration.ts` (pure),
`functions/src/scripts/backfill_bunny_library_id.ts` (CLI),
`functions/test/bunny_library_migration.test.js` (37 assertions).

## 1. Write capability removed, not merely disabled

The previous build had an `--apply` write loop with `lastUpdateTime` preconditions.
It has been **deleted**. The tool now has no Firestore write call at all, so no flag,
environment variable or code path can write production data.

`resolveBunnyLibraryBackfillMode({apply})` returns `blocked_apply` for `--apply`, and the
CLI checks it **before** reading the mapping file or opening any project connection.

Observed behaviour:

| Invocation | Result |
|---|---|
| `node lib/scripts/backfill_bunny_library_id.js` | exit 1, `--mapping <path> is required …` (no connection) |
| `node lib/scripts/backfill_bunny_library_id.js --mapping package.json --apply` | exit 3, `Refused: apply mode is disabled in this build …` (no connection, no file read) |

## 2. Default mode

Dry run is the only mode. The run prints a structured report and writes two local JSON
artifacts under `reports/adr010/migration/` (created only when the command is actually
run against a project; nothing was run here):

- `<stamp>-plan.json` — every decision + summary + conflicts + unresolved mappings.
- `<stamp>-backup.json` — `createdAt`, one entry per planned write with
  `previousLibraryId`, `nextLibraryId`, `lectureId`, `subjectId`, `updateTime`, plus a
  `rollback` instruction string.

## 3. Input validation added

| Check | Behaviour |
|---|---|
| Unexpected mapping field (typo e.g. `libaryId`) | rejected by name |
| Empty `videoId` / `libraryId` | rejected |
| Unknown library id | rejected (registry) |
| Known-but-inactive library (`775315`) | rejected unless `BUNNY_ACTIVE_LIBRARY_IDS` lists it |
| Duplicate `videoId` | rejected (same or different library, distinct messages) |
| Duplicate `resourceId` | rejected |
| Empty `lectureId` / `subjectId` when supplied | rejected |
| Non-array mapping file | rejected |

No inference from subject, grade, title or ordering anywhere.

## 4. Mapping integrity (planner)

For every snapshot row the planner records exactly one decision:

| Action | Meaning |
|---|---|
| `set` | mapped, currently null, ready for a future authorized write |
| `unchanged` | already correct (idempotent) |
| `skipped_no_video_id` | placeholder row — never touched (7 exist today) |
| `skipped_not_video` | non-video resource — never written |
| `conflict` | unmapped video, mapping scoped to another resource, lecture/subject mismatch or missing identity, stored library disagreeing with the mapping |

Additional safeguards:

- A mapping entry scoped with `resourceId` may only apply to that document.
- `lectureId` / `subjectId` cross-checks refuse when the row cannot prove them.
- An entry pointing at a resource missing from the snapshot appears in
  `unresolvedMappings` (never silently ignored).
- `plan.writable` is true only with zero mapping errors, zero conflicts and zero
  unresolved mappings.

## 5. Concurrency design (unit-tested with mocks, no writes)

`evaluateBunnyLibraryBackfillWrite(decision, row, {writesEnabled, expectedUpdateTime})`:

| Case | Verdict |
|---|---|
| `writesEnabled` not explicitly `true` | `writes_disabled` |
| decision is not `set` | `not_a_write` |
| snapshot row missing | `resource_missing` |
| `expectedUpdateTime` differs from the row's | `stale_snapshot` |
| explicit enablement + matching timestamp | `ok` |

There is no ambient default that enables writes: a future executor must pass
`writesEnabled: true` deliberately, and the pure planner alone can never write.

## 6. Reporting fields

`resourcesInspected`, `plannedUpdates`, `unchanged`, `withoutVideoId`, `notVideo`,
`conflicts`, `invalidMappings`, `missingResources`, `manualReview`, `writable`,
`planPath`, `backupPath`, `backupEntries`, plus per-resource reason strings.

## 7. What is still NOT possible

- No production (or emulator) write was executed. `--apply` cannot work in this build.
- The 7 placeholder rows and the duplicate-video pair remain untouched.
- A real run still needs a verified mapping file and a read credential; none was used
  in this mission (no project read either).
