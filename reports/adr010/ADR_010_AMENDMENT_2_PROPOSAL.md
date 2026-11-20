# ADR-010 — Amendment 2 (PROPOSAL)

Status: **PROPOSED — awaiting Platform Owner approval. Not in force.**
Date: 2026-11-17
Amends: `21_ADR_010_Multi_Library_Bunny_Stream.md` (v1.0, Approved)
Also supersedes: the `775315` requirement in ADR-010 "Open Items"
Related: `21_ADR_010_Amendment_1.md` (Implemented, pending deployment)

> This is a proposal file in `reports/adr010/`. It does **not** modify
> `21_ADR_010_Multi_Library_Bunny_Stream.md`. On approval, its normative text is to be
> published as `21_ADR_010_Amendment_2.md` and the original ADR's status line updated to
> "Approved — amended by Amendment 2".

---

## 1. Context

ADR-010 (v1.0, 2026-11-12) recorded the Platform Owner's decision that the platform must
support multiple Bunny Stream libraries, and it enumerated options. It did not record
which option was selected, and its Open Items still require configuring library `775315`.

Since then:

- The Platform Owner approved **Option C — Hybrid Multi-Library Bunny Stream**, together
  with recommendations N1–N12 from the Mission 8 onboarding architecture review.
- Phase 0 (2026-11-17) established the production baseline and found that the *read*
  half of Option C already exists in Production (catalog read path, per-library secret
  resolver, per-resource library resolution, emergency-list semantics) while the *write
  and lifecycle* half does not exist at all (no registration, no revocation, no
  verification job, no receipt key, no Stream upload).
- Phase 0 also established that one approved recommendation — **N2** — cannot be
  implemented from documented Bunny capability. That is recorded here as a feasibility
  limitation, not resolved by assumption.

This amendment records Option C as the target architecture and incorporates N1–N12 as
normative decisions, **without** asserting that every one of them is currently
implementable.

---

## 2. Decision

**Option C — Hybrid Multi-Library Bunny Stream — is the approved target architecture.**

The platform supports multiple independently managed Bunny Stream libraries, selected
and resolved exclusively on the server, with a server-managed catalog as the source of
truth and per-library credential isolation in Secret Manager.

This amendment:

1. records Option C as the selected option;
2. incorporates N1–N12 as normative decisions, each carrying an explicit
   implementation-status qualifier (§3);
3. removes the ADR-010 Open Item requiring configuration of library `775315` and
   replaces it with a deferral (§5);
4. defines the catalog, isolation, fail-closed, emergency-deactivation, receipt-key and
   upload-security contracts (§4);
5. does **not** authorize any deployment, secret creation, IAM change, Bunny change,
   Firestore migration, Rules change, Functions deployment, Hosting deployment, or App
   Check change.

No security guarantee of ADR-010 v1.0 is weakened by this amendment.

---

## 3. Normative decisions (N1–N12)

The decision text below is the approved wording. The **Implementation status** column is
an evidence statement from Phase 0/Phase 1, not part of the decision.

| ID | Decision (approved wording) | Implementation status at 2026-11-17 |
|---|---|---|
| N1 | Server-managed library catalog. | Read path implemented and deployed; write path absent; Production catalog empty; Staging holds one manually written entry (`780700`). Schema has no approved documentation home. |
| N2 | Account-level API credential stored in Secret Manager, using a Stream-only sub-user with least privilege. | **Not implemented. Feasibility not established.** No such credential exists; Bunny's published model documents a single full-access account key and dashboard-only, account-wide team permissions. See §4.7. |
| N3 | Use `ReadOnlyApiKey` for read operations where supported. | Not implemented. Whether `ReadOnlyApiKey` is returned unmasked and supports every required read endpoint is unverified. |
| N4 | Backend may enable CDN Token Authentication only for libraries registered through the platform and after the documented ownership and safety checks. | Not implemented. `PlayerTokenAuthenticationEnabled` is a writable library property; not proven against this account. |
| N5 | Dedicated `BUNNY_ASSOCIATION_RECEIPT_KEY`, with a 10-minute dual-verification transition. | **Not implemented.** Receipts are currently signed with `BUNNY_TOKEN_KEY`; TTL is 600 s. |
| N6 | `BUNNY_ACTIVE_LIBRARY_IDS` is an emergency deny list only. It can reduce eligibility, never grant eligibility. | Implemented as an intersection over catalog rows: it can only reduce. Naming says "active"; semantics are "allowed". The default library bypasses it — see §4.5. |
| N7 | Protected Dashboard workflow with masked one-time token-key fallback only when automatic retrieval is not proven. | Not implemented; no UI authority exists. |
| N8 | Figma scope includes library picker, registration/management, fallback credential input, and upload workflow as specified in Mission 8. | Not implemented. Figma nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` are inaccessible. |
| N9 | Daily verification job and an approved alert channel. | Not implemented; no scheduler, no channel. |
| N10 | `775315` remediation is deferred. Keep it inactive. | Satisfied by configuration: no `BUNNY_775315_*` secret exists in either project and it is absent from both `BUNNY_ACTIVE_LIBRARY_IDS` values. |
| N11 | The platform must not create Bunny libraries. | Satisfied: no library-creation endpoint exists in the codebase. |
| N12 | During Account API unavailability, existing playback may use valid cached catalog and credentials until their defined validity expires. New provisioning must fail closed. | Partially satisfied: a 60 s secret cache exists; no catalog validity window is defined. Provisioning does not exist, so "fails closed" is true only trivially. |

**Normative effect of the status column:** none. A decision that is not implemented is
still binding as a design constraint. Implementation may not contradict it, and may not
be declared complete while the status remains "not implemented".

---

## 4. Contracts established by this amendment

### 4.1 The server-managed catalog

`bunny_libraries/{libraryId}` is the trusted, non-secret source of truth for which
libraries this platform may use.

- It contains **no key material**. It contains ids, host, booleans, verification
  timestamps, error codes, and the **names** of Secret Manager entries.
- It is never client-readable and never client-writable. All access is through callables
  or Admin SDK.
- A document that does not parse, is not `active`, does not have token authentication
  enabled, or has not had token authentication verified is **never eligible**. A
  dashboard toggle alone is never sufficient.
- The client-visible projection of a library is exactly `{libraryId, displayName}`.
  Pull zone, host, credential names, verification stamps and error codes are server-only.

### 4.2 Library identity and credential isolation

- Library identity is a numeric Bunny library id. No path, UUID, URL or operator-chosen
  label may serve as identity.
- Secret names are **derived deterministically** from the library id:
  `BUNNY_<libraryId>_STREAM_API_KEY` and `BUNNY_<libraryId>_TOKEN_KEY`. Rotation is
  auditable precisely because the name is not operator-chosen.
- A request that concerns library *X* may read only library *X*'s credentials. A missing
  credential for *X* is an error; it is never satisfied by *Y*'s credential, and never by
  a global default, except for the explicitly documented legacy default-library path.
- Clients never receive a Stream API key, a token key, a pull-zone security key, or a
  credential reference name.

### 4.3 Fail-closed rules

The following conditions must deny the operation. They are normative:

| Condition | Required behaviour |
|---|---|
| Library id missing, non-numeric, or unknown to the catalog | Deny |
| Catalog document fails validation (any field) | Deny |
| `status` is not `active` | Deny |
| `token_auth_enabled` is false | Deny |
| `token_auth_verified` is false | Deny |
| Library is named by the emergency list as ineligible | Deny |
| Library's credential missing in Secret Manager | Deny — never substitute another credential |
| Library's credential malformed | Deny |
| Video does not belong to the named library | Deny — never cross-library associate |
| Caller lacks the required authorization | Deny |
| Catalog read fails | Deny the *provisioning* operation; playback may use the approved cached path (N12) |

"Deny" means the operation fails with a typed error that reveals no credential, host, or
internal identifier. Silent fallback to a different library is forbidden.

### 4.4 Video association

An association is only written after the backend has verified, using **that library's**
credential, that the video exists in **that** library. The receipt proving this is
short-lived (600 s today) and bound to the resource and lecture when supplied. A client
may not set `bunny_library_id` directly; Firestore Rules must continue to force it to
`null` on client create and to keep it immutable on client update.

### 4.5 Emergency deactivation (N6)

The emergency list reduces eligibility; it never grants it. Two consequences follow:

- The implemented behaviour (intersection over catalog rows) is compliant.
- The **variable name** `BUNNY_ACTIVE_LIBRARY_IDS` describes the opposite mental model
  and must be documented as a legacy name, not renamed silently.
- The **default library currently bypasses the list** (`isDefault`). Whether the default
  library must also be subject to the emergency list is an open decision (D-06 in
  `ADR_010_OPTION_C_UNRESOLVED_DECISIONS.md`). Until it is decided, this amendment does
  not claim that the emergency list is a complete kill switch.

### 4.6 Receipt-signing key migration (N5)

Receipts must be signed by a **dedicated** key, not by the CDN token key, so that token
rotation does not invalidate in-flight associations.

Normative requirements for the migration:

- The transition window is 10 minutes, matching the current receipt TTL exactly.
- During the window the verifier accepts receipts signed by either key; the issuer signs
  only with the new key.
- After the window, the old-key path is removed in a separate, approved change.
- Clock skew must be bounded and documented; a receipt must not be accepted because a
  clock is wrong.
- Rollback restores the previous signer and verifier pair without invalidating receipts
  already issued inside the window.
- The new key is created through the approved Secret Manager gate; no existing production
  key is rotated or replaced as part of this migration.

### 4.7 N2 — accurate statement of the limitation

N2 as approved requires an account-level credential scoped to Stream with least
privilege. The evidence available does not support that scope:

- Bunny's published documentation describes **one** account API key that grants full
  access to the account.
- Team permissions are **dashboard** permissions and are coarse: "Manage zones" covers
  all pull zones, storage zones, DNS zones **and** Stream libraries. There is no
  per-library permission.
- No published endpoint creates a scoped or sub-user API key; `ScopedApiKey` and
  `Subuser*` appear in the OpenAPI specification only as authentication-scheme names.

Therefore this amendment records N2 as **approved in intent, blocked in feasibility**.
It does not select a substitute. The three available resolutions (full-access key with
accepted risk / no account-API automation / written clarification from Bunny support) are
presented for decision in `ADR_010_OPTION_C_UNRESOLVED_DECISIONS.md` (D-01).

Until that decision is made, no account-level credential may be created and no
account-API automation may be implemented.

### 4.8 Upload security requirements

Whatever mechanism is ultimately proven, it must satisfy all of:

- No privileged key reaches the browser, the Dashboard, or the Flutter client.
- Upload authorization is bound to one intended library and cannot be replayed against
  another.
- Upload completion is verified server-side before any video is associated with a
  lecture.
- The resulting video identity is validated against the intended library.
- Incomplete or failed uploads leave no associable state.
- Size and resource limits are enforced, not advisory.
- If a server-side proxy is required, it must be justified against measured file sizes,
  function memory/timeout limits, and bandwidth — not assumed.

The mechanism itself (direct presigned TUS vs proxy) is not decided by this amendment;
it is an unresolved capability (U-05/U-06).

---

## 5. Supersession of the ADR-010 Open Items

ADR-010 v1.0 requires, in its Open Items, that library `775315` be configured (enable
token authentication, then register it).

**That requirement is withdrawn.** In its place:

- `775315` remains **deferred and inactive** (N10).
- No secret matching `BUNNY_775315_*` may be created.
- `775315` must not appear in `BUNNY_ACTIVE_LIBRARY_IDS` in any environment.
- Its registry definition may remain in code as an inert, non-activated entry.
- The consequence — the videos that live only in `775315` remain unplayable — is an
  **accepted limitation**, to be recorded in `05 Database` / `13 Releases` as such.

Re-activating `775315` later requires a new, separate owner decision; it is not implied
by this amendment.

---

## 6. Consequences

1. `05 Database` must document `bunny_libraries` and the Bunny fields on
   `lecture_resources` before any catalog write path is deployed. Until that approval,
   the catalog remains a proposal in this repository and the Production catalog remains
   empty.
2. `FINAL_DECISIONS` §4 must be amended, because it currently states that the Dashboard's
   video action is entering a Video ID only. Option C requires registration, selection and
   upload. The amendment text is proposed separately.
3. `03 UI/UX` has no approved authority for the four required surfaces; the Dashboard
   workstream remains blocked until Figma is accessible and the surfaces are approved.
4. The emergency list cannot yet be described as a complete kill switch (D-06).
5. N12's "defined validity" is undefined until D-07 is decided.
6. Existing playback must not break: the legacy default-library path remains in force
   until the Production catalog is populated and verified.

---

## 7. What this amendment does not authorize

Explicitly **not** authorized by approving this amendment:

- Creating, rotating, or deleting any secret.
- Any IAM change.
- Any Bunny configuration change, including enabling token authentication on any
  library.
- Any Firestore data write or migration.
- Deploying Cloud Functions, Firestore Rules, or indexes.
- Deploying the Dashboard or releasing the Flutter app.
- Changing `APP_CHECK_ENFORCEMENT`.
- Activating `775315`.

Each requires its own approval under the gate structure in
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`.

---

## 8. Approval block

| Field | Value |
|---|---|
| Prepared | 2026-11-17 |
| Approver | Platform Owner (Doctor) |
| Decision requested | Approve publication of this text as `21_ADR_010_Amendment_2.md` |
| Decision requested | Approve withdrawal of the `775315` Open Item, replaced by the N10 deferral (§5) |
| Not requested here | Any deployment, credential, IAM, Bunny, database, or UI authorization |

Proposed approval sentence:

> "I approve ADR-010 Amendment 2 as proposed: Option C is the target architecture,
> N1–N12 are normative with the implementation-status qualifiers shown, and the `775315`
> Open Item is withdrawn in favour of the N10 deferral. This approval does not authorize
> any deployment, secret, IAM, Bunny, database, or UI change."
