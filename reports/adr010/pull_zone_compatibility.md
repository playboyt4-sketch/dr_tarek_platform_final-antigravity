# ADR-010 — Workstream C: Pull Zone Compatibility

Date: 2026-11-12
Mode: READ-ONLY GET requests only. No settings changed, no signed URLs issued to students, no device binding.

## Zones under test

| Library | Pull Zone host | Auth model observed |
|---|---|---|
| `736742` | `vz-c6abe953-876.b-cdn.net` | Token Authentication enforced (unsigned → 403) |
| `775315` | `vz-c850a9e1-eb4.b-cdn.net` | **No token enforcement observed**; hotlink filter only |

All tests used `GET /{video_id}/playlist.m3u8` and `GET /{video_id}/thumbnail.jpg`.

## Test A — Library `736742` (configured, control)

| Case | Referer | Result |
|---|---|---|
| Signed directory token, known video `6ffb23ad…` | app Referer | **200**, `application/vnd.apple.mpegurl` |
| Signed directory token, same video | no Referer | 403 |
| Unsigned, same video | app Referer | 403 |
| Signed directory token, `7ddd0e6e…` (775315 video) | app Referer | **404** |
| Signed directory token, random GUID (control) | app Referer | **404** |

Interpretation: signing key, template host, path shape and Referer are all correct for `736742`;
404 is exclusively "resource not in this library".

## Test B — Library `775315` (target)

| Case | Referer | Result |
|---|---|---|
| `7ddd0e6e…/playlist.m3u8` unsigned | `https://dr-tarek-platform.web.app/` | **200**, `application/vnd.apple.mpegurl`, 622 b |
| `94710db9…/playlist.m3u8` unsigned | app Referer | **200**, 774 b |
| `4dd8a3b0…/playlist.m3u8` unsigned | app Referer | **200**, 621 b |
| Same three, no Referer | — | 403 (`text/html`) |
| `7ddd0e6e…/thumbnail.jpg` | app Referer | 200 `image/jpeg` (53 KB) |
| `94710db9…/thumbnail.jpg` | app Referer | 404 (no custom poster; playback unaffected) |
| `4dd8a3b0…/thumbnail.jpg` | app Referer | 200 `image/jpeg` (51 KB) |
| Known-good dashboard GUID `010e8899…` | app Referer | 200 |

HLS variants confirmed by parsing the master playlists:
`7ddd0e6e` 4 renditions (240p–720p, 35:54), `94710db9` 5 renditions (240p–1080p, 68:26),
`4dd8a3b0` 4 renditions (240p–720p, 39:20). Variant playlists and segments served 200.

**Referer answer: YES — the second Pull Zone accepts `https://dr-tarek-platform.web.app/` and rejects an empty Referer.**

## Test C — Signed URL on `775315` — NOT VERIFIED

Impossible without the zone's token-signing key. Two consequences:

1. If the zone is left without token authentication (current state), signed and unsigned URLs behave the
   same and playback will work — but **content protection is GUID-secrecy only**.
2. If token authentication is enabled later on that zone, a matching key must be provisioned before
   playback can work. A key from `736742` must not be assumed to work for `775315`.

## Exact failure classification (production incident)

| Layer | Verdict |
|---|---|
| Authentication (token signature) | PASS — the token is accepted by the configured zone |
| Authorization (subscription/plan/device) | PASS — issuance succeeded; the upgrade wall disappeared after Phase 1 |
| Resource existence | **FAIL** — the GUID is not present in the configured library |
| Configuration | **MISMATCH** — playback template/zone points at library `736742`, content lives in `775315` |

## Security finding (reported, not fixed)

Library `775315`'s Pull Zone serves HLS playlists, variant playlists and media segments to **unsigned**
requests whenever a non-empty `Referer` is supplied. Anyone who knows a Video GUID and sends any
Referer can stream the content outside the platform, bypassing subscription and device authorization.

Enabling token authentication on that zone (and configuring its key per ADR-010) is required to restore
the protection level the platform assumes. This is a Bunny configuration change and is **not** performed
here; it needs the Platform Owner's explicit approval.

## Missing prerequisites for full validation

- Stream API key for `775315` (poster/preview metadata).
- Token-signing key for `775315` **if** token auth is to be enabled on its zone.
- Confirmation of the intended protection model for the legacy library (token auth on/off).
