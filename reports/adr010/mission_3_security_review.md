# ADR-010 — Mission 3 Security Review

Scope: picker wiring, emulator CI, pre-write validation. Read-only review; no production
access, no deployment, no secret change in this mission.

## 1. Client authority

- The Dashboard now routes library selection through `BunnyLibrarySelection`, whose
  `libraryIdForWrite` returns an id **only when valid**, otherwise the stored value
  (null for new/legacy). A rejected choice cannot reach Firestore.
- A changed Video ID sets `libraryReviewRequired` and keeps the stored association — no
  silent re-association, no guessed library.
- No signing secret, template, pull zone or secret-manager reference is representable in
  the catalog (`toJson()` exposes `id`/`displayName`/`isAvailable`/`isSelectable` only).
- The Dashboard still never calls Bunny directly and never constructs a playback URL.

## 2. Server validation boundary

- `validateBunnyVideoAssociation` is doctor-only (`requireDoctor`), so students cannot
  probe library contents or enumerate Video IDs.
- The library id is resolved through the server registry; `775315` stays
  `library_not_activated`; unknown ids are `unknown_library`; missing credentials are
  `incomplete_configuration`. There is no fallback to the default library.
- The Stream API key is used server-side only and never returned; the response shape is
  asserted closed in the emulator suite (`apiKey`, `AccessKey`, token, secret absent).
- `unavailable` (timeout / 5xx / 401 / 403 / unparseable body) is never reported as
  `verified`, so a broken integration cannot mint a passing verdict.
- Verdict caching uses `libraryId:videoId`, so one library's verdict can never be served
  from another library's cache entry.
- Receipts are HMAC-SHA256 over `libraryId\nvideoId\nexpiresAt` with the server token key,
  compared in constant time, and expire after 10 minutes. A receipt for another library or
  video, a tampered signature, or an expired receipt is rejected (tested).

## 3. Persistence enforcement — explicit limitation

The validation verdict is **not yet enforced at write time**. Client-side Firestore writes
would need one of: a pre-save callable, a server-side write callable that consumes the
receipt, or a trigger guard. All three require deployment (prohibited) and/or an approved
design. This is documented as PARTIAL in `pre_write_metadata_validation.md`; it is not
claimed as enforced.

## 4. CI

- The new job uses the isolated `demo-tarek-platform` project with fake fixture secrets in
  `env:`; no production credential, service account or secret is read.
- `--only auth,firestore,functions`; no hosting/firestore deploy, no `firebase deploy`.
- `BUNNY_ACTIVE_LIBRARY_IDS` is deliberately unset, so `775315` remains inactive in CI.
- Logs contain only verdict/denial lines; no secret is printed by the suites.

## 5. Regression posture

- No authorization logic changed: authentication, per-lecture deny, subject access,
  subscription, Feature Matrix, device binding, takeover, rolling window and quality code
  are untouched. The emulator suite re-asserts denial paths (unauthenticated,
  non-entitled subject, rolling window) and the doctor gate.
- PDF / external-link resources remain association-free (widget + persistence tests).
- Legacy rows keep reading and editing as legacy; no association is invented.
- No signed playback URL is persisted anywhere.

## 6. Library 775315

Still inactive: no allow-list entry, no catalog selectability, validation returns
`inactive_library`, issuance returns `library_not_activated`. Its Bunny settings were not
touched in this mission.

## 7. Pre-existing issues unchanged (reported, not fixed)

1. `775315` Pull Zone serves unsigned HLS.
2. Archived / `is_deleted` lectures remain issuable (out of ADR-010 scope).
3. Duplicate `6ffb23ad…` Video ID across two resources.
4. Seven placeholder video resources with empty `bunny_video_id`.
5. `BUNNY_STREAM_API_KEY` still a plain env var rather than a Secret Manager secret.

## 8. Verdict

No security regression. The new surface is doctor-only, fail-closed, secret-free and
cache-isolated. The single open item is the deliberate absence of write-time enforcement,
which needs a deployment decision, not more local code.
