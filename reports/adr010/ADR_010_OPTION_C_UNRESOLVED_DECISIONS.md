# ADR-010 Option C — Unresolved Decisions Register

Status: **OPEN — awaiting Platform Owner decisions.**
Date: 2026-11-17
Purpose: one place where every decision that is *not* mine to make is stated exactly, with
the evidence available, so that no decision is made by assumption.

Rules applied:

- Decisions are not bundled. Each can be answered independently.
- A recommendation is given **only** where evidence supports one; otherwise the entry says
  "no recommendation".
- Nothing here blocks work that is genuinely independent. The "Blocks" field names what
  actually stops.
- No expiry value, threshold, or policy number is invented. Where a value is required, it
  is presented as a choice, not as a default I have chosen.

---

## D-01 — N2: Account API credential strategy

**Exact question.** Which of the three resolutions replaces the unimplemented N2?

**Why it matters.** N2 is the only approved decision that assumes a capability Bunny does
not document. Until it is resolved, no account-level credential may be created and no
account-API automation may be written.

**Evidence.**

| Fact | Source |
|---|---|
| Bunny documents one account API key granting full access to the account | `bunny.net/docs/account/api-keys` |
| Team permissions are dashboard-only and coarse: "Manage zones" covers all CDN zones, storage zones, DNS zones **and** Stream libraries | `bunny.net/docs/account/team-management/permissions` |
| No endpoint creates a scoped or sub-user API key; `ScopedApiKey` / `Subuser*` appear only as authentication-scheme names in the OpenAPI spec | `core-api-public-docs` OpenAPI v3 |
| No code in `functions/src` calls the account API at all; only `GET video.bunnycdn.com/library/{id}/videos/{videoId}` | Repository |
| The catalog, the resolver and playback work **without** any account credential | Staging runs this way today |

**Options.**

| Option | What it means | Security implication | Implementation impact |
|---|---|---|---|
| **A** — Full-access account key | Store the account key in Secret Manager, bound only to the runtime service account | The runtime would hold authority to create/delete libraries and zones. A compromise of the function runtime becomes an account compromise. Requires a written risk acceptance and a rotation procedure. | Unblocks automatic discovery, automatic token-auth enablement (N4), and N3 if a read-only key exists |
| **B** — No account-API automation | Libraries are registered manually; credentials are provisioned by the Owner per library; verification uses the library's own key | Preserves least privilege. No account-wide authority exists anywhere in the system. | N4 becomes manual; N7's fallback path becomes the primary path; N9 verification limited to what a library key can prove. **Nothing in Phase 4 is blocked.** |
| **C** — Ask Bunny support in writing | Request a definitive answer on whether a Stream-only or library-scoped credential exists and how to create it | No change until answered | Blocks N2 only; A/B-compatible work continues |

**Does it block the next task?** No. The catalog write path, receipt key, association,
audit and playback work are all achievable under Option B.

**Recommendation (evidence-supported): C now, build toward B.** C costs nothing and may
convert an unknown into a fact; B is the only option that is implementable today and the
only one that satisfies N2's least-privilege intent without accepting account-wide risk.
Option A should not be adopted merely to unblock convenience — it grants more authority
than any current requirement needs.

**Owner action.** Choose A, B, or C (or "C now, B as the build target").

---

## D-02 — Dedicated test library (E-02)

**Exact question.** Is Staging library `780700` authorized as the dedicated test library
for capability verification?

**Why it matters.** U-01…U-06 cannot run without a library that is neither `736742` nor
`775315`. Without them, N2/N3/N4 and the upload mechanism remain unverified.

**Evidence.**

| Criterion | `780700` |
|---|---|
| Not Production `736742` | Confirmed |
| Not deferred `775315` | Confirmed |
| Separate Bunny library | Yes — own pull zone `6807898`, own host `vz-b5f9cb68-f06.b-cdn.net` |
| Separate credentials | Yes — `BUNNY_780700_STREAM_API_KEY` v1, `BUNNY_780700_TOKEN_KEY` v1 (Staging only) |
| Separate Firebase project | Yes — `dr-tarek-staging` |
| Catalog entry already present | Yes — `bunny_libraries/780700`, status fields populated |
| Existing content | 3 lectures, 2 videos (test data) |

**Caveat.** Because it already holds test content, destructive capability tests must be
limited to newly created test assets.

**Does it block the next task?** Yes — it blocks U-01…U-06 and therefore the upload
mechanism decision (D-08).

**Recommendation (evidence-supported): authorize `780700`, with the caveat above.**
It satisfies every isolation criterion that can be verified without an account credential.

**Owner action.** "`780700` is authorized / not authorized as the dedicated test library."

---

## D-03 — Figma access (E-04)

**Exact question.** How will the four nodes be made readable?

**Why it matters.** `03_UI_UX` has no approved video or library screens. Implementing
without them means inventing UI, which the mission forbids.

**Evidence.** Re-verified 2026-11-17: 0 MCP resources/templates, no Figma tool, no Figma
token in the environment, no Figma browser session.

**Options.**

| Option | Requirement |
|---|---|
| Personal access token | `file_read` scope on the design file, exposed as `FIGMA_TOKEN` |
| Export | Read-only share link per node plus PNG at 2× and the node's spec panel |

**Does it block the next task?** It blocks Phase 6 entirely. It does not block Phase 3–5.

**Recommendation:** none possible — this requires an action only the Owner can take.

**Owner action.** Provide the token or the exports.

---

## D-04 — Alert channel for N9 (E-05)

**Exact question.** Which channel receives library verification alerts, and with what
credential?

**Why it matters.** N9 requires "an approved alert channel". Implementing verification
without a channel produces a job nobody reads.

**Evidence.** No alerting integration exists in the repository for this purpose. No
approved channel is recorded anywhere.

**Options.** Email to a nominated address / Slack or Discord webhook / in-app Doctor
notification / a Firestore-backed alert surface read by the Dashboard.

**Security implication.** Each option creates a new outbound dependency that may carry
operational data. A webhook URL is itself a credential and must live in Secret Manager,
not in code or Firestore.

**Does it block the next task?** It blocks T-CF.16 only.

**Recommendation:** none — this is an operational preference, not an evidence question.

**Owner action.** Choose the channel and provide the credential (or confirm "in-app only").

---

## D-05 — Database approval (E-06)

**Exact question.** Approve the `05 Database` schema addition?

**Why it matters.** It is the only hard governance blocker on the catalog write path.

**Evidence.** `05` is `Proposed — Pending Teacher Database Change Approval`. The proposed
schema in `ADR_010_OPTION_C_DATABASE_SCHEMA_PROPOSAL.md` matches the code exactly, so
approval introduces no new implementation risk.

**Does it block the next task?** Yes — it blocks Gate 2 (catalog write path) and the
`05`-dependent documentation.

**Recommendation (evidence-supported): approve.** The schema is already implemented and
already exercised in Staging; approving it makes the documentation match reality rather
than authorizing something new.

**Owner action.** Teacher Database Change Approval for the proposed text.

---

## D-06 — Emergency list vs the default library (E-07)

**Exact question.** Must the default library also be subject to the emergency list?

**Why it matters.** N6 says the list "can reduce eligibility, never grant eligibility".
Today the default library is always eligible via `isDefault`, i.e. the list cannot reduce
it. That is a *grant* that bypasses the control.

**Evidence.**

| Fact | Source |
|---|---|
| Eligibility is an intersection over catalog rows: `if (denyList && !denyList.has(option.libraryId)) continue;` | `bunny_library_catalog_reader.ts` |
| The default library is treated as active regardless of the list | `bunny_library_registry.ts` (`isDefault`) |
| An unset list means "not engaged" (not "deny everything") | `parseBunnyEmergencyDenyList` |
| Staging currently engages the list with exactly one id (`780700`) | Deployed env |

**Options.**

| Option | Behaviour | Risk |
|---|---|---|
| **A** — Subject the default to the list | The kill switch can disable every library, including the default | If the list is misconfigured to an empty set while engaged, all playback stops. Mitigated by the existing rule that *unset* means "not engaged". |
| **B** — Exempt the default, document it | The default library can never be blocked | The control is incomplete; an incident involving the default library cannot be contained without a deploy |

**Does it block the next task?** It does not block Phase 3–5. It **must** be resolved
before Gate 6 (Flutter release), because that gate's only rollback story depends on a
working kill switch.

**Recommendation (evidence-supported): A.** It is the only option consistent with N6 as
written. The outage risk is manageable precisely because "unset" already means "not
engaged", so the safe default is preserved.

**Owner action.** Choose A or B.

---

## D-07 — Catalog and credential validity windows (E-08)

**Exact question.** What is the "defined validity" in N12 for (a) the cached catalog and
(b) cached credentials?

**Why it matters.** N12 permits cached data to support playback "until their defined
validity expires". No validity is defined today, so the permission is unbounded in
practice.

**Evidence.**

| Fact | Source |
|---|---|
| Credential cache TTL is 60 s | `BUNNY_SECRET_CACHE_TTL_MS = 60_000` |
| No catalog staleness check exists | `bunny_library_catalog_reader.ts` has no expiry logic |
| Verification cadence is itself undecided (N9/D-04) | — |

**Options (structure, not invented numbers).**

| Option | Meaning | Security implication |
|---|---|---|
| **A** — Validity = until the next scheduled verification, with a maximum age equal to the verification interval | Validity is derived from a decision already required, not from a new arbitrary number | Stale data lives at most one verification cycle |
| **B** — Validity = the existing 60 s credential cache only; catalog has no expiry | Minimal change | A catalog entry disabled in Bunny could keep serving until the next deploy |
| **C** — Fixed maximum age chosen by the Owner | Explicit | Requires choosing a number |

**Does it block the next task?** It blocks completion of N12, not Phase 4.

**Recommendation (evidence-supported): A.** It avoids inventing a value by tying validity
to the verification cadence that N9 already requires.

**Owner action.** Choose A, B, or C (and, if C, the number).

---

## D-08 — Upload mechanism

**Exact question.** Direct presigned TUS upload, or a server-side proxy?

**Why it matters.** This determines the entire upload design and the Dashboard UI.

**Evidence.** TUS presigned upload is documented: the server computes
`SHA256(libraryId + apiKey + expire + videoId)` and the client uploads to
`https://video.bunnycdn.com/tusupload` without a key. It has **not** been proven against
this account, and the maximum reliable file size from a browser on a poor connection is
unknown.

**Status:** this is a **capability question first** (U-05/U-06). It becomes an owner
decision only if the capability fails and the fallback changes user-visible behaviour
(proxy = slower, size-limited; out-of-band = manual video-id entry returns).

**Does it block the next task?** It blocks Phase 6 upload UI and T-CF.17.

**Recommendation:** none until U-05/U-06 run. Do not design against an unproven mechanism.

**Owner action.** None yet. After verification, approve the resulting mechanism.

---

## D-09 — The seven video rows without a video id

**Exact question.** What happens to the 7 `lecture_resources` rows with no
`bunny_video_id` (1 deleted, 6 visible)?

**Why it matters.** The migration gate "every video resource has a verified library
mapping" cannot pass while they exist. They are also a user-facing defect: 6 of them are
marked visible but cannot play by any path (no video id, no `resource_url`, no
`storage_path`, no thumbnail).

**Evidence.** Production census, 2026-11-17.

**Options.**

| Option | Effect |
|---|---|
| **A** — Leave as-is | Gate can never pass; 6 visible-but-unplayable items remain |
| **B** — Hide the 6 (`is_visible=false`), keep the deleted one soft-deleted | Removes the UX defect without deleting data; gate still blocked but honestly |
| **C** — Delete the 7 rows | Destructive; loses whatever intent they represented |
| **D** — Re-upload content and associate | Requires source media that is not available to me |

**Does it block the next task?** It blocks the *absolute* form of the migration gate. It
does not block catalog work.

**Recommendation (evidence-supported): B**, pending a content decision. It is reversible,
non-destructive, and removes a defect. The deleted row needs no action.

**Owner action.** Choose A, B, C, or D.

---

## Summary

| ID | Question | Blocks | Recommendation |
|---|---|---|---|
| D-01 | N2 strategy (A/B/C) | N2, N3, N4 automation | C now, build toward B |
| D-02 | Authorize `780700` as test library | U-01…U-06, upload | Authorize |
| D-03 | Figma access | Phase 6 (all UI) | None possible |
| D-04 | Alert channel | T-CF.16 only | None |
| D-05 | `05` schema approval | Gate 2, catalog write | Approve |
| D-06 | Default library vs emergency list | Gate 6 | Subject default to list (A) |
| D-07 | Catalog/credential validity | N12 completeness | Tie to verification cadence (A) |
| D-08 | Upload mechanism | Phase 6 upload, T-CF.17 | After U-05/U-06 |
| D-09 | 7 unmapped video rows | Absolute migration gate | Hide the 6 (B) |

**None of these blocks Phase 3 preparation or the receipt-key workstream (W08).**
