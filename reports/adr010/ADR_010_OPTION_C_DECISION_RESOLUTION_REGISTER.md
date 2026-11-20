# ADR-010 Option C — Decision Resolution Register

Status: **Closed for the decisions that evidence can settle; owner-dependent items consolidated.**
Date: 2026-11-18
Supersedes nothing. Companion to
`ADR_010_OPTION_C_UNRESOLVED_DECISIONS.md` (the original D-01…D-09 register).

The mission directive requires that every decision be handled in exactly one of four ways:

1. resolved from repository evidence and the approved architecture;
2. resolved by choosing the safest reversible option that does not change a business decision;
3. recorded as an external blocker (credential, third-party answer, Figma, business choice);
4. never fabricated and never silently bypassed.

This register applies that rule to D-01…D-09. **No decision below was answered by
assumption.**

---

## Summary

| ID | Subject | Classification | Resolved by this mission | Owner action still required |
|---|---|---|---|---|
| D-01 | N2 account API credential | **Resolved to the safe posture (B); "ask Bunny" is external** | Implementation posture fixed at "no account-API automation" | Acknowledge B, or later approve A/C |
| D-02 | `780700` as test library | **External blocker — business authorization** | Read-only inspection only | Authorize or refuse |
| D-03 | Figma access | **External blocker — credential/access** | Phase 6 UI kept BLOCKED | Provide token or exports |
| D-04 | Alert channel for N9 | **External blocker — business choice** | Manual `verifyBunnyLibrary` implemented instead of a scheduler | Choose channel + credential |
| D-05 | `05 Database` schema approval | **Resolved** | `05` bumped to 1.11, Approved (documentation only) | None for documentation |
| D-06 | Default library vs emergency list | **Owner decision (security posture)** | Current behaviour preserved and documented | Choose A or B |
| D-07 | Catalog / credential validity | **Owner decision, depends on D-04** | 60 s credential cache unchanged; no invented expiry | Choose A/B/C |
| D-08 | Upload mechanism | **Capability-blocked (needs D-02 + D-01)** | Required behaviour documented; no mechanism chosen | After U-05/U-06 |
| D-09 | 7 unmapped Production video rows | **External blocker — Production data write** | Nothing written to Production | Choose A/B/C/D |

---

## D-01 — N2: account API credential strategy

**Classification: resolved to the safest reversible posture (Option B), with the
third-party question (Option C) recorded as external.**

**Why this is a resolution and not a guess.** The mission directive permits choosing the
safest reversible option when it stays inside the approved architecture and does not change
a business decision. Option B is that option:

- The approved architecture (ADR-010 Amendment 2, N1/N6/N12) requires a server-managed
  catalog, per-library credential isolation and fail-closed eligibility. **None of these
  requires an account-level credential.**
- No code in `functions/src` calls the Bunny account API. The only Bunny calls are
  `GET https://video.bunnycdn.com/library/{id}` and `.../videos/{videoId}`, authenticated by
  that library's own Stream key.
- Option A would grant the runtime authority to create and delete libraries and zones. That
  is strictly more authority than any current requirement, and reversing it requires key
  rotation — not a reversible choice.
- Option B is what Staging already does today, so it introduces no new runtime behaviour.

**What this mission did.** Nothing was created, and no account-API automation was written.
That is the correct implementation of B.

**What remains external.** Whether Bunny can issue a Stream-only or library-scoped
credential is a third-party answer. Until Bunny answers, N2's "least privilege" intent is
satisfied by B rather than by N2 as originally worded.

**Owner action.** Acknowledge B as the standing posture. Option A remains available later
but requires a written risk acceptance and a rotation procedure. Nothing is blocked by
waiting.

---

## D-02 — Dedicated test library (`780700`)

**Classification: external blocker — business authorization.**

The directive does not grant permission to treat `780700` as an authorized test library;
that is a business decision about using Staging content for capability tests. Read-only
inspection was performed and is unchanged from the original register:

| Criterion | `780700` |
|---|---|
| Not Production `736742` | Confirmed |
| Not deferred `775315` | Confirmed |
| Own pull zone and host | Confirmed (`6807898`, `vz-b5f9cb68-f06.b-cdn.net`) |
| Own credentials, Staging only | Confirmed (two secrets, one enabled version each) |
| Catalog entry exists | Confirmed (`bunny_libraries/780700`) |

**What this blocks.** U-01…U-06, and therefore the upload-mechanism decision (D-08). It does
not block registration, deactivation, verification, playback or receipt work.

**Owner action.** "`780700` is authorized / not authorized as the dedicated test library."

---

## D-03 — Figma access

**Classification: external blocker — access.**

Re-verified during this mission: the environment contains no Figma MCP resource, no Figma
tool, no `FIGMA_TOKEN`, and no browser session against the design file. The four required
nodes remain unreadable:

- `58011:1024` — library picker
- `58335:1444` — library registration / management
- `871:1074` — fallback credential input
- `58171:1964` — upload workflow

**What this mission did.** All Phase 6 visual work is explicitly **BLOCKED**. No screen,
widget, colour, spacing, copy or interaction was invented. The non-visual Dashboard
scaffolding that already existed (domain model, gateway, validation) was left intact and was
not extended into UI.

**Owner action.** Provide a `FIGMA_TOKEN` with `file_read`, or read-only exports (PNG at 2×
plus the node spec panel) for the four nodes.

---

## D-04 — Alert channel for N9

**Classification: external blocker — business choice.**

No approved channel exists, and a webhook URL is itself a credential that must live in
Secret Manager. Choosing email vs Slack vs in-app is an operational preference, not an
evidence question.

**What this mission did instead.** Implemented `verifyBunnyLibrary` as a Doctor-triggered,
audited, on-demand verification callable. It performs the same probe a scheduled job would
perform, and fails closed with a typed code. It does **not** claim to satisfy N9, which
requires a scheduled job plus an approved channel.

**Owner action.** Choose the channel and provide its credential, or confirm "in-app only".

---

## D-05 — `05 Database` schema approval

**Classification: resolved.**

The Owner approved Phase 2 item C. `05 Database 1.8.md` is now **Version 1.11, Approved**,
containing:

- `## bunny_libraries` with the 11-field table, the state machine, and the eligibility
  predicate;
- the three Bunny fields on `lecture_resources` (`bunny_video_id`, `bunny_library_id`,
  `storage_provider`);
- `## admin_audit_log` with the eight-action Option C vocabulary and the forbidden-payload
  list.

**Scope of the approval.** Documentation only. Creating catalog documents, backfilling
`bunny_library_id`, and deploying any write path remain separately gated. The v1.10
subject-device/playback-session proposals remain **Proposed**.

**Owner action.** None for the documentation.

---

## D-06 — Default library vs the emergency list

**Classification: owner decision — security posture. Not silently changed.**

The implemented behaviour is preserved exactly: the default library is eligible through
`isDefault` and is **not** subject to `BUNNY_ACTIVE_LIBRARY_IDS`. Changing it would alter
Production playback semantics for every legacy resource, which is a business/availability
decision, not a technical cleanup.

**What this mission did.** Documented the limitation precisely in three places:
`21_ADR_010_Amendment_2.md` §4.5, `06_FIREBASE_ARCHITECTURE` §6.4.1, and this register. The
emergency list is **not** described as a complete kill switch anywhere.

**Why not choose A unilaterally.** A is technically defensible, but a misconfigured engaged
list would stop all playback — the opposite of "safest reversible" during an active
deployment. The reversible choice is to keep today's behaviour until the Owner decides.

**Owner action.** Choose A (subject the default to the list) or B (keep the exemption).

---

## D-07 — Catalog and credential validity windows (N12)

**Classification: owner decision; its recommended answer depends on D-04.**

No expiry value was invented. The credential cache remains **60 s**
(`BUNNY_SECRET_CACHE_TTL_MS`), which is the only validity that exists in code. The catalog
reader still has no staleness window, so N12 remains **partially satisfied** and is recorded
as such.

**Owner action.** Choose A (validity = one verification cycle), B (60 s credential cache
only), or C (an explicit maximum age).

---

## D-08 — Upload mechanism

**Classification: capability-blocked.**

The mechanism cannot be chosen before it is proven, and proving it requires D-02
(authorized test library) and, for the documented TUS flow, an account credential (D-01).
Neither is available. `uploadBunnyResource` / `deleteBunnyResource` exist in the source tree
but are **not deployed** in Staging.

**What this mission did.** Recorded the mandatory security properties of any future
mechanism in Amendment 2 §4.8 and `04_FEATURES` / `07_FLUTTER_ARCHITECTURE` §16.8, and
implemented **no** upload UI or endpoint change. No client-side key handling was introduced.

**Owner action.** After D-02 (and D-01 if TUS is chosen), approve the resulting mechanism.

---

## D-09 — Seven Production video rows without a video id

**Classification: external blocker — Production data write.**

Production census is unchanged: 13 video rows, 6 with `bunny_video_id`, 7 without (1
deleted, 6 visible), 0 with `bunny_library_id`. Any change to those rows is a Production data
operation requiring a separate approved backup/rollback plan, which this mission did not
receive.

**What this mission did.** Nothing in Production. The migration gate remains honestly
**blocked** rather than being redefined to pass.

**Owner action.** Choose A (leave), B (hide the 6 visible rows), C (delete), or D (re-upload
and associate).

---

## What is genuinely blocking mission completion

Only three items can stop the remaining phases:

| Blocker | Stops | Cannot be resolved by evidence |
|---|---|---|
| Figma access (D-03) | All Phase 6 UI | Yes — access only the Owner can grant |
| Production deployment authorization | Gate 1…Gate 6 | Yes — explicitly reserved to the Owner |
| Production data approval (D-09) | The absolute migration gate | Yes — data write |

Everything else that can be built and tested without those three has been built and tested.
