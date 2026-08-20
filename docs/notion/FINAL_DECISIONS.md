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