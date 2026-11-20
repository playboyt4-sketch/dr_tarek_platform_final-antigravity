# ADR-010 Option C — Database Schema Proposal

Status: **PROPOSED — requires Teacher Database Change Approval. Not applied.**
Date: 2026-11-17
Target: `docs/notion/05 Database 1.8.md` (v1.10, *Proposed*)
Companion: `ADR_010_AMENDMENT_2_PROPOSAL.md`

> This is a proposal file in `reports/adr010/`. It does not modify `05 Database 1.8.md`.
> The schema is not authoritative until the Platform Owner grants the Teacher Database
> Change Approval.

---

## 1. Scope and discipline

Three things are proposed, and nothing else:

| # | Object | Nature |
|---|---|---|
| A | `bunny_libraries` collection | **Already implemented in code and already present in Staging**; undocumented in `05` |
| B | Bunny fields on `lecture_resources` | **Already present in Production data**; undocumented in `05` |
| C | `admin_audit_log` entries for library operations | Collection **already exists** and is already used by 20+ callables; only the new action vocabulary is proposed |

**No new field is invented to make the schema look complete.** Every field in §3 and §4
is validated by code today. Where a field would be useful but does not exist, it is
listed in §6 as *not proposed*, with the reason.

Governing rules:

1. **No plaintext credential ever.** The catalog stores only Secret Manager **names**,
   and even those are server-only.
2. **Server-written only.** Clients cannot create, update, or delete any of these
   documents. `bunny_libraries` is `allow read, write: if false` today and stays that way.
3. **Fail closed.** A document that fails any validation is ineligible, not "partially
   usable".
4. **No client authority over eligibility.** Status, verification flags and credential
   references are server-owned.

---

## 2. `bunny_libraries` — purpose and identity

`bunny_libraries/{libraryId}` is the trusted, non-secret source of truth for which Bunny
Stream libraries this platform may use. The document id equals `library_id`.

It is **not** a cache of Bunny state and **not** a credential store. It is the
authorization record: "this library may be used, and here is the name of the secret that
holds its key".

### 2.1 Field table

| Field | Type | Purpose | Req. | Validation (as implemented) | Authorized writer | Authorized reader | Sensitivity | Authority |
|---|---|---|---|---|---|---|---|---|
| `library_id` | String | Bunny Stream library identity; must equal the document id | Yes | `^\d{1,20}$` | Registration callable (Doctor only) | Server only | Low (identifier, but server-only by policy) | **Authoritative** |
| `display_name` | String | Operator-facing label shown in the Dashboard picker | Yes | non-empty after trim | Registration callable (Doctor only) | Server; projected to client as part of `{libraryId, displayName}` | Low | Informational |
| `status` | String enum | Lifecycle state | Yes | one of `pending_verification`, `active`, `disabled`, `error` | Registration / verification callables | Server only | Medium (drives eligibility) | **Authoritative** |
| `pull_zone_id` | Number | Bunny pull zone bound to the library | Yes | integer > 0 | Registration callable | Server only | Medium | Informational (used for verification and diagnostics) |
| `playback_host` | String | CDN hostname used to build signed URLs | Yes | `^[a-z0-9][a-z0-9-]{0,62}\.b-cdn\.net$` (lowercased) | Registration callable | Server only | Medium (host disclosure aids targeted abuse) | **Authoritative** for URL construction |
| `token_auth_enabled` | Boolean | Whether CDN Token Authentication is on for this library | Yes | strict boolean (`=== true`) | Registration / verification callables | Server only | Medium | **Authoritative** |
| `token_auth_verified` | Boolean | Whether a probe proved token authentication actually works | Yes | strict boolean (`=== true`) | Verification job only | Server only | Medium | **Authoritative** |
| `credential_refs` | Map | Names of the Secret Manager entries holding this library's keys | Yes | keys exactly `stream_api_key`, `token_key`; each value matches `^[A-Z][A-Z0-9_]{2,63}$`; any other key is dropped by the projection | Registration callable (derived from the library id, never operator-chosen) | Server only | Medium — names only, **never values** | **Authoritative** |
| `source` | String enum | How the library entered the catalog | Yes | one of `auto_discovered`, `manual_registration`, `legacy_env` | Registration callable | Server only | Low | Informational |
| `last_verified_at` | Timestamp \| null | Last successful verification | No | Firestore Timestamp or null | Verification job only | Server only | Low | Informational |
| `last_error_code` | String \| null | Last verification failure reason (typed code, never a message containing secrets) | No | string; empty normalizes to null | Verification job only | Server only | Low | Informational |

### 2.2 State machine

| From | To | Trigger | Preconditions |
|---|---|---|---|
| — | `pending_verification` | Registration | Library id valid; not already registered; display name present; credentials exist for that id |
| `pending_verification` | `active` | Verification | `token_auth_enabled === true` **and** `token_auth_verified === true` **and** a signed-URL probe succeeded |
| `active` | `disabled` | Doctor deactivation | None beyond authorization |
| `active` / `pending_verification` | `error` | Verification failure | Typed error code recorded |
| `error` | `pending_verification` | Doctor retry | None |
| `disabled` | `pending_verification` | Doctor re-enable | Requires re-verification; **never** straight to `active` |

**A dashboard toggle alone can never move a library to `active`.** This is the activation
gate required by N4 and by `isBunnyCatalogEntryUsable`.

### 2.3 Eligibility predicate (documented verbatim from code)

A library is usable only when **all** of the following hold:

```
document parses without error
AND status === "active"
AND token_auth_enabled === true
AND token_auth_verified === true
AND (emergency list is not engaged OR the library id is in the emergency list)
```

Any other combination is ineligible. There is no partial state.

---

## 3. `lecture_resources` — proposed field documentation

The collection is documented today with six fields (Lecture ID, Resource Type, Resource
URL, Thumbnail, Duration, Visibility). Production data already contains more. Three
fields must be documented because Option C depends on them.

| Field | Type | Purpose | Req. | Validation | Authorized writer | Authorized reader | Sensitivity | Authority |
|---|---|---|---|---|---|---|---|---|
| `bunny_video_id` | String \| null | Bunny video GUID inside the associated library | Conditional (required for `resource_type == "video"` that is meant to be playable) | bare GUID only — URLs and embed links are rejected | `associateBunnyVideoToLibrary` (after receipt verification) and legacy admin write paths | Server; the client already receives the video id when requesting playback | Low | **Authoritative** |
| `bunny_library_id` | String \| null | Which library owns `bunny_video_id` | Optional today; **must become required** for multi-library correctness | `^\d{1,20}$` when set | **Backend only.** Rules force `null` on client create and immutability on client update | **Server only — never projected to clients** | Medium (reveals topology) | **Authoritative** |
| `storage_provider` | String enum | Which provider holds a non-video resource (PDF/attachment/thumbnail) | Yes for non-video resources | `"bunny"` \| `"firebase"`; code defaults to `"firebase"` when absent | Upload callables | Server; may be needed by the client to choose a fetch path | Low | Informational |

**Justification for including `storage_provider`:** it is not an Option C invention. It is
already written by `uploadBunnyResource`, already read by `generateBunnyResourceUrl`
(L5549, L8585), already defaulted in `system_settings.default_storage_provider`, and
already documented in `06` §5 under FINAL_DECISIONS §15 — but absent from `05`. Leaving
it undocumented is the actual defect.

### 3.1 Observed but undocumented fields requiring a decision

These appear in real documents but are not part of this proposal:

| Field | Where observed | Note |
|---|---|---|
| `id` | Staging `lecture_resources` | Duplicates the document id; either legacy or redundant. Needs a decision: document it as legacy or stop writing it. |
| `section_id` | Staging `lecture_resources` | Not in Production rows. May be legacy from an earlier section model. Needs a decision. |
| `thumbnail_storage_provider` | Read by `index.ts` (L1932, L5740, L9043) | Exists in code but was not present in the sampled Production rows. Needs a decision: document it or remove the read. |

---

## 4. Audit records — `admin_audit_log`

**Do not create a new audit collection.** `admin_audit_log` already exists, is already
written by more than twenty callables, and already has the correct access model:

```
match /admin_audit_log/{auditId} {
  allow get, list: if isDoctor() || (isAdmin() && resource.data.actor_id == request.auth.uid);
  allow create, update, delete: if false;
}
```

Clients can never write or alter an audit record. That satisfies "audit records must be
server-generated and protected from client modification" with zero new surface.

### 4.1 Established field vocabulary (observed in existing writes)

| Field | Type | Meaning |
|---|---|---|
| `action` | String | Verb, e.g. `approve_student`, `content_create`, `default_storage_provider_set` |
| `entity` | String | Subject of the action |
| `target_id` | String | Affected document id |
| `actor_id` | String | Acting uid |
| `actor_role` | String | Role at the time of the action |
| `permission_basis` | String | Which permission justified it |
| `created_at` / `timestamp` | Timestamp | Server timestamp |

### 4.2 Proposed new action vocabulary for Option C

| Action | Emitted by | Required extra fields |
|---|---|---|
| `bunny_library_register` | Registration callable | `library_id`, `source`, `result` |
| `bunny_library_verify` | Verification job | `library_id`, `previous_status`, `new_status`, `reason_code` |
| `bunny_library_deactivate` | Deactivation callable | `library_id`, `previous_status`, `reason` |
| `bunny_library_reactivate` | Reactivation callable | `library_id`, `previous_status` |
| `bunny_credential_ref_set` | Registration / fallback callable | `library_id`, `credential_kind` (`stream_api_key` \| `token_key`) — **never the value, never a fingerprint of the value** |
| `bunny_video_associate` | Association callable | `library_id`, `video_id`, `resource_id`, `lecture_id`, `replaced` |
| `bunny_video_upload` | Upload callables | `library_id`, `resource_id`, `result` |
| `bunny_emergency_list_change` | Configuration change (if exposed) | `previous`, `next` |

**Forbidden in audit payloads:** secret values, secret versions' payloads, token keys,
signed URLs, and any string that could be used to reconstruct a credential.

---

## 5. Security Rules and index implications

| Item | Proposal | Change required? |
|---|---|---|
| `bunny_libraries` | Keep `allow read, write: if false` | **No change** — all access through callables |
| `lecture_resources` create | Keep `bunny_library_id == null` forced | **No change** |
| `lecture_resources` update | Keep `bunny_library_id` immutable | **No change** |
| `admin_audit_log` | Keep deny-write | **No change** |
| Composite index on `bunny_libraries` | Not required today (single-document reads, no compound query). If a Dashboard list ordered by `display_name` is added, it is a single-field order — still no composite index. If filtering by `status` **and** ordering by `last_verified_at` is added, one composite index would be required. | **Probably none**; confirm against the final query set |
| Index on `lecture_resources(bunny_video_id)` | Exists implicitly through the existing single-field index; playback queries by `bunny_video_id` already work in Production | **No change** |

This is a deliberately conservative result: Option C should ship with **zero Rules
changes**, which removes an entire risk class from the deployment gates.

---

## 6. Fields deliberately **not** proposed

| Rejected field | Why |
|---|---|
| `stream_api_key` / `token_key` values in the catalog | Forbidden — plaintext credentials in Firestore |
| `api_key_masked` or a key fingerprint | A fingerprint of a live credential is still credential-adjacent; it also invites comparison attacks. Not needed. |
| `created_at` / `updated_at` / `registered_by` on `bunny_libraries` | Would be genuinely useful, but the code does not write them today. Adding them to `05` without adding them to code would create a schema the system cannot honour. Who and when are captured in `admin_audit_log` instead. Revisit if the Owner wants them. |
| `health_score`, `video_count`, `last_error_message` | Invented. No code writes them; `last_error_code` covers the need without free text. |
| A separate `bunny_library_audit` collection | Duplicates `admin_audit_log` and creates a second access model to secure. |
| `is_default` on the catalog | The default library is currently a compiled constant plus an env var. Making it a catalog field is a real design option but must be decided (D-06), not slipped in as a schema detail. |

---

## 7. Migration and backfill

Current Production data:

| Metric | Value |
|---|---|
| Video resources | 13 |
| With `bunny_video_id` | 6 |
| Without `bunny_video_id` | 7 (1 deleted, 6 visible, 6 distinct lectures) |
| With `bunny_library_id` | 0 |
| `bunny_libraries` documents | 0 |

Proposed sequence (each step separately approved, none executed now):

1. **Register the existing Production library `736742`** as `source: "legacy_env"`, so the
   catalog reflects reality before any completeness requirement is imposed.
2. **Backfill `bunny_library_id = "736742"`** on the 6 rows that already have a verified
   `bunny_video_id`. This is the only backfill that can be justified by evidence.
3. **Do not backfill the 7 rows without `bunny_video_id`.** They have no video identity,
   no `resource_url`, no `storage_path`, and no thumbnail. Assigning them a library would
   be an assumption, not a migration.
4. **Decide the fate of those 7 rows** (1 deleted, 6 visible) separately. Until then, the
   migration gate "every video resource has a verified library mapping" **cannot pass**,
   and must not be treated as a release blocker in its absolute form.
5. Only after steps 1–2 may `bunny_library_id` be considered for a "required" constraint.

Backfill mechanics already exist in `bunny_library_migration.ts`
(`planBunnyLibraryBackfill`, `validateBunnyLibraryMapping`,
`evaluateBunnyLibraryBackfillWrite`, `buildBunnyLibraryBackfillBackup`) and require an
authorized entry point, not new logic.

---

## 8. Proposed `05` text shape

To match the document's existing convention, each collection is documented as
`## collection-name` + one sentence + `Contains` + `| Field | Type | Description |` table.
The proposal therefore adds:

- `## bunny_libraries` with the §2.1 table, plus a state-machine note and the eligibility
  predicate.
- Three rows added to the existing `## lecture_resources` table.
- A short `## admin_audit_log` section documenting the established field vocabulary and
  the rule that clients cannot write it.

A version-history entry is proposed for `05`:

```markdown
- **1.11** (2026-11-17): Added `bunny_libraries` (server-managed Bunny Stream library catalog), the Bunny fields on `lecture_resources` (`bunny_video_id`, `bunny_library_id`, `storage_provider`), and the `admin_audit_log` field vocabulary for library operations. No plaintext credentials are stored. Pending Teacher Database Change Approval.
```

---

## 9. Approval requirements

| Item | Requires |
|---|---|
| This schema text | **Teacher Database Change Approval** (the document's own gate) |
| Creating any `bunny_libraries` document in Production | Separate data-change approval + Gate 2 |
| Backfilling `bunny_library_id` | Separate data-migration approval |
| Any Rules or index change | Gates 3 / 4 (this proposal requests neither) |

---

## 10. Approval block

Proposed approval sentence:

> "I approve the `05 Database` schema addition as proposed: `bunny_libraries`, the three
> Bunny fields on `lecture_resources`, and the `admin_audit_log` vocabulary. This approval
> authorizes documentation only; it does not authorize creating catalog documents,
> backfilling data, or deploying anything."
