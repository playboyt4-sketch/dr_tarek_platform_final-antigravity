# Mission 25 — جاهزية App Check في Production

**التاريخ:** 2026-11-17
**المشروع:** `dr-tarek-platform` / `606744934510`
**تصنيف هذا المسار:** `PARTIALLY CLOSED` — التهيئة موجودة على كل العملاء، لكن **لم يُجرَ أي تحقق حي** من نجاح تبادل رمز التحقق (attestation) عبر استدعاء قابل للاستدعاء.

**لم يُفعَّل `APP_CHECK_ENFORCEMENT`**، ولم تُنشر أي تغييرات تخصه. القيمة ما تزال `false` بدقة (exact match) على كل الدوال.

لا يظهر في هذا التقرير أي مفتاح موقع (site key)، ولا رمز debug، ولا أي قيمة سرية.

---

## 1. الحالة الحالية للإعداد

### 1.1 على الخادم

`APP_CHECK_ENFORCEMENT` على الدوال الست Bunny: **`false`** بدقة، ولم يتغيّر بعد إعادة النشر (تم التحقق بعد كل نشر).

على مستوى المشروع كله (83 دالة): `false` بدقة — وهذا إرث Mission 23.

آلية القراءة في `functions/src/core/utils/security_helpers.ts` (‏`describeAppCheckEnforcement()`):

- `"true"` فقط يُفعّل.
- `"false"` يُعطّل.
- أي قيمة أخرى أو غياب → **تعطيل آمن** مع تحذير عند بدء التشغيل.

هذا السلوك مُختبَر بـ16 اختباراً من Mission 22، ولم يُغيَّر.

### 1.2 تطبيقات Firebase المسجّلة في Production

```
firebase apps:list --project dr-tarek-platform
```

| المنصة | App ID | الاسم |
|---|---|---|
| ANDROID | `1:606744934510:android:e272d428dbc477bbc54e7f` | Dr. Tarek Platform |
| IOS | `1:606744934510:ios:9718f3e90867d668c54e7f` | Dr. Tarek Platform |
| WEB | `1:606744934510:web:0ed4cde346f56acec54e7f` | dr_tarek_platform (web) — تطبيق الطالب |
| WEB | `1:606744934510:web:b809f2ed62c9c9ffc54e7f` | لوحة التحكم (Dashboard) |

### 1.3 تهيئة المزوّدين (عبر Firebase App Check API، قراءة فقط)

ملاحظة منهجية مهمة: نقطة النهاية تُعيد كائناً لكل نوع مزوّد حتى لو لم يُفعّل، لذلك **وجود الكائن ليس دليلاً على التفعيل**. الإشارات الموثوقة هي: وجود `siteKey` لتطبيقات الويب، وعدد رموز الـdebug.

| التطبيق | `siteKey` مضبوط؟ | رموز Debug |
|---|---|---|
| Android | لا ينطبق (Play Integrity لا يحتاج مفتاحاً) | 0 |
| iOS | لا ينطبق (App Attest / DeviceCheck) | 0 |
| Web — الطالب | **نعم** (reCAPTCHA Enterprise) | 1 |
| Web — Dashboard | **نعم** (reCAPTCHA Enterprise) | 0 |

الرقم "1" لرموز debug في تطبيق الويب للطالب يعني وجود رمز تطوير مسجَّل مسبقاً في المشروع. هذا **لا يؤثر على Production** طالما أن بناء الإنتاج لا يستخدم `WebDebugProvider`، وهو ما تم التحقق منه في الكود (القسم 2).

---

## 2. تهيئة العملاء في الكود

### 2.1 تطبيق الطالب — `lib/main.dart` (نحو السطر 100)

المزوّدات:

| المنصة | المزوّد |
|---|---|
| Web | `ReCaptchaEnterpriseProvider` |
| Android | `PlayIntegrityProvider` (وفي وضع debug: `AndroidDebugProvider`) |
| iOS/Apple | `AppAttestProvider` مع تراجع إلى `DeviceCheckProvider` (وفي debug: `AppleDebugProvider`) |

نقاط قوة موجودة:

- التهيئة ملفوفة بـ`try/catch` — فشل App Check لا يمنع إقلاع التطبيق.
- تعليق صريح في الكود يوضح أن `FIREBASE_APPCHECK_DEBUG_TOKEN` **لا** يُضبط في `web/index.html` عن قصد، حتى لا يتسرّب إلى بناء الإنتاج ويُسقط التحقق إلى رموز debug. هذا قرار صحيح.
- يوجد `FailureCode.appCheckFailed` في `lib/core/errors/failure.dart` مع رسالة عربية مخصّصة (`appCheckFailureMessageAr`) — أي أن رفض App Check يظهر للمستخدم برسالة مفهومة لا بخطأ غامض.

### 2.2 لوحة التحكم — `dashboard/lib/main.dart:23`

```
await FirebaseAppCheck.instance.activate(
  providerWeb: ReCaptchaEnterpriseProvider('<site key literal>'),
  providerAndroid: kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
  providerApple: ...
);
```

نقاط قوة:

- مفتاح reCAPTCHA Enterprise مضبوط لـWeb.
- تمييز debug/release للمنصات الأصلية.

**نقطة ضعف حقيقية:**

- الاستدعاء **غير ملفوف بـ`try/catch`**، وهو داخل `main()` قبل `runApp`. أي فشل في تهيئة App Check (شبكة، سكربت reCAPTCHA محجوب، متصفح قديم) سيؤدي إلى **عدم إقلاع اللوحة إطلاقاً** — شاشة بيضاء بلا رسالة.
- المفتاح مكتوب حرفياً (hardcoded) في الملف. هذا **ليس تسريباً** (مفاتيح reCAPTCHA موقعية وعامة بطبيعتها)، لكنه يمنع تدوير المفتاح دون إعادة بناء.

هاتان الملاحظتان **لم تُعالجا** في هذه المهمة لأن تعديل `dashboard/lib/main.dart` ليس ضمن النطاق المصرَّح به، ولأن النظام لا يعتمد على App Check حالياً (التفعيل `false`). لكنهما يجب أن يُعالجا **قبل** أي تفعيل.

---

## 3. مصفوفة الجاهزية (بصراحة كاملة)

| العميل | التهيئة في الكود | التحقق الحي من صحة الـattestation | استدعاء قابل للاستدعاء تم التحقق منه | جاهز؟ |
|---|---|---|---|---|
| Android | ✅ `PlayIntegrityProvider` | ❌ لم يُختبر (لا جهاز/بناء Production متاح في هذه البيئة) | ❌ | **لا** |
| iOS | ✅ `AppAttest` + `DeviceCheck` | ❌ لم يُختبر | ❌ | **لا** |
| Flutter Web (الطالب) | ✅ `ReCaptchaEnterpriseProvider` | ❌ لم يُختبر حياً | ❌ | **لا** |
| Doctor Dashboard | ✅ `ReCaptchaEnterpriseProvider` (بلا `try/catch`) | ❌ لم يُختبر حياً | ❌ | **لا** |

**لماذا "لا" في كل الصفوف:**

التحقق الحي يعني: تحميل العميل فعلياً → حصوله على رمز App Check من المزوّد → إرساله مع استدعاء دالة → قبول الخادم له. هذا التسلسل يتطلب:

- للويب: متصفح حقيقي + تسجيل دخول (لا يوجد حساب اختبار).
- للأندرويد/iOS: جهاز أو محاكي مع بناء Production موقّع (غير متاح في بيئة التنفيذ).

لا يمكن الادعاء بأن العميل "جاهز" بناءً على قراءة الكود فقط. **القراءة الثابتة تُثبت وجود التهيئة، لا تُثبت نجاحها.**

ما تم التحقق منه فعلياً:

- تطبيق الويب للوحة التحكم يستجيب على `https://dr-tarek-dashboard.web.app/` بحالة **HTTP 200** — أي أن الـHosting يعمل، لكن هذا لا يُثبت شيئاً عن App Check.
- تهيئة المزوّدين موجودة في المشروع لكلا تطبيقي الويب (‏`siteKey` مضبوط).

---

## 4. الفروق بين Production وStaging

| البند | Production | Staging |
|---|---|---|
| المشروع | `dr-tarek-platform` | `dr-tarek-staging` |
| مكتبة Bunny | `736742` | `780700` |
| `APP_CHECK_ENFORCEMENT` | `false` | لم يُفحص في هذه المهمة (ممنوع تعديل Staging) |
| تطبيقات Firebase | 4 (أندرويد، iOS، ويب طالب، ويب لوحة) | لم يُفحص |

لم يُجرَ أي تعديل على Staging. لا يُدّعى أي شيء عن حالته.

---

## 5. المخاطر إذا فُعّل Enforcement اليوم

| المخاطرة | الأثر | الاحتمال |
|---|---|---|
| لوحة التحكم تفشل في الإقلاع (لا `try/catch`) | الطبيب لا يستطيع الدخول إطلاقاً | متوسط |
| رموز debug مسجّلة في مشروع Production | لو استُخدم بناء debug على الويب، سيُقبل برمز debug بدل التحقق الحقيقي | منخفض (البناء الإنتاجي لا يستخدمه) |
| أجهزة قديمة بلا Play Integrity | رفض كل الاستدعاءات من تلك الأجهزة | منخفض–متوسط |
| عدم وجود رمز debug لأندرويد/iOS | اختبار التطوير يفشل فوراً بعد التفعيل | متوسط |
| عدم وجود أي اختبار حي مسبق | اكتشاف الأعطال بعد التفعيل، أي تعطّل للطلاب | مرتفع |

الخلاصة: التفعيل الآن **غير آمن**.

---

## 6. خطة التفعيل الآمنة (مقترحة، غير منفَّذة)

**المرحلة 0 — إصلاح مسبق (يحتاج موافقة على تعديل Dashboard):**
1. لفّ `FirebaseAppCheck.instance.activate(...)` في `dashboard/lib/main.dart` داخل `try/catch` مع تسجيل الخطأ، حتى لا يمنع فشل التحقق إقلاع اللوحة.

**المرحلة 1 — مراقبة بلا حظر (غير مُنفَّذة):**
2. تفعيل "App Check metrics only" في وحدة التحكم (لا يحظر) لمدة 24–72 ساعة.
3. مراقبة نسبة الطلبات التي تحمل رمزاً صالحاً لكل تطبيق.

**المرحلة 2 — تفعيل تدريجي:**
4. تفعيل Enforcement على **دالة واحدة منخفضة الخطورة** أولاً (مثلاً دالة قراءة) وليس على مسار الفيديو.
5. التحقق من لوحة التحكم وتطبيق الطالب على الويب.
6. التوسّع دالة بدالة، مع إمكانية الرجوع الفوري (`APP_CHECK_ENFORCEMENT=false` + إعادة نشر الدالة).

**المرحلة 3 — التحقق الحقيقي:**
7. تسجيل رمز debug لأندرويد/iOS للاختبار الداخلي (في بيئة اختبار، لا Production).
8. اختبار جهاز حقيقي لكل منصة قبل تفعيل Enforcement على المسارات الحرجة.

**شرط مسبق لا يمكن تجاوزه:** وجود حسابات اختبار. بدونها لا يمكن قياس أي شيء.

---

## 7. ما لم يُنفَّذ (صريح)

- لم يُفعَّل `APP_CHECK_ENFORCEMENT` على أي دالة.
- لم تُنشر أي دالة لأجل App Check.
- لم يُضَف رمز debug.
- لم يُعدَّل `dashboard/lib/main.dart` ولا `lib/main.dart`.
- لم يُجرَ أي تبادل رمز حي (‏`exchangeRecaptchaEnterpriseToken`) ولم يُرصد.

---

## 8. الملفات

**لم يُعدَّل أي ملف.**

مراجع (قراءة فقط):

- `functions/src/core/utils/security_helpers.ts` — `describeAppCheckEnforcement()`
- `lib/main.dart` — تهيئة App Check لتطبيق الطالب
- `dashboard/lib/main.dart:23` — تهيئة App Check للوحة
- `lib/core/errors/failure.dart` — `FailureCode.appCheckFailed`

---

## 9. التصنيف

`PARTIALLY CLOSED`:

- **مكتمل:** جرد التطبيقات الأربعة، التحقق من تهيئة المزوّدين، التحقق من كود العميل، تأكيد أن Enforcement ما يزال `false` بدقة، وتحديد نقطة ضعف حقيقية في اللوحة (غياب `try/catch`).
- **غير مكتمل:** أي إثبات حي لنجاح التحقق على أي عميل — محجوب بغياب الأجهزة/الحسابات.

**التوصية:** إبقاء `APP_CHECK_ENFORCEMENT=false` حتى تُنجز المرحلة 0 والمرحلة 1 أعلاه.
