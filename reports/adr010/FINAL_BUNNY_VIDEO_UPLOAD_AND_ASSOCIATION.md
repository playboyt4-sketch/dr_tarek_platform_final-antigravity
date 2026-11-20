# Mission 25 — رفع الفيديو وربطه بالمحاضرة (Upload & Association)

**التاريخ:** 2026-11-17
**المشروع:** `dr-tarek-platform` / `606744934510`
**تصنيف هذا المسار:** `PARTIALLY CLOSED` — الربط مؤمَّن ومتحقق منه بالاختبارات؛ الرفع من داخل اللوحة **غير موجود** في الكود.

لا يظهر في هذا التقرير أي مفتاح، ولا توقيع، ولا رابط موقّع، ولا أي قيمة سرية.

---

## 1. المشكلة الأصلية

المطلوب تسلسل كامل: الطبيب يختار المحاضرة → يختار المكتبة → يرفع الفيديو → الـ backend يتحقق → يتم الربط بشكل آمن → يُخزَّن `bunny_library_id` و`bunny_video_id` حسب المخطط المعتمد.

الحالة الفعلية قبل هذه المهمة: خطوة "الرفع" من داخل اللوحة لم تكن موجودة أصلاً، بينما خطوة "الربط" موجودة ومؤمَّنة بالكامل.

---

## 2. السبب الجذري لغياب الرفع

### 2.1 لا توجد نقطة نهاية رفع إلى Bunny **Stream** في الـ backend

تم فحص كل الدوال الـ83. الدالة الوحيدة التي يبدو اسمها متعلقاً بالرفع هي:

`functions/src/index.ts:8477` → `uploadBunnyResource`

وبقراءة جسمها بالكامل:

```
secrets: [SECRET_BUNNY_TOKEN_KEY, SECRET_BUNNY_STORAGE_BASE_URL,
          SECRET_BUNNY_STORAGE_ZONE_NAME, SECRET_BUNNY_STORAGE_PASSWORD]
...
const storagePath = `lecture_resources/${lectureId}/${resourceId}/${fileName}`;
await bunnyStorageRequest("PUT", storagePath, bytes);
return {storagePath};
```

هذه الدالة ترفع **ملفاً** إلى **Bunny Storage** (تخزين ملفات: PDF، صور، مرفقات) وليس إلى **Bunny Stream** (فيديو). الأدلة:

- تستخدم `BUNNY_STORAGE_*` وليس `BUNNY_STREAM_*`.
- تُعيد `storagePath` وليس `videoId`.
- الحد الأقصى للحمولة `BUNNY_PROXY_MAX_BYTES = 24 * 1024 * 1024` (24MB) — غير مناسب لفيديو.
- تضع الملف تحت `lecture_resources/...` في منطقة التخزين.

لا توجد أي دالة تستدعي:

- `POST https://video.bunnycdn.com/library/{id}/videos` (إنشاء فيديو)
- أي نقطة TUS/resumable upload خاصة بـ Stream
- أي نقطة تُعيد `videoId` بعد رفع فيديو

الموجود فقط استدعاءات **قراءة** لـ Stream (بيانات وصفية/توقيع) عبر:

`functions/src/index.ts:1887` → `https://video.bunnycdn.com/library/${config.libraryId}`

### 2.2 النتيجة على تجربة الطبيب اليوم

الطبيب يرفع الفيديو يدوياً في لوحة Bunny، ثم ينسخ الـGUID ويلصقه في اللوحة:

`dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart`

```
/// VIDEO-ID-ONLY: bare Bunny GUID only - URLs are rejected.
bool isValidBunnyVideoId(String raw) { ... }
```

هذا تصميم **مقصود وموثّق** في الكود، وليس نسياناً. لكنه لا يحقق هدف Mission 25 ("Doctor uploads a video to the selected library" من داخل اللوحة).

### 2.3 لماذا لم يُضَف الرفع في هذه المهمة

رفع الفيديو إلى Stream يحتاج قرارين لا يملكهما المنفّذ:

1. **المكتبة المستهدفة**: بدون منتقي مكتبات (محجوب — انظر التقرير الثاني) لا يوجد "المكتبة الصحيحة" التي يُرفع إليها.
2. **نموذج الرفع**: رفع عبر Cloud Function بترميز base64 سيتجاوز حدود الحمولة ويستهلك ذاكرة ضخمة؛ الرفع الصحيح هو TUS من المتصفح مباشرة إلى Bunny باستخدام **توقيع/توكن رفع** قصير العمر يُصدره الخادم. هذا يتطلب تصميم نقطة نهاية جديدة (`createBunnyVideoUploadTicket`) — وهي **إضافة معمارية** لم تُعتمد في أي وثيقة سابقة، وتحتاج موافقة.

لا يجوز اختراع هذا التصميم ثم وصفه بأنه "معتمد".

---

## 3. نموذج الربط الأمني (موجود ومتحقق منه)

هذا هو الجزء القوي في النظام، وتم التأكد من عدم المساس به.

### 3.1 التوقيع (Receipt)

`functions/src/core/video/bunny_library_association.ts`

| الخاصية | القيمة |
|---|---|
| الخوارزمية | `HMAC-SHA256` عبر `node:crypto` (`createHmac`) |
| المقارنة | `timingSafeEqual` (مقارنة ثابتة الزمن) |
| نطاق التوقيع | `RECEIPT_DOMAIN = "adr010-association-v1"` |
| مدة الصلاحية | `BUNNY_VALIDATION_RECEIPT_TTL_SECONDS = 10 * 60` (600 ثانية) |
| الارتباط | المصدر + المحاضرة + المكتبة + الفيديو + وقت الانتهاء |

نصّ التعليق التوثيقي في الملف:

> A receipt proves only that one association; it is never a general ...
> Expired, ... receipts are false. Never throws.

أي أن الإيصال **مقيّد بالارتباط الواحد** ولا يصلح كتصريح عام — وهذا يمنع إعادة الاستخدام (replay) على ارتباط آخر.

### 3.2 الكتابة

- الربط يتم داخل `runTransaction` (كتابة ذرّية): إما يُكتب الارتباط كاملاً أو لا شيء.
- التحقق من الإيصال يحدث قبل الكتابة، وليس بعدها.

### 3.3 الصلاحيات

| الطبقة | القاعدة |
|---|---|
| الدوال | `requireContentManager(request)` على `validateBunnyVideoAssociation` و`associateBunnyVideoToLibrary` |
| Firestore Rules — `create` | `bunny_library_id` يجب أن يكون `null` |
| Firestore Rules — `update` | `bunny_library_id` غير قابل للتغيير (الجديد == القديم) |
| Firestore Rules — `update` | `bunny_video_id` غير قابل للتغيير على الصفوف المرتبطة بمكتبة |
| Firestore Rules — `update` | `created_at` غير قابل للتغيير (يمنع "ترقيع" صف قديم ليصبح legacy) |
| Firestore Rules — `bunny_libraries` | رفض كامل لكل وصول من العميل |

هذا التصميم يعني: **العميل لا يستطيع كتابة `bunny_library_id` أبداً**. القيمة الوحيدة الممكنة من العميل هي `null` عند الإنشاء، ثم تتغيّر فقط عبر دالة الخادم.

---

## 4. الحالة الفعلية للبيانات في Production (قراءة فقط)

فحص عدّادات فقط، دون أي بيانات شخصية:

| المجموعة | العدد |
|---|---|
| `lecture_resources` | 13 |
| موارد فيديو (`resource_type == "video"`) | 13 |
| موارد تحمل `bunny_library_id` صريحاً | **0** |
| `bunny_libraries` | **0** |

الاستنتاج: كل الفيديوهات الحالية على **مسار المكتبة الافتراضية القديم** (legacy default → `736742`)، ولا يوجد صف واحد يستخدم الربط متعدد المكتبات. هذا متسق تماماً مع Option 1.

---

## 5. الاختبارات

| الاختبار | النتيجة |
|---|---|
| `npm run build` | `exit 0` |
| حزمة Functions الكاملة | **56/56 ملف، 0 FAIL** |

الحزمة تتضمن اختبارات وحدة (pure) لنموذج الارتباط: التحقق من الإيصال الصحيح، الإيصال المنتهي، المكتبة الخاطئة، الفيديو الخاطئ، وإعادة الاستخدام — جميعها تمر.

ملاحظة صريحة: هذه اختبارات وحدة على منطق التوقيع والتحقق، **وليست** اختباراً حياً على Production. لا يوجد في Production ارتباط حقيقي متعدد المكتبات لاختباره.

---

## 6. سيناريوهات الفشل المطلوبة وحالتها

| السيناريو | كيف يُرفض | الحالة |
|---|---|---|
| إرسال مزدوج (duplicate) | `runTransaction` + الإيصال المقيّد بالارتباط | مغطى بالاختبارات |
| إيصال منتهي (expired) | مقارنة `expiresAt` داخل `verifyBunnyAssociationReceipt` | مغطى |
| مكتبة خاطئة | الإيصال موقّع على مكتبة محددة | مغطى |
| فيديو خاطئ | الإيصال موقّع على `videoId` محدد | مغطى |
| إعادة تشغيل (replay) على ارتباط آخر | `RECEIPT_DOMAIN` + ربط الحقول | مغطى |
| عميل يحاول كتابة `bunny_library_id` مباشرة | Firestore Rules | مغطى بالقواعد |
| طالب يحاول الربط | `requireContentManager` | مغطى |

---

## 7. الفجوة المتبقية (بدقة)

| الخطوة | موجود؟ |
|---|---|
| 1. الطبيب يختار المحاضرة | ✅ |
| 2. الطبيب يختار المكتبة | ❌ (محجوب — التقرير الثاني) |
| 3. اللوحة تطلب مسار رفع مُصرَّح | ❌ (غير موجود) |
| 4. الـ backend يتحقق ويُصرّح | ❌ (لا نقطة نهاية) |
| 5. الرفع إلى المكتبة المقصودة | ❌ |
| 6. التحقق من اكتمال الرفع | ❌ |
| 7. جلب metadata | ✅ (دوال القراءة موجودة، والآن بمفتاح صالح v2) |
| 8. التحقق من الارتباط على الخادم | ✅ |
| 9. التحقق من الإيصال | ✅ |
| 10. كتابة ذرّية | ✅ |
| 11. تخزين `bunny_library_id` + `bunny_video_id` | ✅ (عبر الخادم فقط) |
| 12. عرض النجاح | ✅ (لنمط GUID الحالي) |

أي أن **النصف الثاني من السلسلة مكتمل ومؤمَّن، والنصف الأول (الرفع) غير منفَّذ**.

---

## 8. ما يجب اعتماده لتنفيذ الرفع (خطة مقترحة، غير منفَّذة)

1. **موافقة معمارية** على نقطة نهاية جديدة:
   `createBunnyVideoUploadTicket(libraryId, lectureId, resourceId)` — تتحقق من الصلاحية وأهلية المكتبة من الكتالوج، ثم تُصدر توقيع TUS قصير العمر (دقائق) ومحدوداً بحجم وامتداد مسموحين.
2. الرفع يتم من المتصفح مباشرة إلى Bunny عبر TUS — **لا يمر الفيديو عبر Cloud Function** (تجنّب حدود الحمولة والذاكرة).
3. عند انتهاء الرفع: استدعاء `validateBunnyVideoAssociation` بالـ`videoId` الناتج ثم `associateBunnyVideoToLibrary`.
4. تسجيل حدث في `admin_audit_log` لكل رفع (النمط مستخدم بالفعل في `uploadBunnyResource`).
5. واجهة: شريط تقدم الرفع + إعادة المحاولة + عرض الخطأ (تحتاج Figma).

كل بند من 1 و5 يحتاج موافقة/مواصفة. لا يمكن المضي بدونها.

---

## 9. الملفات

**لم يُعدَّل أي ملف** في مسار الرفع/الربط في هذه المهمة.

الملفات المرجعية (قراءة فقط):

- `functions/src/index.ts` (‏`uploadBunnyResource` :8477، `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `listEligibleBunnyLibraries` :7802)
- `functions/src/core/video/bunny_library_association.ts`
- `functions/src/core/video/bunny_library_catalog_reader.ts`
- `firestore.rules` (`lecture_resources`, `bunny_libraries`)
- `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart`
- `dashboard/lib/features/students/data/bunny_association_gateway.dart`
- `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart`

---

## 10. التراجع

لا يوجد ما يُتراجع عنه: لم يُغيَّر كود ولا قواعد ولا نشر في هذا المسار.

---

## 11. التصنيف

`PARTIALLY CLOSED`:

- **مكتمل:** التحقق من الارتباط، التوقيع HMAC، TTL، الكتابة الذرّية، الصلاحيات، حماية القواعد، اختبارات الوحدة.
- **غير مكتمل:** الرفع من داخل اللوحة إلى Bunny Stream، واختيار المكتبة — وكلاهما يحتاج موافقة معمارية ومواصفة Figma.
