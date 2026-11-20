# ADR-010 Option C — Cross-Document Governance Proposal

Status: **PROPOSED — awaiting Platform Owner approval. Not applied.**
Date: 2026-11-17
Targets: `04_FEATURES.md` (2.0 Approved), `06_FIREBASE_ARCHITECTURE .md` (1.4 Draft),
`07_FLUTTER_ARCHITECTURE.md` (1.3 Draft), `08_DEVELOPMENT_STANDARDS.md` (1.3 Draft),
`09_TASKS .md` (1.3 Draft), `11_Assets.md` (1.2 Draft), `13_Releases.md` (1.1 Draft)

> Proposal file only. No target document is modified.

---

## 1. Verified contracts these proposals must match

Every name below was read from the repository, not inferred.

| Callable | Request | Returns | Notes |
|---|---|---|---|
| `generateBunnySignedUrl` | `{videoId, quality?, subjectId?, deviceId, lectureId?}` | signed URL + expiry + quality | `videoId` must be a bare GUID; URLs rejected; `deviceId` required; resolves the library from the matched `lecture_resources` row |
| `getLectureResources` | lecture/resource scope | resource list | resolves per-resource library and storage provider |
| `getSectionDisplayMedia` | section scope | media list | same resolution |
| `generateBunnyResourceUrl` | storage resource scope | signed Storage URL | Bunny Storage only (PDF/attachment) |
| `validateBunnyVideoAssociation` | `{libraryId, videoId, resourceId?, lectureId?}` | `{…, receipt}` | receipt TTL **600 s**; verifies the video with **that library's** key |
| `associateBunnyVideoToLibrary` | `{resourceId, lectureId, libraryId, videoId, replaceVideo?}` | association result | verifies receipt, then writes |
| `listEligibleBunnyLibraries` | — | `{libraries: [{libraryId, displayName}]}` | client projection only |
| `uploadBunnyResource` | file + storage scope | Storage result | **Bunny Storage only** — not Stream video |
| `deleteBunnyResource` | resource scope | delete result | Bunny Storage only |

**There is no Stream video upload callable.** This is the largest gap between the
documented system and the implemented system, and it is why `06`, `07` and `09` must all
change together rather than one at a time.

### 1.1 Signing-duration resolution

Three different durations exist in the code, and three different numbers exist in the
documents. The proposal adopts the **implemented** values and states them once:

| Artifact | Duration | Source of truth |
|---|---|---|
| Video playback signed URL | **3600 s** | `generateBunnySignedUrl` default `expiresInSeconds = 3600` |
| Bunny Storage resource URL (PDF/attachment) | **300 s** | `buildBunnyResourceAccessUrl` default |
| Association receipt | **600 s** | `BUNNY_VALIDATION_RECEIPT_TTL_SECONDS = 600` |

This closes `09` L141 ("suggested: 5 minutes per request") as **not adopted** for video,
and confirms `07`'s "1 hour" as correct.

---

## 2. `04_FEATURES.md` (Approved — requires approval)

### 2.1 Feature 05 (Video Player) — add the library dimension

Insert after the Purpose paragraph:

```markdown
### Library Resolution (ADR-010)

A video belongs to exactly one Bunny Stream library. The library is **not** chosen by the
student and is never sent to the client. When a student opens a video, the backend:

1. resolves the `lecture_resources` row for the requested video;
2. resolves that row's library from the server-managed catalog;
3. rejects the request if the library is unknown, inactive, unverified, or blocked by the
   emergency list;
4. issues a signed URL for that library only.

There is **no cross-library fallback**. If the associated library cannot serve the video,
the student receives a typed failure, not a stream from a different library.

**Acceptance criteria**
- A video associated with library A never plays from library B.
- A library that is deactivated stops serving immediately.
- The client never receives a library id, host, or credential.
- Existing single-library behaviour is unchanged until the catalog is populated.
```

### 2.2 New feature: Library Registration and Management (Doctor)

Proposed new sub-section under Feature 05 (not a new numbered feature, to avoid
renumbering the approved document):

```markdown
### Library Registration and Management (Doctor only)

**Actors:** Doctor (Platform Owner).
**Entry point:** Dashboard → Video Libraries.

**Main flow**
1. Doctor enters a Bunny library id and display name.
2. Backend validates the id format, confirms it is not already registered, and confirms
   credentials exist for that id in Secret Manager.
3. Backend creates the catalog entry with status `pending_verification`.
4. Backend verifies CDN Token Authentication is enabled and that a signed URL actually
   plays; only then does the library become `active`.
5. Every step writes an audit record.

**Alternative flow — automatic verification unavailable**
If the backend cannot read or enable Token Authentication, the Doctor may supply the
token key once through a masked field. The key goes directly to Secret Manager, is never
returned, and the library still requires verification before activation.

**Business rules**
- The platform never creates a Bunny library.
- A library that is not `active` + verified is never offered in any picker.
- Deactivation takes effect immediately and is audited.
```

### 2.3 New sub-flow: Video upload

```markdown
### Video Upload (Doctor or ADMIN_CONTENT)

1. The author selects a lecture and a library from the server-provided eligible list.
2. The backend creates the video in that library and returns a short-lived upload
   authorization bound to that video and that library.
3. The client uploads; the browser never receives a library API key.
4. The backend verifies completion and the resulting video identity before the video can
   be associated with the lecture.
5. Failed or abandoned uploads leave no associable state.
```

**Status:** the upload mechanism itself is an unresolved capability (U-05/U-06). This
feature text describes required behaviour, not a chosen mechanism.

---

## 3. `06_FIREBASE_ARCHITECTURE .md` (Draft)

### 3.1 Replace §6.4

**Current** documents `generateSignedVideoUrl` receiving `video_id`.

**Proposed replacement:**

```markdown
## 6.4 Bunny CDN - Signed URL Generation

Per FINAL_DECISIONS Section 4, as amended for ADR-010 Option C.

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `generateBunnySignedUrl` | Callable, invoked when a student opens a video | Receives `{videoId, deviceId, lectureId?, subjectId?, quality?}`; validates the caller's entitlement, device authorization and lecture access; resolves the resource's library from `bunny_libraries`; rejects unknown, inactive, unverified or emergency-blocked libraries; returns a signed URL for that library only. `videoId` must be a bare GUID — URLs are rejected. |
| `listEligibleBunnyLibraries` | Callable, Dashboard | Returns `{libraries: [{libraryId, displayName}]}`. No host, pull zone, credential reference or verification stamp is ever returned. |
| `validateBunnyVideoAssociation` | Callable, authoring | Verifies, using that library's own Stream key, that the video exists in that library. Returns a short-lived receipt (600 s). Writes nothing. |
| `associateBunnyVideoToLibrary` | Callable, authoring | Verifies the receipt, then writes `bunny_video_id` and `bunny_library_id` on the resource. |

**Flow**
1. A video is uploaded to, or registered in, a specific library.
2. The backend verifies the video belongs to that library and issues a receipt.
3. The association is written only after receipt verification.
4. The app calls `generateBunnySignedUrl`; the library is resolved server-side.
5. The signed URL expires after 3600 s; a new one is issued on each open.
6. The student never sees the raw URL, the library id, or any credential.

**Non-goals:** the platform never creates Bunny libraries; the client never selects a
library for playback.
```

### 3.2 Add a catalog and isolation subsection

```markdown
### 6.4.1 Library Catalog and Credential Isolation

`bunny_libraries/{libraryId}` is the non-secret source of truth. It stores ids, host,
booleans, verification stamps, error codes and Secret Manager **names** only.

Credentials are stored in Secret Manager under deterministic names derived from the
library id: `BUNNY_<libraryId>_STREAM_API_KEY` and `BUNNY_<libraryId>_TOKEN_KEY`. A
request concerning one library may read only that library's credentials. A missing
credential is an error, never a reason to fall back to another library.

Eligibility requires `status === "active"` **and** `token_auth_enabled` **and**
`token_auth_verified`. Any other state fails closed.

`BUNNY_ACTIVE_LIBRARY_IDS` is a legacy-named **emergency eligibility list**: it can only
remove libraries from eligibility, never add them. An unset value means the list is not
engaged; a malformed value denies every library.
```

### 3.3 Correct the stale "resolved" checkbox

`06` L339 marks the token-signing question resolved against `generateSignedVideoUrl`.
Replace the function name with `generateBunnySignedUrl` and note that the library
dimension was added by ADR-010.

---

## 4. `07_FLUTTER_ARCHITECTURE.md` (Draft)

### 4.1 §16.2 — replace the callable name and contract

**Current:** `BunnyCdnRemoteDataSource calls Cloud Function: getSignedVideoUrl` and
`GetSignedVideoUrlUseCase(lectureId, quality)`.

**Proposed:**

```markdown
Student opens lecture video
         ↓
GetSignedVideoUrlUseCase(lectureId, videoId, quality)
         ↓
BunnyCdnRemoteDataSource calls Cloud Function: generateBunnySignedUrl
   request: {videoId, deviceId, lectureId, subjectId?, quality?}
         ↓
Cloud Function:
  1. Verifies the caller's entitlement, device authorization and lecture access
  2. Resolves the resource's library from the server catalog (never from the client)
  3. Rejects unknown / inactive / unverified / emergency-blocked libraries
  4. Generates a signed URL for that library only (expires in 3600 s)
  5. Returns {url, expiresAt, quality}
         ↓
Flutter feeds the URL to the video player
```

Keep the existing 1-hour statement: it matches the implementation. Add:

```markdown
The client never receives a library id, a library host, or any credential. There is no
client-side library selection and no cross-library fallback.
```

### 4.2 Add the upload data source

```markdown
### 16.7 Video Upload Data Source

`BunnyUploadRemoteDataSource` obtains a short-lived upload authorization from the backend,
bound to one library and one video, then uploads using the resumable protocol. It never
holds a library API key. Completion is confirmed server-side before the video can be
associated with a lecture.

**Status:** mechanism pending capability verification (U-05/U-06). No client design is
finalized until the mechanism is proven.
```

---

## 5. `08_DEVELOPMENT_STANDARDS.md` (Draft)

Add a short section:

```markdown
## Bunny Credential Standards

1. **Naming is derived, never chosen.** Per-library secrets are
   `BUNNY_<libraryId>_STREAM_API_KEY` and `BUNNY_<libraryId>_TOKEN_KEY`. An operator may
   not invent a secret name.
2. **One library, one credential scope.** A callable may read only the credential of the
   library it is acting on. There is no global Bunny key in new code.
3. **Secrets never leave the server.** No key, token, signed URL or credential reference
   may appear in a client response, a Firestore document, a log line, an exception
   message, or an audit payload.
4. **IAM is one binding per secret.** The runtime service account receives
   `roles/secretmanager.secretAccessor` on the specific secret. No broader role.
5. **Verification reads metadata, not payloads.** Checking a secret means listing
   versions and IAM, never `versions access`.
6. **No key rotation without a separate approved procedure.** Rotation is an incident or
   lifecycle event, not a routine deploy step.
```

---

## 6. `09_TASKS .md` (Draft)

### 6.1 Close the open expiry question (L141)

**Current:** `- [ ] **NEW**: Confirm Bunny CDN Signed URL expiry duration (suggested: 5 minutes per request).`

**Proposed:** `- [x] Bunny CDN signed-URL expiry confirmed (2026-11-17): video 3600 s, Bunny Storage resources 300 s, association receipt 600 s. The 5-minute suggestion is not adopted for video.`

### 6.2 Rewrite T-000.9

**Proposed:**

```markdown
| **T-000.9** | **Configure Bunny CDN integration: server-managed library catalog (`bunny_libraries`); Dashboard registers libraries (Doctor only) and selects a library per video; Cloud Function `generateBunnySignedUrl` issues the signed URL per request after server-side library resolution; student never sees the raw URL, the library id, or any credential; quality tiers controlled by membership (per Final Decisions Section 4 as amended by ADR-010 Amendment 2).** | **T-000.7** |
```

### 6.3 New tasks

| ID | Task | Depends on |
|---|---|---|
| T-CF.14 | Implement `registerBunnyLibrary` / `deactivateBunnyLibrary` (Doctor only, audited) | `05` approval |
| T-CF.15 | Implement receipt-key migration to `BUNNY_ASSOCIATION_RECEIPT_KEY` with 600 s dual-verify | Gate 1 |
| T-CF.16 | Implement scheduled library verification + alert channel | E-05 |
| T-CF.17 | Implement secure Stream video upload (mechanism pending U-05/U-06) | U-05, U-06 |
| T-CF.18 | Backfill `bunny_library_id` for the 6 rows with a verified video id | Data approval |
| T-DB.1 | Register Production library `736742` in the catalog | `05` approval |

---

## 7. `11_Assets.md` (Draft)

**Current L354:** "Videos (Bunny CDN): Versioning handled by Bunny CDN; platform stores only `video_id`."

**Proposed:**

```markdown
- **Videos (Bunny CDN):** Versioning is handled by Bunny CDN. The platform stores the
  video id **and the library that owns it** (`bunny_video_id`, `bunny_library_id`). A
  video id alone is ambiguous once more than one library exists. Library identity is
  resolved server-side and is never exposed to clients.
```

Also add to §4.3 (Bunny CDN Assets):

```markdown
**Library association:** every video belongs to exactly one registered library. The
library catalog is itself a platform asset record and is maintained by the Doctor.
```

---

## 8. `13_Releases.md` (Draft)

### 8.1 Environment matrix row (L500)

**Current:** `| Bunny CDN | Test library | Test library | Production library |`

**Proposed:** `| Bunny CDN | ≥2 registered test libraries | ≥2 registered test libraries | Registered libraries (currently 1: `736742`) |`

### 8.2 Release checklist additions

```markdown
- [ ] Multi-library playback verified: a video from each registered library plays, and
      no video plays from a library it is not associated with.
- [ ] Library deactivation verified: deactivating a library stops its playback immediately.
- [ ] Emergency eligibility list verified: engaging it removes a library from eligibility
      and never adds one.
- [ ] Credential isolation verified: a missing credential for one library fails closed and
      does not fall back to another library.
- [ ] Audit records present for registration, deactivation, association and upload.
```

---

## 9. Figma status (Workstream G)

**BLOCKED — Figma specification unavailable.**

Re-verified 2026-11-17: zero MCP resources/templates, no Figma tool in the catalog, no
Figma token in the environment, and no Figma browser session.

| Node | Screen | Status |
|---|---|---|
| `58011:1024` | Add New Video | BLOCKED — Figma specification unavailable |
| `58335:1444` | Library Picker | BLOCKED — Figma specification unavailable |
| `871:1074` | Dialog | BLOCKED — Figma specification unavailable |
| `58171:1964` | Dialog | BLOCKED — Figma specification unavailable |

**Access required (either one):**

1. A Figma personal access token with `file_read` on the design file, exposed as
   `FIGMA_TOKEN`; **or**
2. A read-only share link per node plus an export (PNG at 2× and the node's spec panel).

No UI specification has been invented. `03_UI_UX` cannot be extended for these screens
until the nodes are readable.

---

## 10. `FINAL_DECISIONS` §4 — exact proposed amendment (Workstream C)

`FINAL_DECISIONS` is **Approved** and is written in Arabic. The amendment below preserves
every existing business rule and changes only the Dashboard-input rule that Option C
contradicts. It is reproduced in Arabic because it must be inserted verbatim.

### 10.1 Current text (§4, lines 49–56)

```markdown
## 4. Bunny CDN

- الفيديو يرفع على Bunny → Bunny يعمل transcoding
- Dashboard: أدخل Video ID فقط
- التطبيق يطلب رابط موقّع (Signed URL) من Cloud Function
- الرابط يتجدد تلقائياً كل مرة الطالب يفتح الفيديو
- الطالب ميشوفش الرابط أبداً
- الجودة المتاحة: محددة حسب الاشتراك (من Dashboard)
```

### 10.2 Proposed replacement text

```markdown
## 4. Bunny CDN

- الفيديو يرفع على Bunny → Bunny يعمل transcoding
- Dashboard: تسجيل مكتبات Bunny (Doctor فقط)، واختيار المكتبة عند رفع الفيديو أو ربطه بالمحاضرة. إدخال Video ID يبقى متاحاً كمسار احتياطي للمحتوى القديم.
- التطبيق يطلب رابط موقّع (Signed URL) من Cloud Function
- الرابط يتجدد تلقائياً كل مرة الطالب يفتح الفيديو
- الطالب ميشوفش الرابط أبداً
- الجودة المتاحة: محددة حسب الاشتراك (من Dashboard)
- المكتبة تُحدَّد من السيرفر فقط: الطالب لا يختار المكتبة، ولا يعرف هويتها، ولا يستلم أي مفتاح
- لا يوجد انتقال تلقائي بين المكتبات: مكتبة غير مسجّلة أو غير مفعّلة أو غير محقّقة = رفض العملية
- كل فيديو ينتمي لمكتبة واحدة فقط، ولا يمكن ربط فيديو بمكتبة لا تنتمي إليها
- المنصة لا تنشئ مكتبات Bunny إطلاقاً
- المكتبة 775315 مؤجلة وغير مفعّلة، ولا يتم إعدادها
```

### 10.3 Why each line changes or is preserved

| Line | Action | Reason |
|---|---|---|
| "الفيديو يرفع على Bunny → transcoding" | Preserved | Unchanged business rule |
| "Dashboard: أدخل Video ID فقط" | **Replaced** | Directly contradicts N1/N7/N8. The replacement keeps Video-ID entry as a fallback, so nothing is removed from the Owner's workflow. |
| "التطبيق يطلب رابط موقّع من Cloud Function" | Preserved | Unchanged, and matches the real callable `generateBunnySignedUrl` |
| "الرابط يتجدد تلقائياً" | Preserved | Unchanged |
| "الطالب ميشوفش الرابط أبداً" | Preserved | Unchanged |
| "الجودة محددة حسب الاشتراك" | Preserved | Unchanged; `14` adds the min(plan, library) clarification separately |
| Four new lines | **Added** | Encode N6/N11/N10 and the no-cross-library-fallback guarantee at business-decision level |

### 10.4 Proposed version-history entry for `FINAL_DECISIONS`

```markdown
- **2.3** (2026-11-17): Section 4 amended for ADR-010 Option C: the Dashboard may register Bunny libraries (Doctor only) and select a library when uploading or associating a video, while Video-ID entry remains available as a fallback. Added: the library is resolved server-side only; no automatic cross-library fallback; the platform never creates Bunny libraries; library `775315` remains deferred and inactive. No other section changed.
```

**Approval required:** this is an Approved document. The change cannot be applied without
explicit Owner approval of the Arabic text above.

---

## 11. Approval block

Proposed approval sentence:

> "I approve the cross-document governance proposal: the `04`, `06`, `07`, `08`, `09`,
> `11` and `13` changes as written, including the resolution of the signed-URL expiry
> question to 3600 s for video, 300 s for Storage resources and 600 s for association
> receipts. I also approve the `FINAL_DECISIONS` Section 4 replacement text in §10.2 and
> its version 2.3 entry. This approval authorizes documentation only."
