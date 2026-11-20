# ADR-010 — Workstream A: Bunny Video Resource Inventory

Date: 2026-11-12
Mode: READ-ONLY (Firestore REST GET + CDN HEAD/GET probes; no writes)
Scope: every `lecture_resources` document with `resource_type == "video"` in project `dr-tarek-platform`
Total video resources: **13**

## Method

1. Firestore REST `runQuery` on `lecture_resources` where `resource_type == "video"` (includes soft-deleted rows).
2. For each row: read its `lectures/{lecture_id}` document (title, status, is_deleted, subject_id) and `subjects/{id}` title.
3. Verify existence per library with an unauthenticated-where-possible GET of `/{video_id}/playlist.m3u8`:
   - Library `775315` — host `vz-c850a9e1-eb4.b-cdn.net` (its Pull Zone serves the HLS playlist without a token; see Workstream C).
   - Library `736742` — host `vz-c6abe953-876.b-cdn.net` with a locally reproduced directory-token signature (same algorithm as `hashVideoDirectoryToken`), because that zone enforces token authentication.
   - Both probes sent `Referer: https://dr-tarek-platform.web.app/` (the app's playback header).
4. A resource is `VERIFIED:<lib>` only when exactly one library returns `200 application/vnd.apple.mpegurl`; if both or none, it is `CONFLICT` / `MISSING`.

Library was **not** inferred from subject, grade, lecture title or ordering.

## Summary

| Classification | Count |
|---|---:|
| VERIFIED → library `775315` | 3 |
| VERIFIED → library `736742` | 3 |
| MISSING (no `bunny_video_id`) | 7 |
| CONFLICT | 0 |
| UNVERIFIED | 0 |

- All 6 resources that carry a Video ID are verified in exactly one library.
- 7 resources have an empty `bunny_video_id` (placeholder/test rows created by the authoring flow); they cannot play regardless of library.
- `6ffb23ad-f073-480d-9a68-43baaf9803d5` is shared by two different resource documents (duplicate Video ID).
- 3 resources belong to lectures that are `archived` **and** `is_deleted = true`, yet their resources are `is_deleted = false` and playable (`200`).

## Library A — `736742` (host `vz-c6abe953-876.b-cdn.net`)

| Resource ID | Lecture | Subject | Video ID | Status |
|---|---|---|---|---|
| `TCmr0PTvUwVYrOkLzKyd` | `JyBPO388gp70DYdbddB4` (archived, deleted) | محاسبة مالية | `6ffb23ad-f073-480d-9a68-43baaf9803d5` | VERIFIED |
| `iqfThonRycgDJ5xOdoKh` | `UG32WrckEwYnlCGA43Ux` (archived, deleted) | محاسبة مالية | `6ffb23ad-f073-480d-9a68-43baaf9803d5` | VERIFIED (duplicate ID) |
| `t9vPlLeXRlH5zG1UjPDE` | `9WJGceAhfYq6w0avq1RQ` (published) | أخلاقيات مهنة المحاسبة | `d0c31ca2-5bb0-4821-8f5d-64bde4bcc5de` | VERIFIED |

## Library B — `775315` (host `vz-c850a9e1-eb4.b-cdn.net`)

| Resource ID | Lecture | Subject | Video ID | Duration (HLS) | Status |
|---|---|---|---|---|---|
| `n2IpE7D3XslmNgBeeSeq` | `rtJ0JBuudn5beK6eB3Ue` (published) — المحاضرة الأولي | محاسبة مالية | `7ddd0e6e-a0ae-43f6-a11c-ff7ca5db1c31` | 35:54 | VERIFIED |
| `6xIQtr6XHq68FkHfkQ7C` | `nWwf4XGZJiQkUOofPhnQ` (published) — المحاضرة الثانية | محاسبة مالية | `94710db9-8bd4-4c8e-ab21-4d68913dd9be` | 68:26 | VERIFIED |
| `mKzGszf8oiMQjkm0WzxW` | `QTAPgWN1vQcpZ8sgPjId` (published) — المحاضرة الثالثة | محاسبة مالية | `4dd8a3b0-4363-4f39-a21d-cb6bb7c2b99c` | 39:20 | VERIFIED |

Identity evidence for `7ddd0e6e…`: Bunny dashboard search by GUID returns exactly one video titled
`محاسبة مالية المحاضرة الأولي - bunny.mp4`, duration `00:35:54`, matching the HLS-derived duration (2154 s).

## Missing (no Video ID) — 7 resources

| Resource ID | Lecture | Lecture state | Resource deleted | Visible |
|---|---|---|---|---|
| `1Lv5zsow5Ap5GJNaArcP` | `UNQPFUbQwwggZTH0JAj4` (تجربة اخلاق) | published | false | true |
| `Ey3Nqi1zgTQ8hOpXOcYv` | `CvhGSQyEGAZfQ3NEQjK1` | archived + deleted | false | true |
| `ICz33MA21JQSy9e8OJ7h` | `CvhGSQyEGAZfQ3NEQjK1` | archived + deleted | true | false |
| `YmV7LRp9diX9kUCn4PRT` | `cYI0V5VCA2yHVAJgkhPH` (تحربة محاسبة تكاليف) | published | false | true |
| `ju1taw2UbenaC6FIrgFV` | `CAjfNajyccdQpsAwSE9L` (تجربة شركات) | published | false | true |
| `qctAJDSdM9sxND9e2Ehq` | `J94QootP8CDYWBrwD28` (تجربة مشاكل محاسبية) | published | false | true |
| `yjwx89srQkzr3d4PKdGe` | `lD3HNpB1mawsM0SAxI9H` (تجربة محاسبة حكومية) | published | false | true |

These are authoring/test placeholders: they produce a resource row with `bunny_video_id: ""`.
The Flutter entity treats them as non-video (`isVideo == false`), so playback fails closed with
"No published video source found for this lecture." — not a 404.

## Security-relevant observations (not fixed)

1. **Archived/deleted lectures remain issuable.** `TCmr0PTvUwVYrOkLzKyd` and `iqfThonRycgDJ5xOdoKh`
   belong to lectures with `status = archived`, `is_deleted = true`, yet their resources are live and the
   video plays (200). Both `generateBunnySignedUrl` (lecture existence check only) and
   `getLectureResources` (existence check only) omit publication/deletion gates. This is explicitly
   out of scope for ADR-010 and requires separate approval.
2. **Duplicate Video ID** (`6ffb23ad…` on two resources) — identity is resolved by `(lecture_id, video_id)`
   in issuance, so no cross-lecture leak, but legacy lookups without `lectureId` fail closed as ambiguous.
3. **7 rows with empty Video ID** pollute the inventory/`first_video` selection logic; no cleanup authorized.

## Evidence summary

- Firestore REST queries (read-only) — 13 video resources + linked lectures/subjects.
- Bunny Stream API `GET /library/736742/videos/{id}` (library-scoped key, read-only): 404 for the three
  775315 videos, 200 for library-736742 videos.
- CloudFront-style CDN probe on both Pull Zones with the app `Referer`.
- Bunny Dashboard (authenticated browser, read-only): library `775315` name, 74 videos, pull-zone host
  `vz-c850a9e1-eb4.b-cdn.net`, and GUID search for `7ddd0e6e…`.

No secret values were read into these reports.
