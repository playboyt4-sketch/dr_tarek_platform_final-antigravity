# ADR-010 — Mission 22: App Check Enforcement Hygiene (local code + config)

**Date:** 2026-11-16
**Scope:** Mission 21 §11 Phase E — local, non-production changes only.
**Mode:** code + config edits in the repo; **no** Production/Staging resource, secret, IAM, Firestore,
deployment or Git state touched.

Continues `MISSION_21_PRODUCTION_SECURITY_REMEDIATION_ASSESSMENT.md`. The production-affecting phases
(A rotation / secret creation, B.2 flip to `true`, C catalog + deployment, D verification) remain
**unexecuted and owner-gated**.

---

## 1. What was implemented

### E.3 + E.2 — corrupted `APP_CHECK_ENFORCEMENT` is now detected, not silently ignored

`functions/src/core/utils/security_helpers.ts` now parses the switch instead of comparing inline:

| Value | `enabled` | `malformed` | `mode` |
| --- | --- | --- | --- |
| `"true"` | true | false | `enforced` |
| `"false"` | false | false | `disabled` |
| absent / `""` | false | false | `disabled` |
| anything else | **false** | **true** | `malformed` |

- `SECURE_CALL_OPTS.enforceAppCheck` is still `enabled`, so **runtime behaviour is unchanged**:
  only the exact literal `true` enforces attestation.
- The malformed state carries only `rawLength`, never the value, so the production shape (a
  97-character flattened `.env` blob embedding the Stream API key) is detectable without handling or
  logging the credential.
- `functions/src/index.ts` logs one boot warning when the variable is malformed: enforcement is
  reported as DISABLED for that deployment. Skipped under `NODE_ENV=test`, matching the existing
  ADR-010 diagnostic, so suites stay deterministic.

### E.1 — `.env*` excluded from the deployed source archive

`firebase.json` → `functions[0].ignore` now contains `.env*` (after `*.local`). This stops
`functions/.env` and `functions/.env.dr-tarek-staging` from entering the per-function GCS source
archive (Mission 18 N-1 / Mission 21 R-4). Affects future deploys only; deployed archives are not
rewritten.

### Tests

`functions/test/app_check_enforcement.test.js` (16 checks) locks the table above, including the
production incident shape, near misses (`TRUE`, `1`, `"true "`, `"true\n"`, `false=true`) and the
guarantee that the malformed report exposes only a length. Wired into `npm run test:pure`.

---

## 2. Verification (executed)

| # | Command | Result |
| --- | --- | --- |
| 1 | `npm run build` (`tsc`) in `functions/` | exit 0 |
| 2 | `npm run test:pure` (includes the new suite) | exit 0 — all suites passed, 16/16 new checks |
| 3 | `firebase.json` JSON validity + ignore tail read-back | valid, `["*.local", ".env*"]` |

Not run: ESLint (its own budget issue in this environment, unchanged from Mission 21 U-7); no
emulator/deployed-function test, because no behaviour change was made.

---

## 3. Deliberately NOT done

| Item | Reason |
| --- | --- |
| A.5 / B.1 — scrubbing `functions/.env` to a single boolean | The file currently holds the **only** plaintext copy of the live Stream API key. Removing it before A.1 (rotation) + A.3 (Secret Manager creation) would destroy the value the owner needs to seed the secret. Must be done as part of the Phase A window, after the key exists in Secret Manager. |
| A.1–A.4, B.2, C.1–C.5, D.* | Production rotation, secret creation, IAM, catalog write and the 79-function deployment require explicit owner approval. |
| Any deploy | Not authorised in this mission. |

**Next owner decision remains exactly Mission 21 §14:** approve Phase A, then the separate B.2
(App Check `true`) decision, then Phase C deployment. With this mission's change, a recurrence of the
corruption is now visible in the boot log at the moment it is deployed, instead of being inferred from
production metadata later.
