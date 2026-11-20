# Mission 25 — تقرير الإغلاق النهائي لمنظومة الفيديو

**التاريخ:** 2026-11-17
**المشروع:** `dr-tarek-platform` / رقم المشروع `606744934510` / المنطقة `us-central1`
**الفرع / HEAD:** `ci/ios-staging-codemagic` / `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (بدون أي commit أو push أو reset أو stash أو clean أو checkout)
**التصنيف النهائي:** **`BLOCKED`** — التفصيل الكامل في القسم 12.

لا يظهر في هذا التقرير أي مفتاح، ولا رمز، ولا رابط موقّع، ولا قيمة سرية، ولا بيانات شخصية لطالب.

---

## 1. المشكلة الأصلية (ملخّص)

بعد Mission 23 (تأمين Production) وMission 24 (تدوير مفتاح Bunny بالخطأ)، كانت منظومة الفيديو في حالة غير مؤكدة:

1. الدوال الست المسؤولة عن الفيديو قد تكون مربوطة بمفتاح ميت.
2. لا توجد واجهة لإدارة مكتبات Bunny في لوحة التحكم.
3. مسار رفع الفيديو من اللوحة غير موجود.
4. خطأ فهرس Firestore يعطّل طابور إشعارات الإنتاج كل دقيقة.
5. لم يُتحقق من تشغيل الفيديو فعلياً في Production.
6. حالة App Check غير موثّقة.

---

## 2. السبب الجذري لكل مشكلة

| المشكلة | السبب الجذري |
|---|---|
| دوال الفيديو بمفتاح ميت | Firebase Functions Gen2 **يُثبّت رقم إصدار السر وقت النشر**. إنشاء إصدار جديد (v2) لم يغيّر ما تستخدمه الدوال (v1). |
| لا منتقي مكتبات | قرار **Option 1** يمنع كتالوج `bunny_libraries`، و`listEligibleBunnyLibraries` تقرأ من هذا الكتالوج فقط → قائمة فارغة. إضافةً إلى غياب مواصفة Figma. |
| لا رفع من اللوحة | لا توجد نقطة نهاية رفع إلى **Bunny Stream** في الكود. `uploadBunnyResource` ترفع إلى **Bunny Storage** (ملفات) لا Stream (فيديو). |
| خطأ الفهرس | استعلام `collectionGroup("retries").where("status","==","pending")` يحتاج فهرس `COLLECTION_GROUP` على حقل واحد، وهو **لا يُنشأ تلقائياً**. |
| لا إثبات تشغيل | Production يحتوي 7 مستخدمين حقيقيين فقط، بلا أي حساب اختبار، ولا بيانات اعتماد مقدَّمة. |
| App Check غير موثّق | لا يوجد إثبات حي لتبادل رمز التحقق على أي عميل. |

---

## 3. ما تم تنفيذه فعلياً (ملخّص تنفيذي)

| المسار | الحالة | الدليل |
|---|---|---|
| إعادة ربط إصدار السر | ✅ `CLOSED` | الدوال الست تحمل `BUNNY_STREAM_API_KEY` **v2** بعد النشر |
| إصلاح فهرس الإشعارات | ✅ `CLOSED` | الفهرس `READY` + 4 تشغيلات بلا أخطاء |
| الربط الآمن للفيديو | ✅ موجود ومتحقق بالاختبارات | HMAC-SHA256 + TTL 600s + كتابة ذرّية + قواعد Firestore |
| رفع الفيديو من اللوحة | ❌ غير موجود | لا نقطة نهاية Stream upload |
| إدارة المكتبات من اللوحة | ⛔ `BLOCKED` | Option 1 + غياب Figma |
| إثبات تشغيل الفيديو | ⛔ `BLOCKED` | لا حسابات اختبار |
| App Check | ⚠️ `PARTIALLY CLOSED` | تهيئة موجودة، إثبات حي غائب |

---

## 4. الملفات المتغيّرة

### 4.1 داخل المستودع (تغيير واحد فقط)

| الملف | التغيير |
|---|---|
| `firestore.indexes.json` | إضافة إدخال `fieldOverrides` واحد: `retries` / `status` / `COLLECTION_GROUP` / `ASCENDING` |

### 4.2 ملفات التقارير (جديدة)

سبعة تقارير في `reports/adr010/` (انظر القسم 13).

### 4.3 ما لم يُعدَّل

- `functions/src/**` — **صفر** تغييرات.
- `dashboard/lib/**` — **صفر** تغييرات.
- `lib/**` (تطبيق الطالب) — **صفر** تغييرات.
- `firestore.rules` — **صفر** تغييرات ولم تُنشر.
- `storage.rules` — لم تُلمس.
- تقارير Missions 21–24 — لم تُعدَّل.

---

## 5. التغييرات حسب الطبقة

### 5.1 الـ backend (Cloud Functions)

- **صفر تغييرات في الكود.**
- أُعيد نشر 6 دوال فقط (لإعادة ربط إصدار السر).
- لم تُنشأ دالة، ولم تُحذف دالة.
- العدد الكلي بقي **83**.

### 5.2 لوحة التحكم (Dashboard)

- **صفر تغييرات.**
- لم يُنشر أي Hosting.
- الموجود: طبقة بيانات كتالوج غير مرئية (`bunny_library_catalog.dart`) وبوابة ربط (`bunny_association_gateway.dart`) ونمط إدخال GUID يدوي.

### 5.3 تطبيق Flutter (الطالب)

- **صفر تغييرات.**
- لم يُشغَّل `flutter analyze` على التطبيق الجذري لأنه لم يُعدَّل أي ملف Dart فيه؛ تشغيله كان سيعطي نتيجة لا علاقة لها بهذه المهمة.

### 5.4 Firebase

| العنصر | التغيير |
|---|---|
| Firestore Indexes | إضافة 1 `fieldOverride` |
| Firestore Rules | لا تغيير، لم تُنشر |
| Functions | 6 تحديثات (إعادة ربط سر) |
| Hosting | لا تغيير |
| App Check | لا تغيير (`false`) |
| Secret Manager | لا إنشاء، لا تدوير، لا تعطيل |

### 5.5 Bunny

| العنصر | الحالة |
|---|---|
| مكتبة Production `736742` | نشطة، Pull Zone `6414868` |
| مفتاح Stream | v2 هو المستخدم في كل الدوال الست |
| مفتاح Stream v1 | ما يزال `enabled` بقيمة ميتة (بند معلّق — القسم 11) |
| `BUNNY_TOKEN_KEY` | لم يُلمس (v3) |
| مكتبة `775315` | **غير مفعّلة** — لم تُلمس |
| Staging `780700` | لم يُلمس |

---

## 6. التحقق من إصدار السر (ملخّص)

| الدالة | قبل | بعد |
|---|---|---|
| `generateBunnySignedUrl` | v1 (ميت) | **v2** |
| `getLectureResources` | v1 | **v2** |
| `getSectionDisplayMedia` | v1 | **v2** |
| `generateBunnyResourceUrl` | v1 | **v2** |
| `validateBunnyVideoAssociation` | v1 | **v2** |
| `associateBunnyVideoToLibrary` | v1 | **v2** |

`APP_CHECK_ENFORCEMENT` بقي `false` بدقة على الست، ولم يتغيّر أي متغير بيئة آخر. IAM على السر ما يزال محصوراً بحساب الخدمة `606744934510-compute@developer.gserviceaccount.com`.

التفاصيل الكاملة: `FINAL_BUNNY_SECRET_VERSION_REBINDING.md`.

---

## 7. بيان النشر (Deployment Manifest)

| العملية | الأمر | النتيجة |
|---|---|---|
| بناء الدوال | `npm run build` | `exit 0` |
| نشر 6 دوال | `firebase deploy --only functions:<6> --project dr-tarek-platform` | `exit 0` — 6 updates، 0 create، 0 delete |
| نشر الفهارس | `firebase deploy --only firestore:indexes --project dr-tarek-platform` | `exit 0` — 1 field override |
| نشر Hosting | — | **لم يُنفَّذ** |
| نشر Rules | — | **لم يُنفَّذ** |
| نشر شامل للـ83 دالة | — | **لم يُنفَّذ** (ممنوع بدون موافقة) |

توقيت النشر: الدوال الست `2026-11-17T16:18Z`، والفهرس اكتمل قبل `16:26Z`. الدوال السبع والسبعون الأخرى بقيت بأوقات `11:39Z–11:45Z` (لم تُلمس).

---

## 8. نتائج الاختبارات (أوامر ونتائج دقيقة)

| الاختبار | الأمر | النتيجة |
|---|---|---|
| بناء Functions | `npm run build` | **`exit 0`** |
| حزمة Functions الكاملة | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test` | **56/56 ملف ناجح، 0 FAIL** |
| تحليل Dashboard الساكن | `flutter analyze` (في `dashboard/`) | **`exit 0` — `No issues found!`** |
| اختبارات Dashboard | `flutter test` (في `dashboard/`) | **407 ناجح / 7 فاشل** |
| إعادة تشغيل الاختبارات الفاشلة منفردة | `flutter test test/subject_details_test.dart test/subject_grade_context_sync_test.dart` | `exit 1` — نفس الـ7 إخفاقات (قابلة للتكرار) |

### 8.1 تفصيل الإخفاقات السبعة في Dashboard

| الملف | عدد | الموضوع |
|---|---|---|
| `dashboard/test/subject_details_test.dart` | 4 | توسيط عنوان المادة (3 حالات) + اختبار `EditSubjectOverlay` عند فشل الحفظ |
| `dashboard/test/subject_grade_context_sync_test.dart` | 3 | مزامنة سياق الصف عند التنقل |

**التشخيص:**

- الخطأ الأول الظاهر: `Expected: TextAlign:<TextAlign.center>` مقابل `Actual: TextAlign:<TextAlign.right>`.
- الملفان **غير معدّلين** (`git status --porcelain` لهما فارغ).
- لم يُعدَّل أي كود Dashboard في هذه المهمة.
- النتيجة: **إخفاقات سابقة، غير مرتبطة بالفيديو**، ولم تُعالَج لأن إصلاحها خارج النطاق (والمهمة تنص: لا تصلح أخطاء قديمة فقط لتجميل التقرير).

### 8.2 ما لم يُختبر

- لم تُشغَّل اختبارات Firebase Emulator لهذه المهمة (لم يتغيّر كود يستدعيها؛ الحزمة الكاملة تشمل ما هو موجود).
- لم تُشغَّل اختبارات Firestore Rules.
- لم تُشغَّل اختبارات تكامل المتصفح.

---

## 9. أدلة المتصفح / الجهاز

**لا يوجد أي دليل متصفح أو جهاز في هذه المهمة.**

- لم يُفتح متصفح لتشغيل فيديو.
- لم يُشغَّل أي مشغّل.
- لم يُرصد `readyState` ولا `currentTime`.
- الفحص الوحيد عبر الشبكة: `https://dr-tarek-dashboard.web.app/` أعاد **HTTP 200** (إثبات أن الـHosting حيّ فقط، لا أكثر).

---

## 10. نتائج فحص الإنتاج (Smoke Tests) واختبارات الأمان

### 10.1 فحوص ناجحة

| الفحص | النتيجة |
|---|---|
| حالة المشروع | `ACTIVE`، المشروع الافتراضي `dr-tarek-platform` |
| عدد الدوال | 83 (بلا تغيير) |
| الدوال الست | v2، `ACE=false`، `updateTime=16:18Z` |
| بقية الدوال | `11:39Z–11:45Z` (لم تُلمس) |
| فهرس `retries/status` | `COLLECTION_GROUP` / `READY` |
| `processNotificationQueue` | 4 تشغيلات INFO متتالية، 0 أخطاء بعد `16:26Z` |
| الفهارس المركّبة | 36 (كلها محفوظة) |
| مفتاح نصي في متغيرات البيئة | **0** دوال |
| IAM على السر | حساب الخدمة فقط |
| `bunny_libraries` | 0 مستند |
| موارد الفيديو | 13، منها **0** بـ`bunny_library_id` صريح (مسار افتراضي) |
| مكتبة `775315` | غير مفعّلة |

### 10.2 اختبارات الأمان (مراجعة قواعد ومسار)

| البند | الحالة |
|---|---|
| `lecture_resources` — `create` يفرض `bunny_library_id == null` | ✅ |
| `lecture_resources` — `update` يمنع تغيير `bunny_library_id` | ✅ |
| `lecture_resources` — `update` يمنع تغيير `bunny_video_id` على صف مرتبط | ✅ |
| `lecture_resources` — `created_at` غير قابل للتغيير | ✅ |
| `bunny_libraries` — رفض كل وصول من العميل | ✅ |
| الإيصال HMAC-SHA256 + `timingSafeEqual` | ✅ |
| TTL = 600 ثانية | ✅ |
| نطاق الإيصال `adr010-association-v1` | ✅ |
| كتابة ذرّية (`runTransaction`) | ✅ |
| `requireContentManager` على دوال الإدارة | ✅ |
| عزل Production/Staging | ✅ (لا مسار يستخدم بيانات اعتماد البيئة الأخرى) |
| فشل مغلق للمكتبات غير المعروفة | ✅ (`selectEligibleBunnyLibraries` تُسقط غير المطابق) |

### 10.3 ما لم يُختبر أمنياً بشكل حي

- رفض طالب حقيقي لمحاولة الوصول لمحتوى غير مشترك فيه (يحتاج حساب اختبار).
- سلوك ربط الجهاز (Free/Pro جهاز واحد، Max جهازان) — **لم يُختبر حياً**، ولم يُغيَّر.
- استحواذ التشغيل (playback takeover) — لم يُختبر.

---

## 11. القيود المتبقية (Remaining Limitations)

| # | القيد | الخطورة | ما يحتاجه |
|---|---|---|---|
| 1 | لا واجهة لإدارة المكتبات في اللوحة | عالية (هدف أساسي) | موافقة Option 2 + مواصفة Figma |
| 2 | لا رفع فيديو إلى Stream من اللوحة | عالية (هدف أساسي) | موافقة معمارية على نقطة نهاية رفع/TUS + Figma |
| 3 | لم يُثبت تشغيل فيديو حي في Production | عالية (هدف أساسي) | حساب اختبار أو إذن بإنشاء بيانات اختبارية |
| 4 | `BUNNY_STREAM_API_KEY` v1 ما يزال `enabled` بقيمة ميتة | منخفضة | إذن بتعطيله ثم إتلافه |
| 5 | لوحة التحكم تُهيّئ App Check بلا `try/catch` | متوسطة (مستقبلية) | تعديل `dashboard/lib/main.dart` (خارج النطاق) |
| 6 | لا إثبات حي لأي عميل App Check | متوسطة | أجهزة/حسابات + مراقبة metrics |
| 7 | 7 اختبارات Dashboard فاشلة (سابقة) | منخفضة | مهمة منفصلة لإصلاح التوسيط/مزامنة الصف |
| 8 | تحذيرات في `firestore.rules` (دوال غير مستخدمة) | منخفضة | تنظيف منفصل |

---

## 12. التصنيف النهائي

### `BLOCKED`

**لماذا ليس `FULLY CLOSED`:** ثلاثة من أهداف المهمة الأساسية غير محققة — إدارة المكتبات من اللوحة، الرفع من اللوحة، وإثبات التشغيل الحي. ولا واحدة منها أُنجزت.

**لماذا ليس `PARTIALLY CLOSED`:** هذا التصنيف مخصّص لحالة "المسار الرئيسي يعمل مع بقاء بند غير حرج". هنا البنود المتبقية **ليست غير حرجة** — هي جوهر المهمة (البندان B وD من معايير القبول). كما أن الإخفاق ليس تقنياً بل هو انعدام مدخلات خارجية إلزامية.

**لماذا `BLOCKED` تحديداً:** التعريف ينص على أن الحجب يقع عندما يمنع "موافقة مطلوبة، أو حساب، أو مواصفة Figma، أو بيانات اعتماد" الإكمال الآمن. وهذا بالضبط ما يحدث:

| العائق | نوعه | ما يحجبه |
|---|---|---|
| غياب وصول Figma (0 موارد MCP، لا أداة، لا رموز وصول) | مواصفة تصميم | واجهة منتقي المكتبات + واجهة الرفع |
| قرار Option 1 يمنع كتالوج `bunny_libraries` | موافقة معمارية | قائمة المكتبات المؤهلة |
| لا حسابات اختبار في Production (7 مستخدمين حقيقيين فقط) | حساب/بيانات اعتماد | إثبات التشغيل الحي |

**ما أُنجز رغم الحجب:** أُغلقت المشكلتان التقنيتان اللتان كانتا تُعطّلان الإنتاج فعلياً (المفتاح الميت، فهرس الإشعارات)، وتأُكّد سلامة نموذج الربط الأمني، وجُرّدت جاهزية App Check.

### 12.1 شروط الانتقال إلى تصنيف أعلى

| للوصول إلى | الشرط |
|---|---|
| `PARTIALLY CLOSED` | توفير Figma + الموافقة على تفعيل الكتالوج (فتُبنى الواجهة)، **أو** إثبات التشغيل الحي |
| `FULLY CLOSED` | تحقق جميع معايير القبول A–G، بما فيها تشغيل فيديو حقيقي تقدّم زمنه فعلياً، ورفع من اللوحة، وربط ناجح، مع عدم بقاء أي عيب حرج |

---

## 13. التقارير السبعة

| # | الملف | التصنيف |
|---|---|---|
| 1 | `FINAL_BUNNY_SECRET_VERSION_REBINDING.md` | `CLOSED` |
| 2 | `FINAL_BUNNY_DASHBOARD_LIBRARY_MANAGEMENT.md` | `BLOCKED` |
| 3 | `FINAL_BUNNY_VIDEO_UPLOAD_AND_ASSOCIATION.md` | `PARTIALLY CLOSED` |
| 4 | `FINAL_BUNNY_PRODUCTION_PLAYBACK_VALIDATION.md` | `BLOCKED` |
| 5 | `FINAL_FIRESTORE_NOTIFICATION_INDEX_REPAIR.md` | `CLOSED` |
| 6 | `FINAL_APP_CHECK_READINESS.md` | `PARTIALLY CLOSED` |
| 7 | `FINAL_VIDEO_SYSTEM_CLOSURE.md` | هذا الملف — `BLOCKED` |

---

## 14. تعليمات التراجع (Rollback)

### 14.1 الدوال الست (إعادة الربط)

```
gcloud run services update-traffic generatebunnysignedurl --to-revisions=generatebunnysignedurl-00035-vuy=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic getlectureresources --to-revisions=getlectureresources-00031-guj=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic getsectiondisplaymedia --to-revisions=getsectiondisplaymedia-00004-rab=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic generatebunnyresourceurl --to-revisions=generatebunnyresourceurl-00017-vom=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic validatebunnyvideoassociation --to-revisions=validatebunnyvideoassociation-00001-dab=100 --project dr-tarek-platform --region us-central1
gcloud run services update-traffic associatebunnyvideotolibrary --to-revisions=associatebunnyvideotolibrary-00001-rer=100 --project dr-tarek-platform --region us-central1
```

⚠️ هذا التراجع يعيد ربط **الإصدار 1 الميت** ويُعيد تعطيل الفيديو. لا يُستخدم إلا إذا كان v2 نفسه سبب مشكلة.

### 14.2 الفهرس

```
Copy-Item D:\Temp\opencode\m25_firestore.indexes.backup.json firestore.indexes.json -Force
firebase deploy --only firestore:indexes --project dr-tarek-platform
```

⚠️ حذف التعريف من الملف لا يضمن حذف الفهرس الحقيقي؛ تحقق من اختفائه فعلياً قبل اعتباره محذوفاً. التراجع يُعيد خطأ `FAILED_PRECONDITION` كل دقيقة.

### 14.3 Hosting وRules

لا شيء للتراجع عنه — لم يُنشر أي منهما.

### 14.4 حالة Git

لا يوجد ما يُتراجع عنه في Git: لم يُنفَّذ أي commit، وكل التغييرات غير المرحّلة باقية كما هي.

---

## 15. حالة Git الحالية (مُتحقَّق منها)

| البند | القيمة |
|---|---|
| الفرع | `ci/ios-staging-codemagic` |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| ملفات معدّلة | **34** (33 سابقة + `firestore.indexes.json`) |
| ملفات غير متتبَّعة | **33** (بما فيها `reports/adr010/`) |
| مرحلة (staged) | 0 |
| محذوفة | 0 |
| Commits جديدة | 0 |

لم يُنفَّذ أي أمر من: `commit`, `push`, `reset`, `clean`, `stash`, `checkout`.

---

## 16. المطلوب من المالك (ثلاث موافقات)

1. **Figma:** ربط التكامل أو تزويد رمز وصول للقراءة، أو تصدير العقد:
   `58011:1024`، `58335:1444`، `871:1074`، `58171:1964`.
2. **الموافقة المعمارية:** تفعيل كتالوج `bunny_libraries` (الحد الأدنى: مستند واحد للمكتبة `736742`) مع إقرار بأن `775315` تبقى غير مفعّلة، واعتماد تصميم نقطة نهاية رفع Stream/TUS.
3. **الاختبار الحي:** تزويد بيانات اعتماد طالب (وطبيب) اختباريين، **أو** إذن صريح بإنشاء بيانات اختبار معزولة (مستخدم واحد + اشتراك واحد) وحذفها/وسمها بعد الاختبار.

بند اختياري منخفض الخطورة: إذن بتعطيل `BUNNY_STREAM_API_KEY` الإصدار 1 ثم إتلافه.

---

## 17. خلاصة صادقة

ما يمكن قوله بثقة وبالدليل:

- منظومة الفيديو في Production **لم تعد تُعطَّل بمفتاح ميت** — هذا كان العطل الحقيقي، وقد أُصلح وتحقّق.
- طابور الإشعارات **يعمل الآن** بعد إصلاح الفهرس — متحقّق بالسجلات.
- نموذج الربط الآمن **قائم وسليم** — متحقّق بالكود والاختبارات والقواعد.
- App Check **غير مفعّل بأمان**، وجاهزيته مجرّدة، مع نقطة ضعف معروفة في اللوحة.

وما لا يمكن قوله:

- لا يمكن القول إن الطبيب يستطيع إدارة المكتبات ورفع الفيديو من اللوحة — **هذا غير موجود**.
- لا يمكن القول إن الفيديو يعمل في Production — **لم يُشغَّل فيديو واحد ولم يتقدّم `currentTime`**.

هذان البندان هما جوهر المهمة، وكلاهما محجوب بمدخلات يملكها المالك وحده.
