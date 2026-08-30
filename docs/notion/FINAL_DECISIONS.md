# FINAL_DECISIONS

# قرارات نهائية — د. طارك منصة تعليمية

# تاريخ: 2026-08-04

# تم الاتفاق عليها في شات مراجعة المعمارية

---

## 1. Device Binding

- كل حساب مربوط بـ X أجهزة (X محدد حسب الاشتراك)
- Free/Pro: 1 جهاز
- Max: 2+ أجهزة (قابل للتحكم من Dashboard)
- تغيير الجهاز: الأدمن يلغي القديم → الطالب يدخل بالجديد
- Factory Reset = جهاز جديد → يحتاج تفعيل من الأدمن
- البيانات (تقدم، ملاحظات، امتحانات) متزامنة على السحابة

## 2. Offline Learning

- التحميلات على الجهاز فقط — مش على السحابة
- لو الاشتراك اتقفل: التحميلات تتمسح فوراً
- DRM: AES-256 — غير قابل للوصول برا التطبيق
- تغيير جهاز = التحميلات ترجع من أول وجديد

## 3. Authentication

- V1: Custom Tokens (أقوى من Pseudo-Email)
- V1.2: OTP + Email + Facebook + Google
- رقم التليفون: 0100... (مصر) — بدون كود دولة في V1
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
| Center Max | طالب سنتر | كل المميزات + أجهزة متعددة |
- Public → Center: لازم يتحول أولاً (مينفعش ترقية مباشرة)
- كل المميزات: قابلة للتفعيل/الإلغاء من Dashboard (Feature Matrix)

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

## 10. ملاحظات تقنية

- Custom Claims في Firebase Auth: role + student_type + plan_id + max_devices
- Cloud Functions: verifyPhonePassword + onStudentApproved + onLoginAttempt
- Firestore Security Rules: تستخدم Custom Claims (0 reads)
- Offline DRM: AES-256 + Secure Storage + Device Binding validation

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

## 14. Center Pro vs Center Max — Device Limit Only
- The only difference between the two plans is allowed device count:
  - Center Pro: exactly 1 device.
  - Center Max: more than 1, count set manually per-student from the dashboard.
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