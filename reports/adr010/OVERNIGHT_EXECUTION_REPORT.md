# ADR-010 — Overnight Execution Report

Date: 2026-11-12
Author: Engineering (autonomous, read-only)
Scope: Multi-Library Bunny Stream — readiness, inventory, migration preparation
Status: **NO production change. No code change. No deployment.**

---

## 1. Executive summary

The ADR-010 decision is technically sound and the codebase is small enough to change safely. The
production evidence fully explains the student-facing HTTP 404 and confirms the library mismatch:

- Content library `775315` ("المنصة القديمة", 74 videos, Pull Zone `vz-c850a9e1-eb4.b-cdn.net`) holds
  the three published Financial Accounting lectures.
- The deployed backend is configured for library `736742` ("اختبار", 2 videos, Pull Zone
  `vz-c6abe953-876.b-cdn.net`).
- All 13 video resources were inventoried; **6 carry a Video ID and each is verified in exactly one
  library** (3 in `775315`, 3 in `736742`); 7 have an empty `bunny_video_id`.

Implementation cannot be deployed yet: the second library has **no server-side credentials** (the
existing Stream API key returns 401 for `775315`), and no playback template exists for its zone.
Additionally, the `775315` Pull Zone currently serves HLS **without token authentication**, which is a
content-protection gap that must be addressed on the Bunny side before that library serves production
traffic.

**Verdict: GO for implementation of the additive schema + backend resolver (unblocked, behind a
migration flag). NO-GO for deployment, backfill execution, or switching playback to `775315` until the
credentials and Bunny-side protection decision are in place.**

---

## 2. Work completed

| Workstream | Output | Status |
|---|---|---|
| A — Resource inventory | `bunny_resource_inventory.md`, `.csv` | ✅ complete (13/13 resources) |
| B — Library readiness | `library_configuration_readiness.md` | ✅ complete (2 libraries × 7 items) |
| C — Pull Zone compatibility | `pull_zone_compatibility.md` | ✅ complete for `736742`; `775315` signed test **NOT VERIFIED** (no key) |
| D — Backend design | `backend_implementation_design.md` | ✅ complete |
| E — Client change map | `client_implementation_map.md` | ✅ data/contract complete; **UI blocked (Figma)** |
| F — DB & migration design | `migration_design.md` | ✅ complete (dry-run design, no execution) |
| G — Test strategy | `test_strategy.md` | ✅ complete (15 cases, 6 layers) |
| H — Roadmap | `implementation_roadmap.md` | ✅ complete (19 tasks, 5 buckets) |

---

## 3. Files created

```
reports/adr010/bunny_resource_inventory.md
reports/adr010/bunny_resource_inventory.csv
reports/adr010/library_configuration_readiness.md
reports/adr010/pull_zone_compatibility.md
reports/adr010/backend_implementation_design.md
reports/adr010/client_implementation_map.md
reports/adr010/migration_design.md
reports/adr010/test_strategy.md
reports/adr010/implementation_roadmap.md
reports/adr010/OVERNIGHT_EXECUTION_REPORT.md
```

(Plus `21_ADR_010_Multi_Library_Bunny_Stream.md`, created in the previous approved documentation step.)

## 4. Existing files modified

**None.** No existing file, ADR, document, code, rule, or configuration was edited in this run.

Pre-existing working-tree modifications (present before this session, untouched here) are listed in the
final `git status` output: `dashboard/...` providers/screens, `functions/package.json`,
`functions/src/index.ts`, `functions/test/run_all.js`, plus untracked dashboard/function test files. They
were not overwritten, staged, or reverted.

## 5. Production access performed

Read-only only:

- Firestore REST `GET` / `runQuery` (OAuth via `gcloud auth print-access-token`) on
  `lecture_resources`, `lectures`, `subjects`.
- Cloud Functions `describe` / `list` (metadata: env var **names**, update times).
- Secret Manager `secrets list` / `versions list` (names and states only; **no value read**).
- Bunny Stream API `GET` (library metadata + video metadata) with the already-provisioned library key.
- Bunny CDN `GET` probes on both Pull Zones (status/content-type only).
- Bunny Dashboard (authenticated browser, read-only): library names, counts, pull-zone hostnames, one
  GUID search to confirm title/duration.

No writes. No deploys. No device binding. No signed URL issued to a student. No secret value printed or
stored.

---

## 6. Resource inventory summary

| Classification | Count |
|---|---:|
| Video resources total | 13 |
| VERIFIED → `775315` | 3 |
| VERIFIED → `736742` | 3 |
| MISSING (empty Video ID) | 7 |
| CONFLICT / UNVERIFIED | 0 |

Key rows:

| Resource | Lecture | Video ID | Library | State |
|---|---|---|---|---|
| `n2IpE7D3XslmNgBeeSeq` | المحاضرة الأولي (published) | `7ddd0e6e…` | 775315 | playable 35:54 |
| `6xIQtr6XHq68FkHfkQ7C` | المحاضرة الثانية (published) | `94710db9…` | 775315 | playable 68:26 |
| `mKzGszf8oiMQjkm0WzxW` | المحاضرة الثالثة (published) | `4dd8a3b0…` | 775315 | playable 39:20 |
| `TCmr0PTvUwVYrOkLzKyd` | archived+deleted | `6ffb23ad…` | 736742 | playable (security gap) |
| `iqfThonRycgDJ5xOdoKh` | archived+deleted | `6ffb23ad…` | 736742 | duplicate ID |
| `t9vPlLeXRlH5zG1UjPDE` | تجربة تجربة (published) | `d0c31ca2…` | 736742 | playable |

---

## 7. Library readiness matrix

| Item | `736742` | `775315` |
|---|---|---|
| Library ID configured | READY | **MISSING** |
| Stream API credential | READY (plain env var — should move to Secret Manager) | **MISSING** (401 with current key) |
| Pull Zone hostname | READY `vz-c6abe953-876` | VERIFIED `vz-c850a9e1-eb4` (not configured) |
| Token signing key | READY | **MISSING / not enforced** |
| Playback template | READY | **MISSING** |
| Hotlink/Referer | READY (empty → 403) | READY (app Referer → 200, empty → 403) |
| Metadata API | READY | **MISSING** (401) |

## 8. Pull Zone compatibility

- `736742`: signed 200 / unsigned 403 → token auth enforced, signing verified.
- `775315`: unsigned 200 with the app Referer → **works but unprotected**; signed behaviour NOT VERIFIABLE
  without its key.
- Failure classification for the incident: authentication PASS, authorization PASS, **resource existence
  FAIL / configuration MISMATCH**.
- `Referer: https://dr-tarek-platform.web.app/` is accepted by both zones → no client header change needed.

## 9. Security findings

1. **`775315` Pull Zone has no token authentication** (unsigned HLS 200). Content is protected only by
   GUID secrecy. Must be enabled (with a key) before this library becomes the production playback source.
2. **Archived/deleted lectures remain issuable** — `generateBunnySignedUrl` and `getLectureResources`
   check existence only. Two live resources belong to deleted lectures. Out of ADR-010 scope; needs
   separate approval.
3. **Duplicate Video ID** across two resource documents (`6ffb23ad…`).
4. **Stream API key stored as a plain function environment variable**, not Secret Manager — conflicts with
   ADR-010's secret-management requirement.
5. **7 placeholder video resources with empty Video ID** remain visible/published; they fail closed on the
   client but pollute listings and `first_video` selection.

## 10. Remaining blockers

| # | Blocker | Owner action |
|---|---|---|
| B1 | `775315` Stream API key | create secret + attach to functions |
| B2 | `775315` token-signing key + decision to enable token auth on its zone | Bunny dashboard + secret |
| B3 | `775315` playback template (per-library config) | configure with B1/B2 |
| B4 | Move `BUNNY_STREAM_API_KEY` into Secret Manager | config change approval |
| B5 | Dashboard library selector design (Figma) | confirm design or approve a minimal control |
| B6 | Verified mapping for every resource | satisfied for 6/6 with Video IDs; 7 rows have none |

## 11. Recommended first implementation task

**T1 — Additive, no-credential, no-deploy:**
Add nullable `bunny_library_id` to the Dart/Dashboard models and the pure `library_registry` resolver with
fail-closed behavior and unit tests, leaving production behavior byte-identical (migration flag off,
default library fallback preserved). This unblocks everything else and cannot affect students.

## 12. GO / NO-GO

- **GO** — to implement T1–T7 (schema + resolver + tests) after review.
- **NO-GO** — for deployment, backfill execution, and switching playback to `775315` until B1–B4 are
  resolved and the token-auth decision is made.
- **NO-GO** — for the Dashboard selector UI until B5 (design) is confirmed.

## 13. Validation performed at the end of this run

- `git status --short` reviewed: only the new `reports/adr010/*` files and the previously created ADR are
  added by this work; pre-existing modifications are untouched.
- No build, test, deploy, or migration command was run (none is safe/authorized without implementation).
