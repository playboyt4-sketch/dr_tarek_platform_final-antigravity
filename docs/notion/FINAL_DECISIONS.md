# FINAL_DECISIONS

# قرارات نهائية — د. طارك منصة تعليمية

# تاريخ: 2026-08-04

# تم الاتفاق عليها في شات مراجعة المعمارية

Version: 2.1
Status: Approved
Date: 2026-09-17
Authority: 00_MASTER_ARCHITECTURE.md Version 2.1 / ADR-004 + ADR-005 (highest authoritative source)

## Version History

- **2.1** (2026-09-17): Added Section 26 recording approved ADR-005 — Platform Owner role migration (`teacher` → `doctor`). No enforcement change in this document update.
- **2.0** (2026-09-14): Major update to Subject-Level Device Binding per ADR-004. Rewrote Section 1 to Student + Subject + Device authorization; updated Sections 2, 3, 5, 10, 14 for consistency; added Sections 16–25 (membership per Subject, Guest tier, Max two-devices-plus-single-playback, device identity, claims authority, reset/lost-device, term/freeze, migration, highest-plan rule, separation, supersession). No exact Guest minute values, no DRM durations, no fingerprint algorithm, no database/function/class details added. Sections 4, 6, 7, 8, 9, 11, 12, 13, 15 unchanged.
- **1.x** (2026-08-04 and addenda §§11–15): prior approved baseline, including the account-level device-binding model now superseded by 2.0.

---

## 1. Device Binding — Subject-Level (supersedes the old account-level model; see Section 25 and ADR-004)

- المصادقة على مستوى الحساب، وتفويض الجهاز على مستوى المادة: الطالب + المادة + الجهاز (Student + Subject + Device).
- أي جهاز صالح قد يسجّل الدخول برقم الهاتف وكلمة المرور. تفويض الجهاز لا يرفض الدخول أبداً ولا يسبب تسجيل الخروج.
- Free: جهاز واحد مصرّح له لهذه المادة. Pro: جهاز واحد مصرّح له لهذه المادة. Max: جهازان مصرّح لهما لهذه المادة.
- الجهاز المصرّح لمادة ما لا يُصرّح تلقائياً لأي مادة أخرى.
- التفويض يحدث عند أول دخول فعلي للمادة، وليس عند تسجيل الدخول للحساب.
- الجهاز غير المصرّح لمادة ما يحصل على دخول Guest/Limited لتلك المادة فقط، دون تغيير الاشتراك (انظر القسم 17).
- البيانات (تقدم، ملاحظات، امتحانات) متزامنة على السحابة.
- النموذج القديم (ربط الحساب كله بجهاز واحد، ورفض الدخول من جهاز جديد حتى يلغي الأدمن القديم) ملغى — انظر القسم 25.

## 2. Offline Learning

- التحميلات على الجهاز فقط — مش على السحابة
- لو الاشتراك اتقفل: التحميلات تتمسح فوراً (على مستوى المادة الخاصة بهذا الاشتراك، دون اختراع سلوك إضافي هنا)
- DRM: AES-256 — غير قابل للوصول برا التطبيق
- القاعدة القديمة (أي تغيير جهاز يبطل كل التحميلات على الحساب كله) ملغاة — انظر القسم 25. الوصول دون اتصال يتبع التفويض على مستوى المادة والاشتراك الخاص بها.

## 3. Authentication

- V1: Custom Tokens (أقوى من Pseudo-Email)
- V1.2: OTP + Email + Facebook + Google
- رقم التليفون: 0100... (مصر) — بدون كود دولة في V1. رقم الهاتف هو الهوية الأساسية في V1 ولا يوجد student_number كهوية للطالب. أي رقم تسلسلي في قوائم الأدمن هو تسلسل عرض فقط وليس هوية النظام.
- أي جهاز صالح قد يسجّل الدخول برقم الهاتف وكلمة المرور. تفويض الجهاز لا يرفض الدخول أبداً، والجهاز غير المصرّح لا يسبب تسجيل الخروج.
- نسيت الباسورد: الطالب يضغط "نسيت" → إشعار للأدمن/المالك → يغيّروه من Dashboard

## 4. Bunny CDN

- الفيديو يرفع على Bunny → Bunny يعمل transcoding
- Dashboard: أدخل Video ID فقط
- التطبيق يطلب رابط موقّع (Signed URL) من Cloud Function
- الرابط يتجدد تلقائياً كل مرة الطالب يفتح الفيديو
- الطالب ميشوفش الرابط أبداً
- الجودة المتاحة: محددة حسب الاشتراك (من Dashboard)

## 5. الاشتراكات

| Plan | النوع | المميزات |
| --- | --- | --- |
| Public Free | طالب خارجي | Preview أول X دقايق — قابل للتعديل |
| Center Free | طالب سنتر | كامل بس بدون مميزات Premium |
| Center Pro | طالب سنتر | كامل + مميزات إضافية |
| Center Max | طالب سنتر | كل المميزات + جهازان مصرّح بهما لهذه المادة (انظر القسم 18) |
- Public → Center: لازم يتحول أولاً (مينفعش ترقية مباشرة)
- كل المميزات: قابلة للتفعيل/الإلغاء من Dashboard (Feature Matrix)
- الاشتراك على مستوى المادة: قد يحمل الطالب خططاً مختلفة لمواد مختلفة (مثال: مادة Free ومادة Pro ومادة Max). لا يُعرض اشتراك عام واحد للطالب؛ ملف الطالب قد يعرض لكل مادة شارتها الخاصة، وشارة الخطة الظاهرة تعكس خطة المادة المختارة حالياً.
- الخطة الأعلى في مادة ما لا ترفع حد الأجهزة في مادة أخرى (انظر القسم 23).

## 6. فاتورة الدفع

- المالك فقط — الأدمن مينفعش
- تسجيل الدفع يدوي في Dashboard
- إشعار "تم تأكيد الدفع" من المالك فقط

## 7. Indexes

- 15 Composite Index أساسي (موضحين في 05 Database)
- الباقي يضاف حسب الحاجة

## 8. Notifications

- كل التحسينات السبعة:
    1. FCM Token Refresh
    2. Retry Logic
    3. Dead Letter Queue
    4. Dual System (Push + In-App)
    5. Quiet Hours
    6. Rich Notifications
    7. Grouping

## 9. UI & UX

- مؤجل — شات منفصل مع AI مصمم
- Mobile First
- Material 3
- White-based UI
- Arabic support (RTL)

## 10. ملاحظات تقنية (محدّثة per ADR-004؛ التفاصيل التنفيذية للوثائق المالكة)

- Custom Claims في Firebase Auth: role + student_type + approved (معلومات الهوية والترخيص العام فقط). لا تُستخدم أي plan_id أو max_devices أو subscription_status مفردة كحقيقة ترخيص لكل المواد، ولا تُستخدم Claims كمصدر معتمد لتفويض الجهاز على مستوى المادة (انظر القسم 20).
- Cloud Functions: verifyPhonePassword + onStudentApproved + onLoginAttempt — يُحظر استخدام أي منها لرفض الدخول بسبب الجهاز. أي فحص قديم لرفض الدخول من جهاز غير مصرّح ملغى (انظر القسم 25). لا تُخترع أسماء دوال جديدة هنا.
- Firestore Security Rules: الاشتراك وتفويض الجهاز على مستوى المادة يُحسمان من مصدر الحقيقة في الخادم، وليس من Claims مفردة. قاعدة (0 reads) القديمة لا تصلح كمصدر معتمد للتفويض الخاص بكل مادة.
- Offline DRM: AES-256 + Secure Storage + تحقق من التفويض على مستوى المادة (دون اختراع مدد أو آليات هنا).

## 11. Public Free — Per-Lecture Access Control
- Public Free students have no whole-subject access — only individual
  lectures explicitly marked available to them.
- Each lecture in the admin panel has:
  - A toggle switch "إتاحة للفري العام" (green = available / gray = not available).
  - A numeric field next to it: minutes allowed for THIS specific lecture 
    for Public Free students (independent per lecture).
- Playback stops automatically when the allowed minute count is reached, 
  showing an upgrade prompt.

## 12. Center Free — Rolling 24-Hour Single-Video Limit
- Center Free students have full access to all subjects of their current 
  grade + any prior-grade subjects manually granted (see Section 13).
- Limit: only ONE video may be started per rolling 24-hour window.
  - The window starts the moment a video is first opened.
  - Within that window, the student may resume/replay THAT SAME video 
    without restriction.
  - Attempting to start a DIFFERENT video before the window expires is 
    blocked entirely, showing "Upgrade to Pro".
  - The window resets from the timestamp of whichever video was most 
    recently opened (a rolling window, not a fixed daily reset).

## 13. Grade-Based Prior-Term Access (Center Student Only)
- When accepting a Center Student, the Admin/Teacher sets their current grade.
- A student in grade N may be granted access to subjects from any grade 
  1 to N-1 (for students repeating failed subjects).
- Grade 1 students have no prior grades — no such grant is possible.
- Granting happens at two points only:
  a. During registration review (initial approval).
  b. Later, from the student's profile screen, at any time.
- This is entirely separate from `users.grade` itself — prior-grade subject 
  access is managed via `subject_access_assignments` (already in the schema), 
  NOT by changing the student's own grade field.

## 14. Center Pro vs Center Max — Device Limit Only (per Subject; see Sections 16–18 and ADR-004)
- The only difference between the two plans is allowed device count, evaluated independently per Subject:
  - Center Pro: exactly 1 authorized device for that Subject.
  - Center Max: exactly 2 authorized devices for that Subject (device continuity + single active playback session — see Section 18). The old "more than 1, count set manually per-student" account-wide rule is superseded (see Section 25).
- Each subscription (Pro or Max) covers exactly one subject (already 
  established in FINAL_DECISIONS Section 5 — unchanged, restated for clarity).

## 15. Dual Storage Provider Support (Bunny + Firebase) — Per-Resource
- The platform supports BOTH Bunny Storage and Firebase Storage 
  simultaneously for PDFs/attachments/thumbnails — NOT a single global 
  choice, and NOT a per-upload manual pick by default either. Every stored 
  resource carries its own `storage_provider` value ("bunny" | "firebase") 
  recorded at upload time.
- The admin upload screen lets the Admin/Teacher choose the provider at 
  upload time per file (a simple selector next to each upload action), 
  defaulting to whichever provider the Teacher configures as the platform 
  default (a `system_settings.default_storage_provider` value, editable 
  from the dashboard).
- The student-facing resource-delivery logic (signed URL generation) reads 
  `storage_provider` from the resource document and dispatches to the 
  correct backend automatically — Bunny path uses the Bunny signed-URL flow, 
  Firebase path uses Firebase Storage's own access-controlled download flow. 
  Neither the student nor the playback UI needs to know or care which 
  provider served a given file.
- Video files remain Bunny-only (per FINAL_DECISIONS Section 4 — unchanged); 
  this dual-provider flexibility applies to PDFs/attachments/thumbnails only.

## 16. Subject-Level Membership (per ADR-004)

- Membership and subscription belong to the Subject. A student may hold different plans for different Subjects at the same time.
- Example: Subject A → Free; Subject B → Pro; Subject C → Max.
- The student's subscription is therefore not represented as one global plan.
- The Student Profile may show, for example: My Subjects — Subject A FREE; Subject B PRO; Subject C MAX. When the student navigates between Subjects, the visible plan badge reflects the plan of the currently selected Subject.
- A higher plan on one Subject does not increase the device allowance of another Subject (see Section 24).

## 17. Guest / Limited Access (per ADR-004)

- Guest is not a subscription plan. Guest is a limited access tier for an authenticated student whose current device is not authorized for full access to that Subject.
- Login succeeds normally. The student can enter Subjects they are entitled to access. The unauthorized device receives Guest/limited access for that Subject only.
- Guest may watch only a predefined limited amount of video content. The limited amount is configured in advance. The limitation may apply to one video or a limited number of videos. No exact minute values are defined in this document.
- Guest cannot download protected content. Guest cannot access protected PDFs. Guest cannot access protected resources that require full authorization. Guest does not receive full premium content access.
- Guest never mutates, downgrades, upgrades, or otherwise changes the student's actual subscription. Guest status is never treated as a new subscription plan.

## 18. Max Plan — Two Devices + Single Active Playback (per ADR-004)

- Max allows two authorized devices for the Subject. The purpose is device continuity, not concurrent playback.
- Example: Device S authorized and Device X authorized for the same Subject. If the student is watching content on Device S and starts the same content on Device X, playback on Device S stops, playback on Device X starts, and Device X continues from the saved/resume position. The reverse (Device X → Device S) works identically.
- Only one active playback session for the same Subject/content is allowed at a time. Max therefore means 2 authorized devices + 1 active playback session, never 2 simultaneous playback sessions.
- The transport and session implementation mechanism is not specified in this document.

## 19. Device Identity (per ADR-004)

- The platform distinguishes devices independently from the student's phone number. Device records support later recognition and audit of a known device.
- Relevant device information includes device type/platform, device identity/fingerprint, device metadata, and IP information.
- IP address is metadata only. IP address is not the sole permanent device identity because it can change.
- The exact fingerprint algorithm belongs to the owning technical documentation and is not invented here.

## 20. Custom Claims Authority (per ADR-004)

- Custom Claims are not the authoritative source for Subject-specific authorization. A single global plan identifier, device allowance, or subscription status is not used as the authorization truth for all Subjects.
- Identity/general authorization claims may contain information such as role, student type, and approval status.
- Subject subscription and Subject-Device authorization are resolved from the server-side source of truth. Claims, index, rule, and caching design belong to the owning documents.

## 21. Device Reset (per ADR-004)

- If the student loses a device, nothing happens automatically. Existing device authorization remains until the student requests intervention.
- When the Teacher (Platform Owner) or authorized Admin performs the approved Device Reset: existing device-binding/authorization data is cleared according to the approved reset operation; existing devices are no longer considered authorized; the student is not blocked from logging in; the student starts the device-binding process again from the beginning; the first new device can become authorized again according to the Subject-level authorization rules.
- Whether reset uses hard delete, soft delete, archival, or another storage mechanism is not defined here; that belongs to the Database/Firebase documents. Ordinary logout is not a Device Reset.
- No automatic migration strategy for old account-level device bindings is defined. No automatic mapping of old devices to Subjects is performed. When the approved Device Reset operation is performed, old device authorization data is cleared according to the reset operation and the student begins the device-binding cycle again under the Subject-level rules.

## 22. Lost Device (per ADR-004)

- A lost device by itself does not automatically release or transfer authorization. No automatic global unbind occurs merely because a device is lost.
- If the student requests intervention, the Teacher (Platform Owner) or authorized Admin performs the approved Device Reset/management action (see Section 21).

## 23. Subscription Term, Freeze/Resume (per ADR-004)

- Subscriptions are term-based, not monthly. When the academic term ends, the relevant subscriptions stop according to the subscription lifecycle rules. No special device behavior is introduced merely because the term ended.
- No special device behavior is invented for Freeze/Resume. Existing subscription lifecycle behavior remains authoritative. Device authorization never mutates the subscription.

## 24. Highest Plan Does Not Set Other Subjects' Allowances (per ADR-004)

- A student's highest plan does not determine device authorization allowances for other Subjects. Each Subject independently uses the allowance of that Subject's own subscription plan.
- Example: Subject A = Free → maximum 1 authorized device; Subject C = Max → maximum 2 authorized devices. The Max allowance does not grant a second authorized device to Subject A.

## 25. Architectural Separation and Supersession (per ADR-004, the architectural source)

- Account Authentication, Device Registry, Subject-Device Authorization, Subject Subscription, and Active Playback Session are separate concepts and are not treated as one global device-binding concept.
- The following old decisions are explicitly superseded and must not be used: account-wide device binding; first login permanently binding the whole account; login rejection from unauthorized devices; one global device allowance for the account; one global subscription plan used for device authorization; global device authorization represented by a single current-device pointer; global active-device state as the authorization source; device change as a prerequisite for login; global invalidation of offline content caused by any device change.
- 00_MASTER_ARCHITECTURE.md Version 2.0 / ADR-004 is the architectural source. Any remaining text in Sections 1–15 that still reads as the old account-level model is to be read as superseded by Sections 16–25; residual wording will be cleaned in owning-document follow-ups, not silently reinterpreted.

## 26. Platform Owner Role Migration — `teacher` → `doctor` (per ADR-005, approved 2026-09-17)

- Target model: `doctor` = Doctor (Platform Owner, full access); `admin` = delegated administrator (unchanged); `student` / `new_student` unchanged. `DR` is a profile badge / presentation indicator only — NOT an authorization role; no `dr` RBAC value is created.
- One shared management Dashboard architecture (no separate Admin Dashboard): Doctor at web path `/doctor` with full access; Admin at web path `/admin` with delegated permissions. Doctor Dashboard is Web-first; management functionality later surfaces in mobile through the existing management/admin icon, which is retained.
- Historical records (`actor_role: "teacher"`, `permission_basis: "teacher"`, prior ADR text, frozen change reports) remain historical and are NOT rewritten. New authorization/audit writes use `doctor`.
- No permanent `teacher OR doctor` dual authorization; the target state is `doctor`.
- Generic educational wording ("teacher reviews", generic "teachers") and the feature key `chat.doctor_channel` are NOT renamed.
- Cutover must be coordinated across Rules, Functions, owner Firestore role, Custom Claims, owner re-authentication/session refresh, and Dashboard/mobile clients. Partial migration is unsafe and not prescribed.