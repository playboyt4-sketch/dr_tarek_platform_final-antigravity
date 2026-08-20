# Feature 14 — Missing Database v1.7 Baseline

**الحالة:** **BLOCKED**  
**المرحلة:** قبل إنشاء Database Change Authority و`05_DATABASE_v1.8.md`  
**التاريخ:** 15 أغسطس 2026

## 1. القرار المرجعي

`pasted_content_13.txt` يحدد صراحةً أن:

- `05_DATABASE_v1.7.md` هو الـ **CURRENT APPROVED DATABASE BASELINE**.
- Version 1.7 يجب أن تبقى محفوظة دون overwrite أو modification in place.
- المطلوب إنشاء `05_DATABASE_v1.8.md` بالاعتماد على Version 1.7 وقرارات Feature 14.
- لا يجوز استخدام root `05_DATABASE.md` fragment كمصدر canonical.

## 2. ما تم العثور عليه فعليًا

تم البحث داخل:

- `/home/ubuntu/dr_tarek_platform/dr_tarek_platform_final/`
- `/home/ubuntu/`

والملفان الموجودان فقط هما:

| المسار | الوصف الفعلي |
|---|---|
| `docs/notion/05_DATABASE.md` | وثيقة Database كاملة، Version 1.6، Status Approved. |
| `05_DATABASE.md` | Fragment قصير خاص بـ ADR-003، وليس Database specification كاملة. |

لا يوجد ملف:

```text
05_DATABASE_v1.7.md
```

ولا توجد نسخة أخرى تحمل اسمًا أو نمطًا مكافئًا لـ Database v1.7 داخل مساحة العمل.

## 3. سبب التوقف

لا يمكن إعداد Database Change Authority أو `05_DATABASE_v1.8.md` بأمان؛ لأن ذلك يتطلب مقارنة دقيقة مع baseline Version 1.7، والحفاظ على collections وrelationships وconstraints وindexes وsecurity وquery patterns والـ architecture notes الموجودة فيها.

إعادة بناء Version 1.7 من Version 1.6 أو من ملفات أخرى ستكون اختراعًا لمصدر canonical، وقد تؤدي إلى فقدان تغييرات معتمدة أو تغيير قواعد لم يحددها Teacher في القرار الحالي. وهذا يخالف:

- عدم اختراع schema أو business rules.
- عدم downgrade إلى Version 1.6.
- عدم overwrite أو silent replacement.
- التوقف عند أي تعارض أو baseline غير متوقع.

## 4. الملفات التي لم تُعدّل

لم يتم تعديل:

- `docs/notion/05_DATABASE.md`
- `05_DATABASE.md`
- أي Flutter files.
- `functions/src/index.ts`.
- `firestore.rules`.
- `firestore.indexes.json`.
- أي migration data.

كما لم يتم إنشاء `05_DATABASE_v1.8.md` أو Database Change Authority، لأن baseline المطلوب غير متاح.

## 5. أصغر حل صحيح

يرجى تزويد المشروع بالنسخة المعتمدة:

```text
/home/ubuntu/dr_tarek_platform/dr_tarek_platform_final/05_DATABASE_v1.7.md
```

أو تزويد نسخة مكافئة معتمدة وتحديد مسارها canonical صراحةً. بعد توفيرها، يمكن إنشاء المخرجات المطلوبة فقط:

1. Feature 14 Database Change Authority.
2. Complete proposed `05_DATABASE_v1.8.md`.
3. Version Change Log.
4. Canonical-source reconciliation note.
5. Remaining blockers.

## 6. الحالة النهائية لهذه المرحلة

**BLOCKED — Missing approved baseline `05_DATABASE_v1.7.md`.**

لا يُسمح بالانتقال إلى تعديل code أو Firebase أو indexes أو migration أو tests، ولا بإنشاء v1.8 من مصادر بديلة، حتى يتم توفير baseline أو اعتماد مصدر بديل صراحةً من Teacher.
