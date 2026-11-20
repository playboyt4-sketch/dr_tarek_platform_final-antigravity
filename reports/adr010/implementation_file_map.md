# ADR-010 — Implementation File Map

Every file below was changed by this task only. Pre-existing working-tree
modifications (dashboard application/student screens, `functions/package.json`,
`functions/src/index.ts`, `functions/test/run_all.js`, `live_student.dart`, …)
were present before this work and were **not** reverted or reformatted.

## Backend (new)

### `functions/src/core/video/bunny_library_registry.ts` (NEW, pure)
- `DEFAULT_BUNNY_LIBRARY_ID = "736742"`.
- `BUNNY_LIBRARIES`: default entry (existing env var names, `isDefault: true`) and
  `775315` (its own `BUNNY_775315_*` names, `isDefault: false`). Names only — no values.
- `BUNNY_LIBRARY_ACTIVATION_VAR = "BUNNY_ACTIVE_LIBRARY_IDS"`,
  `BUNNY_LEGACY_FALLBACK_VAR = "BUNNY_LEGACY_LIBRARY_FALLBACK"`.
- `normalizeBunnyLibraryId`, `findBunnyLibraryDefinition`, `isBunnyLibraryActive`.
- `resolveBunnyLibraryForResource({storedLibraryId, clientLibraryHintId}, env)`:
  hint must match the stored value, otherwise the hint is discarded; blank/absent
  ⇒ legacy default; unknown ⇒ `unknown_library`; non-activated ⇒
  `library_not_activated`; `BUNNY_LEGACY_LIBRARY_FALLBACK=false` ⇒
  `legacy_fallback_disabled`.
- `resolveBunnyPlaybackRuntime(env, libraryId)` → `{playbackUrlTemplate, tokenKey}` or a
  typed failure (`unknown_library` / `library_not_activated` / `incomplete_configuration`).
- `resolveBunnyStreamApiRuntime(env, libraryId)` → `{apiLibraryId, apiKey}`; the
  default library keeps the `BUNNY_STREAM_LIBRARY_ID` override for identical metadata behaviour.

### `functions/src/core/video/bunny_library_migration.ts` (NEW, pure)
- `validateBunnyLibraryMapping(mapping, env)`: empty ids, unknown library,
  unactivated library, and one video id mapped to two libraries.
- `planBunnyLibraryBackfill(rows, mapping, env)` → per-resource
  `set | unchanged | skipped_no_video_id | conflict` + summary + `mappingErrors`.
  A stored library that disagrees with the mapping is a `conflict` (never overwritten);
  an unmapped video id is a `conflict` (never guessed).

### `functions/src/scripts/backfill_bunny_library_id.ts` (NEW, CLI)
- `--mapping <file>` required; `--out`, `--project`; `--apply` opt-in.
- Dry run by default: prints the plan, writes `<stamp>-plan.json`, exits non-zero on
  mapping errors or conflicts.
- Before any write: `<stamp>-backup.json` (previous value + `updateTime`, doubles as the
  rollback source).
- Writes use `{lastUpdateTime}` preconditions (a row changed after planning is skipped
  and reported) and stamp `updated_by: "migration:adr-010"`.
- Never executed against any project in this task.

## Backend (modified)

### `functions/src/index.ts`
- Imports the registry and re-exports both ADR-010 modules (pure-helper pattern used by
  the existing test suite).
- `bunnyLibraryEnvSnapshot()` — server-only env view.
- `resolveIssuanceBunnyLibrary(resource, clientHint)` — trusted resolution, throws
  `failed-precondition` with the typed reason, returns `{libraryId, playbackUrlTemplate, tokenKey}`.
- `resolveBestEffortBunnyLibrary(resource)` — non-throwing variant for display media.
- `buildBunnyFileUrl(videoId, fileName, expiresInSeconds, libraryId = DEFAULT)` — resolves
  template + token key per library instead of reading the two global env vars.
- `bunnyStreamApiConfig(libraryId = DEFAULT)` — per-library Stream API credentials.
- `fetchBunnyVideoMeta(videoId, libraryId = DEFAULT)` — per-library cache key
  `libraryId:videoId`.
- `resolveVideoDisplayMedia(resource)` — resolves the library from the resource, drops
  Bunny poster/preview when it cannot resolve, and passes the library to both helpers.
- `generateBunnySignedUrl` — resolves the library **after** every authorization/window/
  session verdict (error precedence unchanged), signs with that library's template/key,
  logs `library=`, and reports placeholder errors per library.
- `serializeResource` — additive `bunnyLibraryId` key.
- `firstVideoFieldsFromResources` — additive `bunny_library_id` in the `first_video` map.

### `functions/test/run_all.js`
- Appends `test/bunny_library_registry.test.js` to the roster (no other line touched).

### `functions/package.json`
- Appends the new suite to `test:pure` (no other script touched).

## Flutter (modified)

### `lib/features/video_streaming/domain/entities/playback_entities.dart`
- `VideoResource.bunnyLibraryId` (nullable) + constructor parameter.
- `fromCallablePayload` parses `bunnyLibraryId` tolerantly: numeric ids only,
  malformed/non-string ⇒ null (legacy path). `_sanitizeBunnyId` now takes `Object?`
  so a non-string id cannot throw during listing parse.

### `lib/features/video_streaming/data/services/video_source_resolver.dart`
- Copies `bunnyLibraryId` when re-stamping the Guest verdict.
- Sends `libraryId` as a hint when present (server validates it; never a credential selector).

### `lib/features/video_streaming/presentation/controllers/video_playback_controller.dart`
- Fast-lane `VideoResource` carries `bunnyLibraryId: ref.bunnyLibraryId`. No other change.

### `lib/features/subject_navigation/domain/entities/subject_learning_entities.dart`
- `FirstVideoRef.bunnyLibraryId` + `fromLectureData` reads `bunny_library_id`
  (null for legacy pointers).

## Dashboard (new)

### `dashboard/lib/features/students/domain/bunny_library_association.dart` (NEW, pure)
- `defaultBunnyLibraryId`, `configuredBunnyLibraryIds`, `normalizeBunnyLibraryId`,
  `isValidBunnyLibraryId`, `bunnyLibraryIdForCreate` (video ⇒ stored or default,
  non-video ⇒ null), `bunnyLibraryIdForUpdate` (null ⇒ keep), and
  `validateBunnyLibraryAssociation` (unknown/missing/non-video-with-library errors).

## Dashboard (modified)

### `dashboard/lib/features/students/presentation/providers/subject_details_provider.dart`
- `LectureEditResource`, `UpdatedLectureResource`, `NewLectureResource` gain
  `bunnyLibraryId`.
- Both create batches write `'bunny_library_id': bunnyLibraryIdForCreate(...)`.
- Both edit reads map `bunny_library_id`; the update batch writes it only when non-null
  (null = keep the stored association).

### `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart`
- `StagedResource.bunnyLibraryId`; the Video dialog defaults new videos to the default
  library and echoes the stored value when editing. **No visual element added or changed.**

### `dashboard/lib/features/students/presentation/widgets/add_lecture_overlay.dart`
- `_StagedResource.libraryId` and `_ExistingResourceEntry.libraryId`; new videos get the
  default library; edit prefill/commit preserves the stored association. **No UI change.**

### `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`
- Quick-upload video write adds `'bunny_library_id': defaultBunnyLibraryId`.

## Tests (new)

- `functions/test/bunny_library_registry.test.js` — 30 assertions (registry, hint,
  activation, fallback switch, per-library signing/metadata, mapping validation,
  planner, `first_video` projection).
- `dashboard/test/bunny_library_association_test.dart` — 12 tests.
- `test/features/video_streaming/video_resource_library_test.dart` — 6 tests.

## Documentation (new)

`reports/adr010/implementation_progress.md`, `implementation_file_map.md`,
`test_results.md`, `remaining_blockers.md`, `FINAL_AUTONOMOUS_EXECUTION_REPORT.md`.
