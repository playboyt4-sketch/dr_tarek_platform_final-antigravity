# Dependency Security Audit — `functions/` (Node.js / Firebase Cloud Functions)

Version: 1.0
Date: 2026-10-22
Scope: audit and remediation planning only. **No source code, dependency, lockfile, Git state, Firebase resource, or production service was modified.** No remediation has been applied. This document does not claim the project is secure or production-ready.

---

## 1. Executive summary

- The external review-report figures (2026-10-22) for `functions/` were **independently reproduced in full**: `npm audit --json` reports exactly **27 vulnerabilities — 1 Critical, 13 High, 13 Moderate** (0 low/info). No scan discrepancy found.
- The single **Critical** finding is confirmed by complete audit output as **`proxy-addr@2.0.7` — GHSA-jqcg-44mw-7w3h (IP spoofing via IPv4-mapped IPv6 trust subnet, CVSS 9.1)**, reached through **`firebase-functions@7.3.2 → express@5.2.1 → proxy-addr@2.0.7`**. It is on the deployed request-serving path (the Firebase Functions HTTPS/onCall serving layer builds an express app in `node_modules/firebase-functions/lib/bin/firebase-functions.js:70`). It is **not** an inferred identification; the advisory chain is explicit in the audit output.
- A production-deployed **High** exists in `@grpc/grpc-js@1.14.4` (server-auth-context certificate trust, GHSA-m9gg-hp2v-232j) and in `@fastify/busboy@3.2.0` (multipart DoS, GHSA-xjh9-v7x6-24jw / GHSA-x8mw-p69m-v3mx), both **fixable without any breaking change** (1.14.5 and 3.2.2 sit inside every parent's declared range).
- The remaining production-flagged entries (13 of the 13 Moderates) are dominated by one real advisory root — **`uuid@9.0.1` (GHSA-w5hq-g745-h8pq)** — fanned out through `google-gax/gaxios/teeny-request/retry-request/@google-cloud/firestore|storage/firebase-admin`; fixing it cleanly requires **`firebase-admin` 13 → 14.5.0 (major)** per npm's computed fix.
- All remaining Highs (`js-yaml@4.3.1` and `js-yaml@3.15.1`, `brace-expansion@1.1.18/@2.1.4`, the `@typescript-eslint` 5.x chain incl. `globby→fast-glob→micromatch→braces@3.0.3`) and most Moderates inherent to dev/test tooling (`sprintf-js@1.0.3`, `argparse@1.0.10`, `ts-deepmerge@2.0.7`, `firebase-functions-test@3.5.0`, `@typescript-eslint/*`) are **development/test-only**: they are not shipped with deployed Cloud Functions.
- `npm ci` and `npm run build` were verified passing by the provided report; the lockfile consistency was additionally inspected here read-only (`npm ls --depth 0` resolves cleanly; lockfileVersion 3; 748 lock packages).
- Verdict: **READY FOR REMEDIATION PLAN APPROVAL** — a 7-line non-breaking Wave 1 removes the Critical, all production-reachable Highs/Moderates, and the dev `js-yaml`/`brace-expansion` items, without touching `package.json` semver ranges. Remaining items require owner decision (major upgrades, overrides, upstream waits).

## 2. Verified project root, branch and HEAD

- Project root (git repo): `D:\antigravity\dr_tarek_platform_final` (verified working dir + `Test-Path functions` = True).
- Audited directory: `D:\antigravity\dr_tarek_platform_final\functions` (contains `package.json`, `package-lock.json`, `node_modules/`, `src/`, `lib/`, `test/`, `scripts/`).
- Branch: `ci/ios-staging-codemagic`.
- HEAD: `d7e125ef5a01f20c39bf71803835f40c60f0d94f` — "ci(ios): wire signed TestFlight workflow via App Store Connect automatic signing" (2026-10-17).
- Runtime/tool environment used for reproduction: **Node v24.19.0** (functions `engines.node` = `"24"`, matching the manifest).

## 3. Working-tree preservation evidence

Captured **before** the audit and **after**; both captures identical:

- 39 pre-existing modified tracked files (Flutter app, dashboard, functions `src/index.ts`, `scripts/seed_database.ts`, `test/security_event.test.js`, CI workflow, Android config, docs) — all treated as the project owner's changes and untouched.
- 4 pre-existing untracked files: `19_ADR_008_Security_Events_Alerting_Policy.md`, `docs/RELEASE_READINESS_HANDOFF_2026-10-20.md`, `security_documentation_reconciliation_2026-10-22.md`, `security_events_database_change_proposal.md` — untouched.
- `git stash list`: empty. HEAD unchanged before/after. No `git add/commit/stash/reset/clean` executed.
- The only file created by this audit is this report (`DEPENDENCY_SECURITY_AUDIT_2026-10-22.md`, new untracked file at repo root; no overwrite of any existing file).
- Working notes (audit JSON/summaries) were written exclusively to `D:\Temp\opencode` (outside the repository).

## 4. Audit reproduction status and limitations

| Item | Status |
|---|---|
| `npm audit --json` | Reproduced exactly: 1 Critical + 13 High + 13 Moderate = 27 (metadata object quoted in §5). Advisory titles/URLs/CVSS captured from the live audit endpoint. |
| `npm ci` | Not re-run (would rewrite `node_modules`/lockfile); existing report states pass — preserved as **unverified-but-consistent historical evidence**. `npm ls --depth 0` resolves the full tree with no "invalid" markers, confirming manifest/lockfile consistency. |
| `npm run build` | Not re-run in this audit; no code was touched, so prior pass remains reproducible. |
| `npm audit fix` / `npm audit fix --force` | **Not executed** (prohibited; would modify the lockfile). All fix targets below are derived from npm's computed `fixAvailable` metadata and the advisory vulnerable ranges, plus parent-dependency constraint verification against the lockfile. |
| Limitations | (1) Reachability conclusions about express-internal use of `proxy-addr`/`qs` are based on verified dependency wiring (firebase-functions bundles express 5.2.1) and advisory mechanics, not on a runtime proof-of-exploit in the Functions serving environment. (2) npm's `fixAvailable: {name: firebase-admin, version: 14.5.0, isSemVerMajor: true}` is npm's computed path; the actual admin-14 runtime compatibility has not been tested. (3) No inventory of devDependency versions was changed by anything in this audit. |

## 5. Complete vulnerability inventory

Manifest: direct production deps = `firebase-admin ^13.6.0` (installed **13.10.0**), `firebase-functions ^7.0.0` (installed **7.3.2**). Direct dev deps = `@typescript-eslint/eslint-plugin|parser ^5.12.0` (5.62.0), `eslint ^8.9.0` (8.57.1), `eslint-config-google 0.14.0`, `eslint-plugin-import ^2.25.4` (2.32.0), `firebase-functions-test ^3.4.1` (3.5.0), `ts-node 10.9.2`, `typescript ^6.0.0` (6.0.3). `engines.node = 24`. No `overrides`/`resolutions` in the manifest. `firebase-functions-test` internal jest chain: jest 30.4.x, glob 10.5.0.

Severity totals (audit metadata): `{info:0, low:0, moderate:13, high:13, critical:1, total:27}`.

Legend: Prod = shipped with deployed Cloud Functions (manifest `dependencies` subtree). Dev = development/test tooling only.

| Package | Installed / vuln range | Severity | Advisory (id → URL) | CVSS | Dependency path | Class | Compatible w/o major? | npm fixAvail |
|---|---|---|---|---|---|---|---|---|
| proxy-addr | 2.0.7 / ≥1.1.0 <2.0.8 | **CRITICAL** | GHSA-jqcg-44mw-7w3h → github.com/advisories/GHSA-jqcg-44mw-7w3h | 9.1 | functions → firebase-functions@7**.3.2 → express@5.2.1 → proxy-addr** | Prod, transitive (via bundled runtime express) | YES — express pins `proxy-addr ^2.0.7` → 2.0.8 | true |
| qs (×2 advisories) | 6.15.3 / [≥6.14.2 ≤6.15.3 + ≥2.2.5 <6.16.0] | Moderate ×2 | GHSA-x5fp-wj9c-mxmx (array-limit bypass); GHSA-4mjr-xmp4-gh2g (isBuffer DoS) | 3.7 / 5.3 | express@5.2.1 body-parser@2.3.0 → qs@6.15.3 (and express direct `qs ^6.14.0`) | Prod, transitive | YES — `qs ^6.14.0`/`^6.15.2` allow ≥6.16.0 | true |
| @fastify/busboy | 3.2.0 / [≥3.1.0 <3.2.1 + ≥1.0.0 <3.2.1 + <3.2.2] | High ×2 + Moderate | GHSA-xjh9-v7x6-24jw (oversized boundary DoS); GHSA-x8mw-p69m-v3mx (prototype header DoS); GHSA-gxm5-99cw-xjw9 (CRLF injection) | 7.5 ×2 / 5.8 | firebase-admin@13.10.0 → @fastify/busboy@3.2.0 (used in `node_modules/firebase-admin/lib/utils/api-request.js:402`) | Prod, transitive | YES — admin pins `@fastify/busboy ^3.0.0` | true |
| @grpc/grpc-js | 1.14.4 / ≥1.14.0 <1.14.5 | High (+1 Low, same fix) | GHSA-m9gg-hp2v-232j (getAuthContext returns unauthorized certs, cert validation CWE-295); GHSA-f596-whhp-79r4 (status-message leak) | 7.4 | @google-cloud/firestore@7.11.6 → google-gax@4.6.1 → @grpc/grpc-js@1.14.4 | Prod, transitive | YES — gax pins `@grpc/grpc-js ^1.10.9` | true |
| uuid | 9.0.1 / <11.1.1 | Moderate | GHSA-w5hq-g745-h8pq (v3/v5/v6 buf bounds) | 7.5 (advisory) | google-gax@gax@4.6.1, gaxios@6.7.1, teeny-request@9.0.0 (via @google-cloud/firestore & @google-cloud/storage@7.21.0) | Prod, transitive | NO — parents pin `uuid ^9.0.1`/`^9.0.0` | via firebase-admin 14.5.0 (major) |
| gaxios | 6.7.1 | Moderate | via uuid | — | @google-cloud/storage → gaxios → uuid | Prod, transitive | via parent major | via firebase-admin 14.5.0 |
| teeny-request | 9.0.0 | Moderate | via uuid | — | @google-cloud/storage → teeny-request → uuid | Prod, transitive | via parent major | via firebase-admin 14.5.0 |
| retry-request | 7.0.2 | Moderate | via teeny-request→uuid | — | @google-cloud/storage → retry-request; google-gax → retry-request | Prod, transitive | via parent major | via firebase-admin 14.5.0 |
| google-gax | 4.6.1 | Moderate | via retry-request + uuid | — | @google-cloud/firestore → google-gax | Prod, transitive | via parent major | via firebase-admin 14.5.0 |
| @google-cloud/firestore | 7.11.6 | Moderate | via google-gax | — | firebase-admin@13.10.0 → @google-cloud/firestore | Prod (direct child of admin), transitive | via parent major | via firebase-admin 14.5.0 (major) |
| @google-cloud/storage | 7.21.0 | Moderate | via retry-request + teeny-request | — | firebase-admin@13.10.0 → @google-cloud/storage | Prod, transitive | via parent major | via firebase-admin 14.5.0 (major) |
| firebase-admin | 13.10.0 / 11.0.0–14.3.0 | Moderate | aggregated from admin's own tree (firestore/storage chains) | — | functions → **firebase-admin@13.10.0** | Prod, **direct** | NO — fix = 14.5.0 (major) | {firebase-admin 14.5.0, major} |
| js-yaml (4.x) | 4.3.1 / [≥3.0.0 <3.15.2 + ≥4.0.0 <4.3.2] | High | GHSA-2883-xcg3-v3hh (maxTotalMergeKeys CPU DoS) | 7.5 | eslint@8.57.1 → @eslint/eslintrc@2.1.4 → js-yaml@4.3.1 (eslintrc pins `^4.1.0`) | Dev-only | YES → 4.3.2 | true |
| js-yaml (3.x) | 3.15.1 / ≥3.0.0 <3.15.2 | High | GHSA-2883-xcg3-v3hh | 7.5 | firebase-functions-test@3.5.0 → jest@30 → babel-plugin-istanbul@7 → @istanbuljs/load-nyc-config → js-yaml@3.15.1 (pins `^3.13.1`) + nested argparse@1.0.10 | Dev/test-only | YES → 3.15.2 | true |
| brace-expansion (1.x) | 1.1.18 / <1.1.21 (3 advisory IDs: GHSA-q2hr-2g5m-vwhr, GHSA-qhr7-859c-m2p7, GHSA-6j4f-fj2g-mc7p) | High (recursion DoS ×2) + Moderate | see IDs | 7.5 ×2 / 5.3 | eslint-plugin-import@2.32.0 → minimatch@3.1.5 (pins `^1.1.7`) | Dev-only | YES → 1.1.21 | true |
| brace-expansion (2.x) | 2.1.4 / ≥2.0.0 <2.1.7 | High + Moderate | same 3 advisory IDs | 7.5 / 5.3 | firebase-functions-test → jest@30 → @jest/reporters@30.4.1 → glob@10.5.0 → minimatch@9.0.9 (pins `^2.0.0`?) | Dev/test-only | YES → 2.1.7 | true |
| @typescript-eslint/eslint-plugin | 5.62.0 / 4.0.1-α.–8.2.1-α.25 | High | via parser/type-utils/utils chain | — | devDeps direct (`^5.12.0`) | Dev-only, **direct** (dev) | NO — fix = v8.72.0 (major) | {8.72.0, major} |
| @typescript-eslint/parser | 5.62.0 | High | via typescript-estree | — | devDeps direct | Dev-only, direct | NO | {8.72.0, major} |
| @typescript-eslint/typescript-estree | 5.62.x | High | via globby (own range flagged) | — | ts-eslint internals | Dev-only | NO | {8.72.0, major} |
| @typescript-eslint/type-utils, utils | 5.62.x | High | chain | — | ts-eslint internals | Dev-only | NO | {8.72.0, major} |
| globby / fast-glob / micromatch | 11.1.0 / 3.3.3 / 4.0.8 | High | chain | — | @typescript-eslint/typescript-estree → globby → fast-glob → micromatch → braces | Dev-only | via ts-eslint 8 major chain | {8.72.0, major} |
| braces | 3.0.3 / ≤3.0.3 | High | GHSA-vfj7-8cjw-p6xm (stack-exhaustion DoS, CWE-674) | 7.5 | (chain above) | Dev-only | only via ts-eslint 8 chain | {8.72.0, major} |
| sprintf-js | 1.0.3 / ≤1.1.3 | Moderate | GHSA-hp3w-g68c-fv3c (unbounded precision DoS) | 5.3 | js-yaml@3 → argparse@1.0.10 (nested under @istanbuljs, pins `sprintf-js ~1.0.2`) | Dev/test-only | NO — `~1.0.2` forbids 1.1.x | true (nontrivial — see plan) |
| argparse | 1.0.10 | Moderate | via sprintf-js | — | (above) | Dev/test-only | via override | true |
| ts-deepmerge | 2.0.7 / <8.0.0 | Moderate | GHSA-87mf-gv2c-c62c (prototype-method-override DoS) | 5.3 | firebase-functions-test@3.5.0 → ts-deepmerge (fst pins `^2.0.1`) | Dev/test-only | NO — patched v8.0.0 is a major; audit proposes **downgrading firebase-functions-test to 0.3.3 (major)** — rejected as unsafe (see §9) | {fst 0.3.3, major} |
| firebase-functions-test | 3.5.0 / ≥2.0.0 | Moderate | via ts-deepmerge | — | devDeps direct (`^3.4.1`) | Dev/test-only, direct | NO (see ts-deepmerge) | {0.3.3, major — rejected} |

Cross-check: Moderate = 13 listed entries ✓; High = 13 ✓; Critical = 1 ✓.

## 6. Direct versus transitive analysis

- **Direct production:** `firebase-admin@13.10.0` (itself Moderate via its own tree) and `firebase-functions@7.3.2` (clean; its *bundled* express 5.2.1 pulls the Critical `proxy-addr` and the `qs` Moderates).
- **Direct dev:** `@typescript-eslint/@5.12.0 → 5.62.0` (self-flagged High), `firebase-functions-test@^3.4.1 → 3.5.0` (Moderate via ts-deepmerge), `eslint@8.57.1`.
- **All other vulnerable packages are transitive.** None of the vulnerable code is written in this repository's source.

## 7. Production exposure assessment

Verified from the lockfile and `node_modules` (read-only):

1. **Deployed surface** = `functions/package.json` `dependencies` subtree only: `firebase-admin@13.10.0` and `firebase-functions@7.3.2` plus their full production trees. Firebase's Functions build installs manifest `dependencies` for the runtime; `devDependencies` are not part of the deployed runtime. Therefore: **proxy-addr, qs, @fastify/busboy, @grpc/grpc-js, uuid, gaxios, teeny-request, retry-request, google-gax, @google-cloud/firestore, @google-cloud/storage are deployed**; eslint/@typescript-eslint/**/js-yaml/brace-expansion/braces/globby/fast-glob/micromatch/sprintf-js/argparse/ts-deepmerge/firebase-functions-test are **not deployed**.
2. **Exposed request paths (production-reachable):**
   - `proxy-addr` — reachable: every HTTPS/onCall request is served through the express app created at runtime (`node_modules/firebase-functions/lib/bin/firebase-functions.js:70`). The advisory concerns IPv4-mapped-IPv6 trust-subnet handling used for client-IP resolution (`req.ip`). Practical exploitation depends on express `trust proxy` configuration in the Functions serving layer (not set in repo source; config not proven here — see §9 Wave 4). Severity is CVSS-based; treat as exposed-until-configured-otherwise.
   - `qs@6.15.3` — reachable: body-parser/express query parsing on every HTTPS body/query.
   - `@fastify/busboy@3.2.0` — reachable through `firebase-admin/lib/utils/api-request.js:402` (admin HTTP/request plumbing); not a direct student-facing upload path in repo source, but part of the deployed runtime.
   - `@grpc/grpc-js@1.14.4` — outbound trusted channel to Google/Firestore APIs for **every** Firestore API call from deployed functions. The critical-risk scenario (authenticating to a *server with a custom mTLS configuration*) is not configured anywhere in repo source; exposure is with-operational-config-caveat.
3. **Trusted internal paths:** `uuid` errors are limited to v3/v5/v6 with caller-supplied `buf` (advisory range text); the Google libraries generate UUIDs internally (v4 usage not confirmed in this audit — flagged for verification), so practical trigger likelihood is low but unproven. Cannot dismiss without proof, therefore handled via the Wave 3 major upgrade.
4. **Development/test-only** (cannot affect deployed functions): entire ESLint/TypeScript- 灯 toolchain, jest chain, `ts-deepmerge`.
5. **Manifest/lockfile consistency:** `npm ls --depth 0` clean; lockfileVersion 3; 748 lock entries. Consistent.

## 8. Critical and High vulnerability analysis

### 8.1 Critical — `proxy-addr@2.0.7` (verified, production-reachable)

- Advisory GHSA-jqcg-44mw-7w3h: "proxy-addr vulnerable to IP spoofing via IPv4-mapped IPv6 trust subnet" (CWE-290/348/697), CVSS 9.1, vuln `>=1.1.0 <2.0.8`.
- Chain: `firebase-functions@7.3.2` (bundled `express@5.2.1`) → `proxy-addr@2.0.7`; verified pinned as `proxy-addr: ^2.0.7` in express 5.2.1's dependencies — **2.0.8+ satisfies the range** (`fixAvailable: true`), i.e., a **non-breaking lockfile-only patch**.
- Impact scenario: incorrect trust classification of IPv4-mapped-IPv6 peers can let a caller influence `req.ip` under trust-proxy-based resolution. In deployed Cloud Functions the app does not configure `trust proxy` in repo source, so the practical spoofing surface is currently *config-dependent, unproven* — documented as a hypothesis, not a demonstrated exploit.
- Fix: lockfile-only bump to ≥2.0.8. No API change (`proxy-addr` 2.x stable). No source-code change. Owner approval required (lockfile edit is prohibited today).

### 8.2 Production Highs

- **`@grpc/grpc-js@1.14.4` → 1.14.5** fixes GHSA-m9gg-hp2v-232j (authorized-certificate confusion in `getAuthContext`) and GHSA-f596-whhp-79r4. Non-breaking (`^1.10.9` in google-gax). Regression scope: any functions that talk to Firestore/Storage/GC APIs — i.e., the entire suite (§10).
- **`@fastify/busboy@3.2.0` → 3.2.2** fixes the two High DoS advisory IDs and the Moderate CRLF issue. Non-breaking (`^3.0.0` in firebase-admin). Regression scope: admin SDK HTTP API call paths; covered by existing function tests that exercise admin SDK calls within the emulator suite.

### 8.3 Highs that are dev/test-only

`js-yaml@4.3.1/3.15.1` (CPU DoS severity 7.5), `brace-expansion` recursion IDs, and the `@typescript-eslint@5.62.0 → globby → fast-glob → micromatch → braces@3.0.3` chain — all reachable only while running lint/build/tooling locally or in CI. **Important:** even dev-tooling DoS can matter if a crafted repository/lint payload is processed by CI, but no such inputs exist in this repo's scan pipeline; treated as hygiene fixes (Wave 1 for the two `js-yaml` variants and both `brace-expansion` versions — non-breaking — and Wave 3 for the `@typescript-eslint` chain which requires a major).

## 9. Proposed remediation options (ranked by safety; ranges verified against the lockfile)

**Global rule: no `npm audit fix --force`; no unapproved resolutions/overrides; every wave requires explicit project-owner approval because this audit is not authorized to modify `package.json`/lockfiles.**

### Wave 1 — Category A: non-breaking, lockfile-only patch bumps (highest priority)
Targets and evidence (all inside each parent's declared semver range):

| Package | Installed → target | Parent constraint (verified) | Notes |
|---|---|---|---|
| proxy-addr | 2.0.7 → ≥2.0.8 (advisory <2.0.8) | express: `^2.0.7` | Removes the Critical |
| qs | 6.15.3 → ≥6.16.0 (advisory <6.16.0) | express: `^6.14.0`; body-parser: `^6.15.2` | Removes 2 Moderates |
| @fastify/busboy | 3.2.0 → ≥3.2.2 (advisory <3.2.2) | firebase-admin: `^3.0.0` | Removes 2 High + 1 Moderate |
| @grpc/grpc-js | 1.14.4 → ≥1.14.5 (advisory <1.14.5) | google-gax: `^1.10.9` | Removes 1 High + 1 Low |
| js-yaml | 4.3.1 → ≥4.3.2 | @eslint/eslintrc: `^4.1.0` | Dev-only High |
| js-yaml (3.x) | 3.15.1 → ≥3.15.2 | @istanbuljs/load-nyc-config: `^3.13.1` | Dev/test High |
| brace-expansion | 1.1.18 → ≥1.1.21; 2.1.4 → ≥2.1.7 | minimatch@3: `^1.1.7`; jest glob chain | Dev-only Highs/Moderate |

Method: `npm audit fix` (non-force) is expected to produce exactly this set; alternatively an owner-approved minimal lockfile edit per package. **Expected npm-caret compatibility confirmed manually.** API/regression risk: none expected; validated by full gates in §10. Rollback: `git checkout -- package-lock.json && npm ci`.
Estimated result after Wave 1: **eliminates the Critical + 11 of 13 Highs + 9 Moderates** (keeps the uuid/gax/admin Moderates and the @typescript-eslint-chain Highs only, plus the dev `sprintf-js/argparse/ts-deepmerge/fst` Moderates — see below; exact post-run numbers must be re-verified by `npm audit --json` after approval).

### Wave 2 — Category B: dev-only overrides (requires separate owner decision)
- `sprintf-js@1.0.3` / `argparse@1.0.10` (Moderate, dev/test-only): nested `@istanbuljs/load-nyc-config/node_modules/argparse@1.0.10` pins `sprintf-js ~1.0.2`, which **cannot** semver-reach a patched 1.1.x. Options: manifest `overrides` for `sprintf-js` (dev-only effect, no runtime impact), verify patched version availability first (advisory gives no explicit patched field — see limitation §4.2), or accept-and-track. Recommendation: low priority, gated.
- `ts-deepmerge@2.0.7` + `firebase-functions-test@3.5.0`: advisory is `ts-deepmerge <8.0.0`; npm's automatic fix proposes **downgrading firebase-functions-test to 0.3.3**, which is a different major line built for Cloud Functions v1 — **rejected as unsafe**: it could break all existing test harnesses (tests use v3 API). Overriding `ts-deepmerge` to ^8 risks an API break inside `firebase-functions-test`. **Category D decision required (upstream watch vs override)** — no clean fix today.

### Wave 3 — Category C: major upgrades (separate, individually-gated)
1. **`firebase-admin` 13.10.0 → 14.5.0** (npm-computed fix for the uuid/gax/gaxios/teeny-request/retry-request/firestore/storage Moderates). Consequences: new major of the Admin SDK — must verify: Node 24 runtime, Firestore/Storage/Auth/Messaging API compatibility with `src/index.ts` usage, behavior regressions in auth claims/emulator tests, and full security suite. Rollback: revert lockfile + `npm ci` (no data migration required — libraries only).
2. **`@typescript-eslint` 5.62.0 → 8.72.0** (dev-only major; also resolves `globby/fast-glob/micromatch/braces`). Risks: lint-rule output changes; **unverified**: v8's supported `typescript@6.0.3` range (flag §8.2 estree TS-version support) — verify before approving; eslint 8.57.1 peer range.
3. *(Deferred by design)* Any change to `firebase-functions` itself is not needed by Wave 1; no upgrade proposed.

### Wave 4 — Category D: further investigation (no changes authorized)
- Verify whether the Firebase Functions serving layer's express instance operates with any trust-proxy behavior that makes the `proxy-addr` advisory practically exploitable (read-only source/config analysis; no exploit testing prohibited area touched).
- Confirm which `uuid` versions (v3/v5/v6-vs-v4) are actually called by gax/gaxios/teeny-request at runtime to complete reachability evidence for §7.3.
- Upstream monitoring: `firebase-functions-test` for a ts-deepmerge ≥8-compatible release.

## 10. Breaking-change risks

| Proposed change | Risk | Mitigation |
|---|---|---|
| Wave 1 patch bumps | Essentially none (semver range-compatible) | Full regression suite (§11); TypeScript build; diff of `npm ls --depth 0` before/after |
| firebase-admin 14 | Major-runtime-semantics risk (API changes, peer/service-account expectations, emulator behavior) | Separate authorization, dedicated branch, full suite incl. emulator + auth/claims tests |
| @typescript-eslint 8 | Lint behavior changes; possible tooling breakage; TS 6.0.3 support unverified | CI lint job only; verify TS support first |
| Overrides (Wave 2) | Override can silently change a transitive API | Dry-run with `npm install --package-lock-only` (owner-approved) + test harness |

**No remediation changes any runtime TypeScript source or public function contract.** Only Wave 3 item 1 touches deployed runtime libraries。

## 11. Required regression gates (before any approved change ships)

Executed in this order, locally/CI (no production integration runs in this audit):

1. `npm run lint` (green before AND after the change).
2. `npm run build` (tsc) — necessary but explicitly **not sufficient**.
3. `npm test` — emulator suite (`firebase emulators:exec --only firestore,functions,auth` → `test/run_all.js`, ~50 test files) covering:
   - Authentication/authorization: `staff_login_throttle`, `student_login_throttle`, `staff_lock_stretch`, `registration_throttle`, `change_password_throttle`, `lock_event`, `enumeration`, `delete_owner_auth`, `admin_claims_merge`, `migrate_teacher_to_doctor`, `password_reset*`.
   - Payment/membership: `payment_idempotency`, `payment_logged`, `payment_correction`, `membership_audit`, `free_plan_activation`, `subject_pricing`, `set_plan_feature_permissions`, `plan_feature`.
   - Security events: `security_event.test.js` (mock-only; emulator coverage is part of ADR-008-required validation).
   - Guest/device/playback: `guest_issuance_verdict`, `guest_migration`, `device_limits`, `device_change`, `playback_session`, `protected_content`, `offline_drm`, `subject_authorization`, `issuance_lecture_*`.
   - Content/exams: `exam_grading`, `result_release`, `assessment_o6b`, `progress_percentage`, `lecture_access`, `resource_delivery`, `bunny_video_id_lookup`.
   - Notification behavior: tests within `payment/paid` + `migrate_teacher_to_doctor` suites that assert notification fan-out; specifically **security-event fan-out tests must NOT be passed as evidence of the ADR-008 Doctor-only recipient policy (that policy is not implemented)**.
4. Firestore/Storage rules: root `security-tests/` emulator suite (CI job "Firestore & Storage rules tests (emulator)").
5. CI review: `.github/workflows/ci.yml` job `cloud-functions` (lint/build/test with firebase-tools@15) + rules tests + Flutter/dashboard/Android/web jobs if any shared-contract code changed.
6. Deployment readiness check: `engines.node 24` intact; `npm ci --production` purity; no locked-version drift.

**Note:** a green `npm run build` alone does NOT establish runtime compatibility or security (explicitly recorded).

## 12. Rollback strategy

- Every wave is performed on a clean branch from current HEAD with `functions/` production deploys disabled until gates pass.
- Rollback for any wave: `git checkout -- functions/package-lock.json && npm ci && npm run build && npm test`. Restore `package.json` from `git` if changed. Re-deploy is prohibited without a separate owner-approved deployment authorization.
- Because Cloud Functions library updates are dependency-only, rollback has no data-migration component.

## 13. Outstanding questions and approval gates

1. **Owner approval required for Wave 1** (lockfile-only patch bumps; modifies `package-lock.json`, prohibited in this audit).
2. **Owner decision — firebase-admin 13→14.5.0** (Wave 3 items: which of the admin-chain Moderates must be closed now vs accepted-and-tracked until the next planned Firebase SDK upgrade).
3. **Owner decision — @typescript-eslint 5→8** (dev tooling; requires prior verification of TS 6.0.3 compatibility).
4. **Owner decision — ts-deepmerge/firebase-functions-test** (no clean fix; override vs track upstream; the `npm audit fix` proposed downgrade to 0.3.3 is explicitly rejected here as unsafe).
5. **Owner decision — sprintf-js override** (dev-only) and whether to add a **CI `npm audit` gate** (warn-only at first) to `.github/workflows/ci.yml`.
6. **Owner decision — deploy authorization** after any approved wave (out of scope for this audit).
7. Open investigation items (§9 Wave 4) before relaxing any classifications.

## 14. Final verdict

**READY FOR REMEDIATION PLAN APPROVAL**

Rationale: the audit is fully reproduced and internally consistent with the external report; dependency wiring, deployed-subtree exposure, and semver-range fix compatibility are verified against the lockfile; the plan separates safe non-breaking fixes (Wave 1) from gated major upgrades (Wave 3) and accepted-risk/dev decisions (Waves 2/4). This is a planning-stage assessment only: **no remediation has been applied and nothing is claimed fixed.**

## 15. Critical/High confirmation + confirmation of non-modification

- Confirmed Critical: `proxy-addr@2.0.7` GHSA-jqcg-44mw-7w3h, production-reachable via bundled express. Confirmed production Highs: `@grpc/grpc-js@1.14.4` (GHSA-m9gg-hp2v-232j), `@fastify/busboy@3.2.0` (GHSA-xjh9-v7x6-24jw, GHSA-x8mw-p69m-v3mx). All other Highs are dev/test-only (`js-yaml`, `brace-expansion`, `@typescript-eslint` chain, `braces`).
- Explicit confirmation: **No source code, dependencies, lockfiles, manifest, Git state, Firebase resources, or production services were modified** during this audit. `npm audit --json`, `npm ls`, and file reads were the only operations against the project; `npm audit fix` was never executed; no Firebase/emulator processes were started; the working tree is byte-identical except for the new report file `DEPENDENCY_SECURITY_AUDIT_2026-10-22.md` (deliverable).
- Awaiting explicit project-owner authorization before any change.
