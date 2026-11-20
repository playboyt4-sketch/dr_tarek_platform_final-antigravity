# ADR-010 — Firebase Emulator CI (Mission 3, Workstream B)

Status: **DONE (locally verified)** — the workflow is created and its exact command was
executed successfully on this machine. It has **not** been executed by GitHub Actions
(no push is authorized), which is stated explicitly below.

## 1. Existing CI inspected

`.github/workflows/ci.yml` (GitHub Actions) already had:

- `flutter-analyze-test`, `dashboard-analyze-test` (analyze + tests),
- `android-release-build`, `web-build`,
- `cloud-functions` (npm ci, dependency audit gate, `npm run lint`, `npm run build`,
  `npm test` — where `npm test` runs `firebase emulators:exec --only firestore,functions,auth`
  over the whole `test/run_all.js` roster),
- `firestore-storage-rules` (rules tests on a `demo` project).

No new CI provider was invented; the workflow is extended in place.

## 2. What was added

A dedicated job `adr010-emulator` in `.github/workflows/ci.yml`:

| Step | Detail |
|---|---|
| Environment | `runs-on: ubuntu-latest`, Java 17 (Firestore emulator), Node 24, `firebase-tools@15` |
| Install | `npm ci` in `functions` |
| Build | `npm run build` (compiled `lib/` is what the emulator loads) |
| Emulators | `--project demo-tarek-platform --only auth,firestore,functions` |
| Health | `emulators:exec` only runs the script after every emulator reports ready |
| Script | `node test/issuance_library_flow.test.js && node test/bunny_library_validation_flow.test.js` |
| Failure | `set -o pipefail` + non-zero script ⇒ step fails ⇒ job fails |
| Shutdown | `emulators:exec` always shuts the emulators down (verified in local runs) |
| Evidence | `adr010-emulator.log` uploaded as an artifact (`if: always()`) |

Fixtures are deterministic and fake: `BUNNY_TOKEN_KEY=fixture-signing-key`,
`BUNNY_PLAYBACK_URL_TEMPLATE=https://example.com/{video_id}/{quality}`,
`BUNNY_STREAM_API_KEY=fixture-api-key`, `BUNNY_STREAM_LIBRARY_ID=736742`, and
**`BUNNY_ACTIVE_LIBRARY_IDS` is never set**, so library `775315` stays inactive in CI.
No production project, credential or secret is referenced; the job cannot deploy.

## 3. Coverage exercised by the new job

`issuance_library_flow.test.js` (11 assertions, real callable via `firebase-functions-test`
against the emulators):

unauthenticated caller · legacy row issues through the default library · explicit default
association · unknown library fails closed (`unknown_library`) · inactive `775315` fails
closed (`library_not_activated`) · client hint disagreeing with stored value rejected ·
malformed hint rejected on an associated row · hint ignored on a legacy row · matching
hint accepted · subject without entitlement denied (`permission-denied`) · rolling window
still blocks a different lecture (`resource-exhausted`).

`bunny_library_validation_flow.test.js` (7 assertions):

unauthenticated · non-doctor (`permission-denied`) · embed URL rejected
(`invalid_video_id`) · unknown library unavailable · inactive `775315` unavailable ·
empty library rejected · closed response shape (no `apiKey`/`AccessKey`/token/secret).

## 4. Commands and actual results

| Command | Result |
|---|---|
| `python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` | **PASS** — `YAML_OK` |
| `node -e "JSON.parse(...functions/package.json)"` | **PASS** |
| `node --check functions/test/run_all.js` (and both new suites) | **PASS** |
| `firebase emulators:exec --project demo-tarek-platform --only auth,firestore,functions "node functions/test/issuance_library_flow.test.js && node functions/test/bunny_library_validation_flow.test.js"` | **PASS** — exit 0, `11` + `7` assertions, emulators shut down cleanly |
| `cd functions && npm test` (full 47-file roster incl. both new suites) | see `mission_3_final_report.md` for the actual outcome of this run |

## 5. Not verified

- **The GitHub Actions run itself is NOT RUN.** The YAML parses and the identical command
  passed locally, but runner-specific behaviour (java/node caching, network access to
  emulator binaries) is unproven until the workflow runs in GitHub.
- No workflow was triggered; nothing was pushed.
- The existing `cloud-functions` job still runs the whole `run_all.js` roster, which now
  also contains the two new emulator suites (they run there too).
