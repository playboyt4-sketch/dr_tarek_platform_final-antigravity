# ADR-010 - Production Bunny Playback HTTP 404 Diagnosis

- Date: 2026-11-19
- Environment: Production (`dr-tarek-platform`)
- Authorized attempt: student `vnnSK7Qg5aY2JPOWLMkAvg1eVGl2`, resource `n2IpE7D3XslmNgBeeSeq`,
  lecture `rtJ0JBuudn5beK6eB3Ue`, video `7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31`
- Reported client error: `PlatformException(VideoError, Failed to load video: The requested URL
  was not found on this server. HTTP 404: File Not Found)`
- Status: **ROOT CAUSE IDENTIFIED - NOT FIXED** (no successful playback has been observed)

## Scope compliance

No playback attempt was repeated. No Firestore write, no Bunny configuration change, no upload,
move or association, no deployment, no code change, no secret value read or printed. All checks
below are reads (Firestore REST, Cloud Logging, gcloud describe metadata, public HTTP GET/HEAD).

---

## A. Endpoint that returned 404

Shape of the URL issued at `2026-11-18T19:06:32.617Z` (token redacted):

```
https://vz-c6abe953-876.b-cdn.net/bcdn_token=HS256-<REDACTED>&token_path=%2F7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31%2F&expires=<REDACTED>/7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31/playlist.m3u8
```

| Element | Value | Basis |
|---|---|---|
| Host | `vz-c6abe953-876.b-cdn.net` | pull zone of library `736742` (default library template) |
| Path | `/{videoId}/playlist.m3u8` | `BUNNY_PLAYBACK_URL_TEMPLATE` + `index.ts:5039-5044` |
| Token | in-path directory token `bcdn_token=HS256-...` + `token_path` + `expires` | `index.ts:1601-1613`, `5039-5044` |
| Format | HLS master playlist (not MP4) | iOS client sends no `format`; `video_source_resolver.dart:320-332` |
| Library id in URL | none (library is implied by the host) | Bunny design |

The failing resource is the **master HLS playlist** `/{videoId}/playlist.m3u8`. It is the first
resource the player requests; segments and rendition playlists were never reached.

## B. HTTP evidence and timestamps

Server side (Cloud Logging, `generatebunnysignedurl`, Production):

```
2026-11-18T19:06:26.923Z  Callable request verification passed
2026-11-18T19:06:27.997Z  generateBunnySignedUrl identity requestedLecture=rtJ0Jbuudn5beK6eB3Ue
                          resolvedLecture=rtJ0Jbuudn5beK6eB3Ue subject=6vqiLbU4BUii3Rzp5y9t
                          video=7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31 tier=full
                          window=not_enforced library=736742
2026-11-18T19:06:28.049Z  analytics_events "Open Video" written
2026-11-18T19:06:32.117Z  Callable request verification passed
2026-11-18T19:06:32.617Z  same identity line (retry), library=736742
2026-11-18T19:06:32.664Z  analytics_events "Open Video" written (retry)
```

The callable returned **HTTP 200 / success** both times: signing succeeded, the failure happened
later, in the player, against the CDN.

Client side: AVPlayer reported `HTTP 404: File Not Found` immediately after the second issuance
(~`19:06:32.7Z`).

CDN side: Bunny CDN access logs are not shipped to Cloud Logging and are only readable with a
Bunny account/API key (not accessed). The origin verdict is therefore reproduced
non-destructively:

| Probe (read-only) | Result | Meaning |
|---|---|---|
| `GET https://vz-c6abe953-876.b-cdn.net/<guid>/playlist.m3u8` (no token, existing video) | `403` | edge token gate runs **before** origin lookup |
| same URL with a **random** GUID (no token) | `403` | unknown paths are also blocked at the edge, never 404 |
| `GET https://iframe.mediadelivery.net/embed/736742/7ddd0e6e-...` | `200`, page `<title>404</title>` | library `736742` reports the video as **not found** |
| `GET https://iframe.mediadelivery.net/embed/775315/7ddd0e6e-...` | `200`, 50,798-byte player shell | video **exists** in `775315` |
| `GET https://iframe.mediadelivery.net/embed/736742/6ffb23ad-...` | `200`, page `<title>403</title>` | video exists, embedding disabled |

Consequence: a `403` can only come from the edge; the observed `404` is therefore produced
**after** the token was accepted, i.e. by the Stream origin for library `736742`.

## C. Exact reason for the 404

**Library / video mismatch.** The signed URL is scoped to the pull zone of library `736742`, but
video `7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31` lives in library `775315` (pull zone
`vz-c850a9e1-eb4.b-cdn.net`). Bunny Stream resolves the GUID inside the library behind the
requested host, does not find it, and answers `404` for the master playlist.

Ruled out:

- **Bunny video lookup failure for a real video**: the video exists, but in another library.
- **HLS playlist / segment failure**: the playlist itself is missing; nothing deeper was requested.
- **MP4 / direct-play**: not used on iOS; no `format=mp4` in the client payload.
- **Malformed signed URL**: the shape matches Bunny's documented directory-token format.
- **Bad signature or wrong key**: a bad token yields `403` at the edge, not `404`.

Why the wrong library was selected: `lecture_resources/n2IpE7D3XslmNgBeeSeq` has **no
`bunny_library_id`** field. Because it was created `2026-11-04T19:53:28.371Z` (before the
`2026-11-13` cutover), `mayResolveBunnyLibraryForPlayback` allows the legacy fallback and
`resolveBunnyLibraryForResource({storedLibraryId: null})` returns `legacy_default` ->
`DEFAULT_BUNNY_LIBRARY_ID = "736742"` (`bunny_library_registry.ts:35,344-358`). Production has no
`BUNNY_DEFAULT_LIBRARY_ID`, no `BUNNY_ACTIVE_LIBRARY_IDS` and an empty `bunny_libraries`
collection, so nothing overrides that default.

## D. Does the video exist in the expected library (`736742`)?

**No.** It exists in `775315`.

Full census of Production `lecture_resources` videos (non-destructive embed probe, read-only):

| Video ID | Home library | Probe on `736742` | Probe on home library |
|---|---|---|---|
| `6ffb23ad-f073-480d-9a68-43baaf9803d5` | `736742` | `403` (exists, embed off) | - |
| `d0c31ca2-5bb0-4821-8f5d-64bde4bcc5de` | `736742` | `403` (exists, embed off) | - |
| `4dd8a3b0-4363-4f39-a21d-cb6bb7c2b99c` | `775315` | `404` | player shell, `vz-c850a9e1-eb4` |
| `7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31` | `775315` | `404` | player shell, `vz-c850a9e1-eb4` |
| `94710db9-8bd4-4c8e-ab21-4d68913dd9be` | `775315` | `404` | player shell, `vz-c850a9e1-eb4` |
| `47561140-5966-4e0f-8851-83c78ce5bb92` | `780700` | `404` | player shell, `vz-b5f9cb68-f06` |

**4 of the 6 Production video rows point to videos that the Production default library cannot
serve.** `780700` is the Staging test library (`bunny_libraries/780700`, "DrTarek Staging Test
Library", `status=active`), and today's Production row (`47561140`, created
`2026-11-18T16:03:04Z`) points into it - a separate governance finding.

The `2026-11-11T13:27:31Z / 13:27:37Z` log lines recorded earlier were **issuance only**; they
never proved playback. No `lecture_progress` document exists for lecture
`rtJ0JBuudn5beK6eB3Ue`, and the analytics show the same "two issuances a few seconds apart"
retry pattern on both dates, so there is no evidence this lecture ever played.

## E. Was the signed URL constructed correctly?

**Yes - for the library that was selected; the selected library is wrong.**

- Token construction (`index.ts:1601-1613`): `HS256-` + `base64url(HMAC-SHA256(secret,
  scope + expires + "token_path=" + scope))`, embedded as
  `/bcdn_token=...&token_path=<enc>&expires=<exp>` before the path - BunnyWay
  TokenAuthentication, directory mode. This is the documented format and is required so that
  relative HLS children inherit authentication.
- Key: secret `BUNNY_TOKEN_KEY` v3, the token key of the **default** library `736742`.
  The edge accepted the signature (it returned `404`, not `403`), which proves the key and
  algorithm match the library that was selected.
- Template: secret `BUNNY_PLAYBACK_URL_TEMPLATE` v2, host `vz-c6abe953-876.b-cdn.net`.
- The URL was therefore valid, correctly signed, and pointed at the wrong library.

## F. Smallest correct fix

The rule to restore is: **the library used for signing must be the library that owns the video.**
Two viable shapes; the choice between them is a governance decision (open item D-06: default
library vs. allow-list).

1. **Per-lecture, no secrets, no deploy (smallest).**
   Upload the source of `7ddd0e6e-...` into `736742`, then set
   `lecture_resources/n2IpE7D3XslmNgBeeSeq.bunny_video_id` to the new GUID.
   Cost: one upload + one field update. Does not fix the other three rows.

2. **Structural (correct).**
   Activate `775315` in Production (`BUNNY_775315_TOKEN_KEY`,
   `BUNNY_775315_STREAM_API_KEY`, `BUNNY_775315_PLAYBACK_URL_TEMPLATE`, add `775315` to
   `BUNNY_ACTIVE_LIBRARY_IDS`), then backfill `bunny_library_id` on the three `775315` rows,
   and move the `780700` row's content out of the Staging library. Requires secret work and a
   deployment, so it is a governed change, not a hotfix.

Either way, add the authoring-time guard that already exists and is unused by the deployed
dashboard: `validateBunnyVideoAssociation` must run before a video row is saved, so a
(library, video) mismatch can never reach playback.

Do **not** "fix" this by pointing the row at a different video, and do not enable `775315`
without the owner's decision on D-06.

## G. Regression test proving the fix

1. Save-time guard: attempting to save `n2IpE7D3XslmNgBeeSeq` with
   `bunny_library_id=736742` and video `7ddd0e6e-...` must be rejected by
   `validateBunnyVideoAssociation` (`video_not_in_library`), and accepted with the owning library.
2. Playback proof (one controlled attempt, after authorization): the callable must log
   `library=<owning library>`, the issued URL must return `200` for `playlist.m3u8` **and** for
   at least one rendition playlist and one segment, `lecture_progress` must be created for the
   lecture, and the iOS player must render frames. Only then is the issue "fixed".
3. Negative test: a row whose video lives in a non-active library must fail with an explicit
   error at authoring time - never with a silent CDN `404` at playback.

## Observed side effects of the authorized attempt (read-only verification)

| Collection | Document | Change |
|---|---|---|
| `analytics_events` | `KcGaPCVuSc0DAr2uqWJW` | `Open Video`, `2026-11-18T19:06:28.049999Z` |
| `analytics_events` | `l3jiuISdi0EXowSdWbbb` | `Open Video`, `2026-11-18T19:06:32.664201Z` |
| `subject_device_authorizations` | `vnnSK..._6vqi..._d35bf897...` | `last_used_at = 2026-11-18T19:06:32.559Z` |
| `devices` | `tRcMrhcjVE0VY4X4LnOm` (`1854ce5e-...`) | `last_login = 2026-11-18T19:06:32.469Z` |
| `devices` | `TLiFaTjPx1BBN33cyfTL` (`86b9e4f4-...`) | `last_login = 2026-11-18T19:06:19.437Z` (login) |

No `video_watch_windows` document, no `lecture_progress` document and no `playback_sessions`
document were created - consistent with a failure before the first segment.
