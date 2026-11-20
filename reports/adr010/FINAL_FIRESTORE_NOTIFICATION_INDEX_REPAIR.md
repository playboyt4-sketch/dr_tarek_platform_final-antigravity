# Mission 25 — إصلاح فهرس Firestore المفقود لطابور الإشعارات

**التاريخ:** 2026-11-17
**المشروع:** `dr-tarek-platform` / `606744934510` / قاعدة `(default)` / `us-central1`
**تصنيف هذا المسار:** `CLOSED` — الفهرس أُنشئ، أصبح `READY`، والخطأ توقف فعلياً.

---

## 1. المشكلة الأصلية

الدالة المجدولة `processNotificationQueue` (تعمل كل دقيقة) كانت تفشل في كل تشغيل بالخطأ:

```
Error: 9 FAILED_PRECONDITION: The query requires a COLLECTION_GROUP_ASC index
for collection retries and field status.
```

الأثر: طابور إعادة محاولة الإشعارات لم يكن يُعالَج إطلاقاً. أي إشعار فشل إرساله يبقى في حالة `pending` بلا إعادة محاولة — أي فقدان صامت للإشعارات.

ملاحظة مهمة: هذا العطل **سابق** لتغييرات الفيديو، ولم يكن ناتجاً عنها.

---

## 2. السبب الجذري

### 2.1 الاستعلام

`functions/src/index.ts:4281`

```ts
const retrySnap = await db.collectionGroup("retries")
  .where("status", "==", "pending")
  .limit(50)
  .get();
```

هذا استعلام **collection group** على مجموعة فرعية `retries` (تحت كل مستند في `notifications`)، مع شرط على حقل واحد `status`.

### 2.2 لماذا لا يوجد فهرس

Firestore يوفّر تلقائياً فهارس على مستوى المجموعة المفردة (single-field, `COLLECTION` scope) لكل حقل. لكن الاستعلام هنا على **collection group**، وهذا يحتاج فهرساً بنطاق `COLLECTION_GROUP` — وهو **لا يُنشأ تلقائياً**.

ولهذا كان الخطأ يذكر `COLLECTION_GROUP_ASC` تحديداً.

### 2.3 لماذا "field override" وليس فهرساً مركّباً

رابط `create_exemption` في رسالة الخطأ:

```
.../firestore/indexes?create_exemption=ClVwcm9qZWN0cy9kci10YXJlay1wbGF0Zm9ybS9kYXRhYmFzZXMvKGRlZmF1bHQpL2NvbGxlY3Rpb25Hcm91cHMvcmV0cmllcy9maWVsZHMvc3RhdHVzEAIaCgoGc3RhdHVzEAE
```

فك الترميز يُظهر المسار:

```
collectionGroups/retries/fields/status
```

أي أن المطلوب هو **تجاوز (exemption/override) على حقل واحد**، لا فهرس مركّب من عدة حقول. استخدام فهرس مركّب كان سينشئ فهرساً زائداً لا يطابق ما يطلبه Firestore، وكان سيظل يرفض الاستعلام.

---

## 3. التشخيص الحي (قبل الإصلاح)

خطأ متكرر كل دقيقة في Production:

```
2026-11-17T16:18:14.909Z  ERROR  ... COLLECTION_GROUP_ASC index for collection retries and field status
2026-11-17T16:19:09.798Z  ERROR  ... (same)
```

ومقارنة الحالة الفعلية بالملف:

| البند | القيمة |
|---|---|
| الفهارس المركّبة في الملف `firestore.indexes.json` | 36 |
| الفهارس المركّبة المنشورة فعلياً في Production | 36 |
| `fieldOverrides` في الملف | 0 |
| أي إدخال يخص `retries` | **لا يوجد** |

أي أن الملف كان مطابقاً للواقع، والمفقود هو الإدخال نفسه.

---

## 4. التغيير المنفَّذ

### 4.1 الملف

`firestore.indexes.json` — إضافة واحدة فقط:

```json
"fieldOverrides": [
  {
    "collectionGroup": "retries",
    "fieldPath": "status",
    "indexes": [
      {
        "order": "ASCENDING",
        "queryScope": "COLLECTION_GROUP"
      }
    ]
  }
]
```

### 4.2 التحقق من عدم المساس بأي فهرس قائم

| الفحص | قبل | بعد |
|---|---|---|
| عدد `indexes` | 36 | **36** (بدون تغيير) |
| عدد `fieldOverrides` | 0 | **1** |
| صلاحية JSON | صحيح | صحيح |
| حجم التغيير في الملف | — | `+12 / -1` سطر |

نسخة احتياطية قبل التعديل:

```
D:\Temp\opencode\m25_firestore.indexes.backup.json   (17622 bytes)
```

بصمات الملف:

```
sha256_before = BE648A18F5F18F3743F6F700E9C333F45CEE5C03A582982010D0752D55A3D0E3
sha256_after  = 6BF673D363AEA08CBCC716752A5FB5E8BE09F0FBAA45B2CF21200F14F1C6E845
```

---

## 5. النشر

```
firebase deploy --only firestore:indexes --project dr-tarek-platform --non-interactive
```

النتيجة:

```
INDEX_DEPLOY_EXIT=0
+  firestore: deployed indexes in firestore.indexes.json successfully for (default) database
+  Deploy complete!
```

### 5.1 ما لم يتغيّر — تنبيه مهم

سجل النشر يُظهر سطراً مثل:

```
cloud.firestore: checking firestore.rules for compilation errors...
+  cloud.firestore: rules file firestore.rules compiled successfully
```

هذا **فحص ترجمة فقط** وليس نشراً. أمر `--only firestore:indexes` لا ينشر القواعد. تم التأكد من ذلك: `firestore.rules` لم يُنشر، ولم يُعدَّل ملفه.

كذلك لم تُنشر أي دالة، ولم يُنشر أي Hosting.

### 5.2 تحذيرات القواعد الظاهرة في السجل

ظهرت تحذيرات موجودة مسبقاً في ملف القواعد:

```
[W] 27:14 - Unused function: isCenterStudent.
[W] 28:29 - Invalid variable name: request.
[W] 88:14 - Unused function: canManageAcademicTerms.
```

هذه **ليست من إنشاء هذه المهمة**، ولا تؤثر على الترجمة (الملف "compiled successfully")، ولم تُعالج لأن إصلاحها تغيير غير مصرَّح به في هذا النطاق.

---

## 6. التحقق بعد النشر

### 6.1 حالة الفهرس

```
gcloud firestore indexes fields list --project dr-tarek-platform
```

```
projects/dr-tarek-platform/databases/(default)/collectionGroups/retries/fields/status
  => COLLECTION_GROUP / READY
     fields = status:ASCENDING
```

تتبّع الحالة:

1. `CREATING` مباشرة بعد النشر.
2. أثناء البناء: الخطأ تغيّر نصّه إلى `... That index is not ready yet.` — وهذا دليل إضافي على أن الفهرس الصحيح هو المطلوب.
3. `READY`.

### 6.2 سلوك الدالة المجدولة

سجل `processnotificationqueue` بعد اكتمال الفهرس:

| التوقيت (UTC) | المستوى |
|---|---|
| `2026-11-17T16:25:15` | **ERROR** (آخر خطأ — أثناء البناء) |
| `2026-11-17T16:26:06` | INFO |
| `2026-11-17T16:27:12` | INFO |
| `2026-11-17T16:28:09` | INFO |
| `2026-11-17T16:29:10` | INFO |

عدد الأخطاء بعد `16:26:00Z`: **0**.

أربعة تشغيلات متتالية ناجحة بعد آخر خطأ — أي أن الإصلاح ليس لحظياً بل مستقر.

### 6.3 لماذا هذا دليل كافٍ بدون بيانات اختبار

`processNotificationQueue` تنفّذ الاستعلام في كل تشغيل حتى لو لم يكن هناك أي مستند `pending`. الخطأ كان يحدث **قبل** معالجة أي شيء (أي عند تنفيذ الاستعلام نفسه). اختفاء الخطأ يعني أن الاستعلام أصبح مقبولاً من Firestore. لذلك لا حاجة لإرسال إشعار حقيقي — ولم يُرسل أي إشعار حقيقي، ولم يُلمس أي مستند.

---

## 7. أثر جانبي إيجابي

بعد إصلاح الفهرس، أصبحت إعادة محاولة الإشعارات الفاشلة ممكنة مرة أخرى. أي إشعار كان عالقاً في `pending` قبل الإصلاح سيُعالَج الآن تلقائياً (حتى 3 محاولات بحسب `MAX_NOTIFICATION_RETRIES = 3`).

هذا سلوك **مقصود** وليس اختباراً: الدالة كانت مصممة للعمل، وكانت معطّلة.

---

## 8. التراجع

### 8.1 هل التراجع مطلوب؟

لا. الإضافة **إضافية بالكامل**:

- لم تُحذف أي فهرس.
- لم يُغيَّر نطاق أي فهرس قائم.
- الفهرس الجديد يخدم استعلاماً واحداً فقط.

### 8.2 إن لزم التراجع

1. استعادة الملف من النسخة الاحتياطية:

```
Copy-Item D:\Temp\opencode\m25_firestore.indexes.backup.json firestore.indexes.json -Force
```

2. إعادة نشر الفهارس:

```
firebase deploy --only firestore:indexes --project dr-tarek-platform
```

**تحذير:** إزالة تعريف من الملف لا تضمن حذف الفهرس الفعلي من المشروع. إذا لزم الحذف النهائي، يجب تأكيده من وحدة تحكم Firebase (أو أداة تدعم حذف `field` index config) والتحقق من اختفائه فعلياً — لا تفترض أن النشر حذفه.

3. الأثر الوظيفي للتراجع: عودة خطأ `FAILED_PRECONDITION` كل دقيقة، وتوقف إعادة محاولة الإشعارات.

---

## 9. الملفات المتأثرة

| الملف | التغيير |
|---|---|
| `firestore.indexes.json` | + إدخال `fieldOverrides` واحد (‏`retries` / `status` / `COLLECTION_GROUP` / `ASCENDING`) |

لا تغييرات في `firestore.rules`، ولا في `functions/src/**`، ولا في أي ملف عميل.

---

## 10. التصنيف

`CLOSED`:

- الفهرس الصحيح (وليس فهرساً مركّباً زائداً) أُنشئ.
- الحالة `READY`.
- الخطأ توقف، وأربعة تشغيلات متتالية بلا أخطاء.
- جميع الفهارس الـ36 السابقة محفوظة.
- لم تُنشر القواعد، ولم يُلمس أي مستند إشعار حقيقي.
