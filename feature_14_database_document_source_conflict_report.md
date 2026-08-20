# Feature 14 — Database Document Source Conflict

**الحالة:** **BLOCKED**  
**المرحلة:** قبل إنشاء Database Change Authority  
**السبب:** وجود نسختين مختلفتين من `05_DATABASE.md` داخل المشروع دون تعريف واضح للنسخة canonical التي يجب ترقيتها.

## 1. ما تم اكتشافه

يوجد ملفان باسم `05_DATABASE.md`:

| المسار | المحتوى والحالة الظاهرة |
|---|---|
| `docs/notion/05_DATABASE.md` | وثيقة Database كاملة، تحتوي على `Version: 1.6` و`Status: Approved`، وتضم collections وrelationships وindexes والسياسات الحالية. |
| `05_DATABASE.md` | ملف قصير من ستة أسطر تقريبًا، يبدأ بـ `Academic Period Lifecycle — ADR-003` ولا يحتوي على Database overview أو Version أو collections أو history كاملة. |

الملفان مختلفان فعليًا، كما أن checksum لكل ملف مختلف. الملف الجذري ليس نسخة مطابقة أو نسخة كاملة من وثيقة Notion.

## 2. سبب التوقف

قرار Teacher في `pasted_content_12.txt` يفرض إنشاء Database Change Authority ثم **تحديث approved Database document إلى الإصدار التالي مع حفظ change history**. لا يمكن تنفيذ ذلك بأمان قبل تحديد أي ملف هو الـ canonical approved Database document؛ لأن الكتابة في `docs/notion/05_DATABASE.md` فقط قد تترك الملف الجذري متعارضًا، بينما تحديث الملف الجذري فقط لا يمكنه تمثيل Database specification الكاملة الموجودة في نسخة Notion.

هذا تعارض توثيقي جديد لم تغطه القرارات السابقة صراحةً، ولذلك تنطبق قاعدة:

> إذا ظهر تعارض جديد غير مغطى، يجب التوقف والإبلاغ قبل تغيير code أو schema.

## 3. الأدلة المحلية

- `docs/notion/05_DATABASE.md`: وثيقة كاملة، `Version: 1.6`, `Status: Approved`.
- `05_DATABASE.md`: fragment خاص بـ ADR-003، دون version أو status أو schema كاملة.
- `pasted_content_12.txt` lines 299–319: يلزم تحديث approved Database document إلى next version مع حفظ history وعدم overwrite صامت.
- `pasted_content_12.txt` lines 373–383: المطلوب في هذه الخطوة Database Change Authority وUpdated Database specification وChange Log وRemaining Blockers فقط.

## 4. أصغر قرار صحيح مطلوب

يرجى تحديد أحد الخيارين صراحةً:

1. اعتماد `docs/notion/05_DATABASE.md` باعتباره الـ canonical approved Database document، وترقية نسخته إلى `1.7` مع حفظ Version 1.6 history، مع اعتبار الملف الجذري `05_DATABASE.md` مرجع ADR مستقلًا لا تتم ترقيته في هذه الخطوة؛ أو
2. اعتماد `05_DATABASE.md` الجذري باعتباره canonical، مع تقديم النسخة الكاملة المعتمدة التي يجب دمجها فيه قبل إضافة Subject Access؛ أو
3. اعتماد سياسة تزامن تحدد أن الملفين يجب أن يتطابقا، مع توضيح كيفية دمج ADR-003 في Database specification دون حذف أو overwrite للمحتوى المعتمد.

لا أقترح اختيارًا تلقائيًا لأن ذلك سيخالف قاعدة عدم اختراع source-of-truth أو schema behavior.

## 5. ما لم يتم تنفيذه

لم يتم إنشاء Database Change Authority بعد، ولم يتم تعديل أي من الملفين، ولم يتم تعديل Flutter أو Cloud Functions أو Firestore Rules أو indexes، ولم يتم تشغيل migration أو tests.

## 6. الحالة

**BLOCKED — بانتظار تحديد canonical Database document source.**
