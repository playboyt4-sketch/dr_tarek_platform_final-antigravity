# ADR-010 — Workstream B: Library Configuration Readiness

Date: 2026-11-12
Mode: READ-ONLY (metadata only; no secret values read or printed, no secret created or modified)

## Configuration surfaces inspected

| Surface | How inspected | Result |
|---|---|---|
| Cloud Function env vars (deployed `generateBunnySignedUrl`) | `gcloud functions describe --gen2` (names only) | `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID` present as **plain environment variables**, not Secret Manager |
| Secret Manager secret names | `gcloud secrets list` (names only) | `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_PASSWORD`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_TOKEN_KEY` |
| Secret versions | `gcloud secrets versions list` (metadata) | `BUNNY_TOKEN_KEY` has at least one ENABLED version (values never fetched) |
| Playback template (structure only) | value piped through a script that printed hostname + path shape only | `vz-c6abe953-876.b-cdn.net` + `/{video_id}/playlist.m3u8` |
| Library metadata API | `GET https://video.bunnycdn.com/library/{id}` with existing key | 200 for `736742`, 401 for `775315` |
| Pull-zone hostnames | Bunny Dashboard (authenticated, read-only) | `736742 → vz-c6abe953-876`, `775315 → vz-c850a9e1-eb4` |

## Readiness matrix

### Library `736742` (currently the only configured library)

| Required item | Status | Evidence |
|---|---|---|
| Bunny Stream Library ID | **READY** | `BUNNY_STREAM_LIBRARY_ID=736742` on the deployed function |
| Stream API credential | **READY (weak placement)** | `BUNNY_STREAM_API_KEY` exists as a plain env var; verified `GET /library/736742` → 200. Not in Secret Manager — violates ADR-010's "secrets remain server-side in Secret Manager" requirement |
| Pull Zone hostname | **READY** | `vz-c6abe953-876.b-cdn.net` (from `BUNNY_PLAYBACK_URL_TEMPLATE`) |
| Token Authentication signing credential | **READY** | `BUNNY_TOKEN_KEY`; signed directory-token URL returns 200 on a known video |
| Playback URL template | **READY** | `https://vz-c6abe953-876.b-cdn.net/{video_id}/playlist.m3u8` |
| Hotlink / Referer requirement | **READY** | 403 with empty Referer, 200 with `https://dr-tarek-platform.web.app/` (signed) |
| Metadata API access (poster/HQ preview) | **READY** | library API 200; `thumbnailFileName` resolvable |

### Library `775315` (content library)

| Required item | Status | Evidence |
|---|---|---|
| Bunny Stream Library ID | **MISSING** | no server-side configuration references `775315` |
| Stream API credential | **MISSING** | existing key returns **401** for `775315` (library-scoped key) — a credential for one library does not authorize another |
| Pull Zone hostname | **VERIFIED (not configured)** | `vz-c850a9e1-eb4.b-cdn.net` confirmed from the dashboard |
| Token Authentication signing credential | **MISSING** | no key configured; zone appears **not** to enforce token auth (see Workstream C) |
| Playback URL template | **MISSING** | no template for this zone |
| Hotlink / Referer requirement | **READY** | accepts `https://dr-tarek-platform.web.app/`; rejects empty Referer (403) |
| Metadata API access (poster/HQ preview) | **MISSING** | 401 with the existing key |

### Additional libraries observed on the account (not in ADR-010 scope)

`DrTarek-Staging-Test` (0 videos), `الفرقة الثانية` (0), `دكتور عبد الرحيم` (18). They must not be
configured unless the Platform Owner adds them to the ADR scope.

## Consequences for implementation

1. Backend resolution cannot be completed until `775315` has (a) a Stream API key, (b) a token-signing
   key **if** the zone is switched to token auth, and (c) a configured playback template referencing
   its Pull Zone.
2. `BUNNY_STREAM_API_KEY` should move into Secret Manager as part of the implementation (ADR-010
   requires server-managed secrets). This is a configuration change and therefore **requires the
   Platform Owner's action/approval**; it is not performed here.
3. The current implementation resolves metadata library and playback zone independently, from two
   different sources (env library id + template secret). Any per-library registry must bind them
   together, otherwise posters can come from one library while playback comes from another.
4. No secret value was read into this report; only names, presence, HTTP authorization outcomes and
   hostnames are recorded.
