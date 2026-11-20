# Mission 25 — إعادة ربط إصدار مفتاح Bunny Stream في دوال Production

**التاريخ:** 2026-11-17
**المشروع:** `dr-tarek-platform` / رقم المشروع `606744934510` / المنطقة `us-central1`
**الفرع / HEAD:** `ci/ios-staging-codemagic` / `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (بدون أي commit أو reset أو stash أو clean)
**النطاق:** ربط إصدار السر فقط — لم يتم تدوير أي مفتاح، ولم تُنشأ أي نسخة سر جديدة.
**تصنيف هذا المسار:** `CLOSED` (إعادة الربط مكتملة ومتحققة) — مع بند واحد معلّق منخفض الخطورة (بقاء الإصدار 1 بحالة `enabled`) موضّح في القسم 9.

لا يظهر في هذا التقرير أي قيمة سر، ولا جزء منها، ولا بصمة (fingerprint)، ولا أي رمز يشبه الأسرار. تتم الإشارة إلى الأسرار بالاسم ورقم الإصدار والحالة فقط.

---

## 1. المشكلة الأصلية

في Mission 24 تم — بالخطأ — استخدام نقطة نهاية خاصة بتدوير مفتاح المكتبة:

```
POST api.bunny.net/videolibrary/736742/resetApiKey
```

نتيجة ذلك:

- المفتاح القديم لمكتبة `736742` أصبح ميتاً (revoked من جهة Bunny).
- المفتاح الجديد تم تخزينه في Secret Manager باسم `BUNNY_STREAM_API_KEY` كإصدار **رقم 2**.
- الإصدار **رقم 1** بقي موجوداً في Secret Manager بحالة `enabled` لكن قيمته لم تعد صالحة.

الخطورة: الدوال الست المسؤولة عن الفيديو كانت لا تزال مرتبطة بالإصدار 1. أي استدعاء لبيانات وصفية (metadata) أو رابط تشغيل موقّع كان سيُرفض من Bunny بمفتاح ميت — أي تعطّل كامل لمسار الفيديو في Production، دون أي تغيير في الكود يفسّر العطل.

الدوال الست المتأثرة:

1. `generateBunnySignedUrl`
2. `getLectureResources`
3. `getSectionDisplayMedia`
4. `generateBunnyResourceUrl`
5. `validateBunnyVideoAssociation`
6. `associateBunnyVideoToLibrary`

---

## 2. السبب الجذري (متحقق منه من الحالة المنشورة)

### 2.1 كيف يربط Firebase Functions (Gen2) إصدارات Secret Manager

دوال Gen2 هي خدمات Cloud Run، وربط السر يظهر في وصف الدالة كقائمة `secretEnvironmentVariables` تحتوي الحقول:

```
key, secret, version
```

حقل `version` هو **رقم إصدار رقمي مُثبَّت (pinned)** يُحسب وقت النشر، وليس مرجعاً ديناميكياً مثل `latest`.

النتيجة العملية:

- إنشاء إصدار جديد للسر **لا يغيّر** ما تستخدمه الدوال المنشورة.
- إعادة نشر الدالة (أو تشغيل `firebase deploy` عليها) هي ما يعيد حساب الإصدار المثبّت إلى أحدث إصدار مفعّل.
- لذلك كان الوضع في Mission 24 "سليماً في Secret Manager، معطّلاً في الدوال" — وهذا يفسّر عدم ظهور أي خطأ نشر.

تم التحقق من هذا السلوك من حالتين مستقلتين:

1. وصف الدوال الست المنشورة (`gcloud functions describe`) أظهر `version=1` صراحةً لكل واحدة.
2. بقية الأسرار على نفس الدوال (مثل `BUNNY_TOKEN_KEY` على الإصدار 3 و`BUNNY_PLAYBACK_URL_TEMPLATE` على الإصدار 2) كانت مربوطة بإصدارات أحدث من 1، أي أن الآلية تعمل كما هو موصوف وليست معطّلة.

### 2.2 لماذا لم يُكتشف العطل آلياً

- لا يوجد فحص صحة (health check) يستدعي Bunny دورياً.
- `processNotificationQueue` وخطأ الفهرس كانا يسجّلان أخطاءً، لكن مسار Bunny لا يسجّل شيئاً حتى يُستدعى فعلياً من عميل.
- لذلك بقي العطل صامتاً حتى التحقق اليدوي في هذه المهمة.

---

## 3. الأدلة قبل الإصلاح (Production، قراءة فقط)

الأمر المستخدم:

```
gcloud functions describe <name> --project dr-tarek-platform --region us-central1 --format=json
```

| الدالة | `BUNNY_STREAM_API_KEY` | `APP_CHECK_ENFORCEMENT` | `updateTime` |
|---|---|---|---|
| `generateBunnySignedUrl` | version **1** | exact `false` | `2026-11-17T11:39:25Z` |
| `getLectureResources` | version **1** | exact `false` | `2026-11-17T11:39:27Z` |
| `getSectionDisplayMedia` | version **1** | exact `false` | `2026-11-17T11:39:2x Z` |
| `generateBunnyResourceUrl` | version **1** | exact `false` | `2026-11-17T11:39:2x Z` |
| `validateBunnyVideoAssociation` | version **1** | exact `false` | `2026-11-17T11:39:2x Z` |
| `associateBunnyVideoToLibrary` | version **1** | exact `false` | `2026-11-17T11:39:2x Z` |

جميع الدوال الست تعمل بحساب الخدمة:

```
606744934510-compute@developer.gserviceaccount.com
```

ولا تحمل أي متغير بيئة يحتوي المفتاح بشكل نصي — المتغيرات الموجودة هي فقط:

```
APP_CHECK_ENFORCEMENT, BUNNY_STREAM_LIBRARY_ID,
EVENTARC_CLOUD_EVENT_SOURCE, FIREBASE_CONFIG, FUNCTION_SIGNATURE_TYPE,
FUNCTION_TARGET, GCLOUD_PROJECT, LOG_EXECUTION_ID
```

أي أن Mission 23 (إزالة المفتاح النصي) لا تزال سليمة.

---

## 4. حالة السر و IAM (بيانات وصفية فقط)

```
gcloud secrets versions list BUNNY_STREAM_API_KEY --project dr-tarek-platform
```

| الإصدار | الحالة | تاريخ الإنشاء |
|---|---|---|
| 2 | `enabled` | `2026-11-17T12:04:01` |
| 1 | `enabled` | `2026-11-17T11:29:54` |

سياسة IAM على مستوى السر:

```
roles/secretmanager.secretAccessor
  -> serviceAccount:606744934510-compute@developer.gserviceaccount.com
```

لا يوجد أي عضو آخر (لا `allUsers`، لا `allAuthenticatedUsers`، لا مستخدم بشري). هذا مطابق لـ Mission 23.

ملاحظة مهمة: قيمة الإصدار 1 أصبحت ميتة من جهة Bunny، لكن حالتها في Secret Manager ما تزال `enabled`. تعطيلها أو إتلافها يحتاج موافقة منفصلة (القسم 9).

---

## 5. التحقق المسبق قبل النشر (Preflight)

| البند | النتيجة |
|---|---|
| المشروع الافتراضي في `.firebaserc` | `dr-tarek-platform` ✅ (Production، وليس Staging) |
| ملفات `functions/src` المعدّلة بعد آخر نشر (`2026-11-17T11:39Z`) | **لا شيء** ✅ (الكود المنشور = الكود المحلي) |
| محتوى `functions/.env` | `APP_CHECK_ENFORCEMENT=false` و`BUNNY_STREAM_LIBRARY_ID=736742` فقط ✅ |
| مراجعات Cloud Run الحالية (خط الأساس للتراجع) | مسجّلة لكل الخدمات الست ✅ |
| عدد الدوال الحالي | 83 ✅ |
| `npm run build` | `BUILD_EXIT=0` ✅ |

مراجعات خط الأساس (rollback baseline):

| الخدمة | المراجعة الحالية قبل النشر |
|---|---|
| `generatebunnysignedurl` | `generatebunnysignedurl-00035-vuy` |
| `getlectureresources` | `getlectureresources-00031-guj` |
| `getsectiondisplaymedia` | `getsectiondisplaymedia-00004-rab` |
| `generatebunnyresourceurl` | `generatebunnyresourceurl-00017-vom` |
| `validatebunnyvideoassociation` | `validatebunnyvideoassociation-00001-dab` |
| `associatebunnyvideotolibrary` | `associatebunnyvideotolibrary-00001-rer` |

---

## 6. التنفيذ

### 6.1 البناء

```
cd functions
npm run build
```

النتيجة: `BUILD_EXIT=0` (‏`tsc` بدون أخطاء).

### 6.2 النشر المحدود (ست دوال فقط)

```
firebase deploy --only functions:generateBunnySignedUrl,functions:getLectureResources,functions:getSectionDisplayMedia,functions:generateBunnyResourceUrl,functions:validateBunnyVideoAssociation,functions:associateBunnyVideoToLibrary --project dr-tarek-platform --non-interactive
```

النتيجة: `DEPLOY_EXIT=0` و`Deploy complete!` و**ست عمليات تحديث ناجحة فقط** (6 updates, 0 creates, 0 deletes).

لم يتم استخدام نشر شامل للدوال الـ83 (وهو ممنوع بدون موافقة منفصلة).

### 6.3 ما لم يتغيّر

- عدد الدوال الكلي بقي **83**.
- الدوال السبع والسبعون الأخرى بقيت بأوقات تحديث `11:39Z–11:45Z` (أي قبل النشر) — لم تُلمس.
- `APP_CHECK_ENFORCEMENT` بقي exact `false` على الدوال الست.
- لم تُعدَّل `firestore.rules`، ولم تُنشر أي دالة غير الست.

---

## 7. التحقق بعد النشر

| الدالة | `BUNNY_STREAM_API_KEY` | `APP_CHECK_ENFORCEMENT` | `updateTime` |
|---|---|---|---|
| `generateBunnySignedUrl` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:11Z` |
| `getLectureResources` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:21Z` |
| `getSectionDisplayMedia` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:20Z` |
| `generateBunnyResourceUrl` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:21Z` |
| `validateBunnyVideoAssociation` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:21Z` |
| `associateBunnyVideoToLibrary` | **version 2** ✅ | exact `false` | `2026-11-17T16:18:20Z` |

الاستنتاج: الإصدار الميت (1) لم يبقَ مربوطاً بأي دالة. المفتاح الحي (2) هو المستخدم في كل مسارات الفيديو.

### 7.1 ما لم يُثبت في هذا المسار

إعادة الربط تُثبت أن الدوال تحمل الإصدار الصحيح، لكنها **لا تُثبت** بمفردها أن:

- طلب metadata من Bunny يعيد 200.
- الصور المصغّرة والملصقات (poster/thumbnail) تُحمّل.
- رابط التشغيل الموقّع يعمل ويُشغّل الفيديو فعلياً.

هذه البنود تحتاج استدعاءً حقيقياً بجلسة طالب مُخوَّل، وهي موثّقة كغير متحققة في:

`reports/adr010/FINAL_BUNNY_PRODUCTION_PLAYBACK_VALIDATION.md`

---

## 8. اختبارات Regression ذات صلة

| الاختبار | النتيجة |
|---|---|
| `npm run build` | `exit 0` |
| حزمة اختبارات Functions الكاملة (`FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test`) | **56/56 ملف ناجح، 0 FAIL** |

الحزمة تشمل اختبارات محلّل الأسرار لكل مكتبة، واختبارات كتالوج المكتبات، واختبارات التحقق من الارتباط — ولم يحدث أي تراجع بسبب إعادة النشر (النشر لا يغيّر كوداً، لكنه يعيد بناء الحزمة وتشغيلها).

---

## 9. القيود المتبقية (تحتاج موافقة منفصلة)

| البند | الحالة | لماذا لم يُنفّذ |
|---|---|---|
| الإصدار 1 من `BUNNY_STREAM_API_KEY` ما يزال `enabled` بقيمة ميتة | معلّق | تعطيل/إتلاف إصدار سر إجراء غير مُصرَّح به في هذه المهمة. الخطورة الآن منخفضة: لا دالة تستخدمه. |
| إثبات حي أن metadata/thumbnail/signed URL تعمل | غير متحقق | يحتاج حساب طالب اختباري في Production (غير موجود) |
| `BUNNY_TOKEN_KEY` | لم يُلمس (version 3) | مفتاح توقيع التشغيل لم يتغيّر — لا حاجة |

التوصية: بعد إثبات التشغيل الحي، يُطلب من المالك إذن صريح لتعطيل الإصدار 1 ثم إتلافه لاحقاً (destroy) لتقليل سطح الهجوم.

---

## 10. التراجع (Rollback)

الطريقة الأولى — إرجاع حركة المرور إلى المراجعات السابقة (الأسرع والأدق):

```
gcloud run services update-traffic generatebunnysignedurl --to-revisions=generatebunnysignedurl-00035-vuy=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic getlectureresources --to-revisions=getlectureresources-00031-guj=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic getsectiondisplaymedia --to-revisions=getsectiondisplaymedia-00004-rab=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic generatebunnyresourceurl --to-revisions=generatebunnyresourceurl-00017-vom=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic validatebunnyvideoassociation --to-revisions=validatebunnyvideoassociation-00001-dab=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic associatebunnyvideotolibrary --to-revisions=associatebunnyvideotolibrary-00001-rer=100 --project dr-tarek-platform --region us-central1
```

تحذير: التراجع إلى هذه المراجعات يعيد ربط **الإصدار 1 الميت**، أي أنه يُعيد العطل الوظيفي. لا يُستخدم إلا إذا كان الإصدار 2 نفسه هو سبب مشكلة ما.

الطريقة الثانية — إعادة نشر الدوال الست فقط بعد إصلاح الكود (نفس أمر القسم 6.2).

الطريقة الثالثة — إعادة ربط إصدار سر محدد عبر `gcloud run services update --update-secrets` (يتطلب مراجعة جديدة، ولا يُنصح به لأن Firebase CLI سيعيد الحساب عند النشر التالي).

---

## 11. الملفات المتأثرة

**لم يُعدَّل أي ملف في المستودع لهذا المسار.** التغيير كله في حالة النشر (deployment state):

- 6 خدمات Cloud Run أُعيد نشرها (إصدارات جديدة).
- 0 تغييرات في `functions/src/**`، 0 تغييرات في `firebase.json`، 0 تغييرات في القواعد.

---

## 12. التصنيف

`CLOSED` لمسألة إعادة الربط تحديداً:

- الإصدار الصحيح (2) مربوط بالدوال الست.
- الإصدار الميت (1) غير مربوط بأي دالة.
- لا مفتاح نصي في متغيرات البيئة.
- IAM على مستوى السر ما يزال محصوراً بحساب الخدمة.
- النشر لم يمسّ أي دالة أخرى ولم يحذف شيئاً.

القيد الوحيد المتبقي (بقاء الإصدار 1 `enabled`) مسجّل كبند منخفض الخطورة يحتاج موافقة، ولا يمنع عمل النظام.
