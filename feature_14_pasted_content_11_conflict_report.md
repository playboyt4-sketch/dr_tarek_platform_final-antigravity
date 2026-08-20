# Feature 14 — Conflict Report قبل التنفيذ
## pasted_content_11.txt مقابل Approved Database Reference

**المشروع:** Dr. Tarek Platform  
**الحالة:** **BLOCKED**  
**المرحلة:** Phase 1 — Code/Schema Audit  
**التاريخ:** 15 أغسطس 2026  
**المرجع الأعلى:** `docs/notion/00_MASTER_ARCHITECTURE.md`

> تم إيقاف التنفيذ فور اكتشاف تعارضات حقيقية بين `pasted_content_11.txt`، الذي يحتوي على Final Implementation Approval من Teacher، وبين القواعد الموجودة في Approved Database Reference `docs/notion/05_DATABASE.md`. لم يتم تعديل application code أو Cloud Functions أو Firestore Rules أو Database schema أو indexes.

## 1. ملخص التعارضات

| # | المجال | الوثيقة الأولى والقاعدة | الوثيقة الثانية والقاعدة | الحالة |
|---:|---|---|---|---|
| 1 | First-open Free Plan | `pasted_content_11.txt` lines 73–85: disabled أو missing Subject Access assignment يسبب **DENY** ويمنع first-open activation؛ missing لا يعني enabled. | `docs/notion/05_DATABASE.md` lines 180–190: عند عدم وجود subscription، يخلق backend تلقائيًا Free Plan عند أول فتح للمادة. | **BLOCKED** |
| 2 | Student Type conversion | `pasted_content_11.txt` lines 177–194: عند تعارض subscription موجود مع eligibility الجديدة يجب **STOP** وعدم اختراع conversion/deletion behavior. | `docs/notion/05_DATABASE.md` lines 163–167: Admin/Teacher يستطيعان التحويل في أي وقت، والتحويل يغير permissions/plan eligibility فقط. | **BLOCKED** |
| 3 | Gift Membership | `pasted_content_11.txt` lines 276–284: Gift removed؛ لا UI أو callable أو provider أو analytics أو permissions أو tests، ولا حذف صامت للحقول legacy. | `docs/notion/05_DATABASE.md` lines 319–327: Gift Membership ضمن Supported Membership Operations؛ وlines 354–357 و894–904 تتضمن gift في Analytics Policy/event list؛ وlines 820–821 تعرّف حقول gift في subscription. | **BLOCKED** للتوثيق المعتمد |
| 4 | Database version | `pasted_content_11.txt` lines 27–55: إنشاء collection Top-Level `subject_access_assignments` وعدم وضع Subject Access داخل subscriptions. | `docs/notion/05_DATABASE.md` Version 1.6 لا تحتوي collection الجديدة ولا evaluation order الجديد. | **BLOCKED** حتى تسجيل واعتماد Database Change ثم تحديث `05_DATABASE.md` |

## 2. التعارض الأول: Free Plan Activation

### الوثيقة الأولى

`pasted_content_11.txt` يفرض ترتيب الوصول التالي:

```text
Subject Access
↓
Subscription
↓
Active Plan
↓
plan_features
↓
Entitlement
```

ويحظر اعتبار missing assignment مفعّلًا، كما ينص صراحةً على أن Subject Access disabled أو missing يمنع first-open Free Plan activation.

### الوثيقة الثانية

`docs/notion/05_DATABASE.md` في Section 7 يقرر أن عدم وجود `subscriptions` عند أول فتح للمادة يؤدي إلى إنشاء Free Plan تلقائيًا باستخدام `student_type` و`system_settings.default_plan`.

### سبب التعارض

تطبيق القاعدة القديمة سينشئ subscription في حالة لا يوجد فيها assignment صالح، وهو ما قد يمنح access لمادة لم يُصرح بها. لذلك لا يمكن تنفيذ `activateFreePlan` قبل تحديد أن قاعدة pasted_content_11 تحل محل قاعدة automatic activation القديمة.

### أصغر إصلاح صحيح مقترح

تحديث Section 7 في `05_DATABASE.md` ليصبح Free Plan activation مشروطًا أولًا بوجود assignment فعال وغير محذوف بـ `enabled: true`. إذا كان assignment مفقودًا أو disabled، يرفض backend العملية ولا ينشئ subscription. لا يتطلب ذلك تغيير subscription schema.

### هل يلزم اعتماد؟

نعم. يلزم اعتماد Database Change/Decision لأن التعديل يغير قاعدة تشغيلية Approved في `05_DATABASE.md`، حتى لو كان القرار الوظيفي صادرًا من Teacher في `pasted_content_11.txt`.

## 3. التعارض الثاني: Student Type Conversion

### الوثيقة الأولى

`pasted_content_11.txt` يسمح بإدارة التحويل بين `public_student` و`center_student`، لكنه يفرض أنه إذا تعارض subscription قائم مع eligibility الخاصة بـ Student Type الجديد، فيجب التوقف وعدم اختراع سلوك تلقائي للحذف أو التحويل أو الإلغاء، مع الإبلاغ عن التعارض قبل تغييره.

### الوثيقة الثانية

`docs/notion/05_DATABASE.md` يقول إن Admin/Teacher يمكنهما التحويل في أي وقت، وأن التحويل يحافظ على learning data ويغير permissions/plan eligibility فقط، دون تحديد ماذا يحدث للاشتراكات القائمة غير المتوافقة.

### سبب التعارض

قد يحتوي الطالب على subscription لخطة `center_*` ثم يُحوّل إلى `public_student` الذي لا يسمح إلا بـ `public_free`. عبارة “convert at any time” تسمح بالتحويل، بينما قاعدة pasted_content_11 تمنع المتابعة عندما يوجد subscription متعارض، ولا تحدد automatic conversion أو deletion.

### أصغر إصلاح صحيح مقترح

إضافة قاعدة صريحة إلى Database/Student Type policy: قبل قبول التحويل، يفحص backend كل active/non-deleted subscriptions. إذا وُجد plan غير متوافق مع Student Type الجديد، يرفض العملية بحالة conflict ويعيد تفاصيل المواد/الخطط المتعارضة، ولا يعدل `student_type` ولا subscription. إذا لم يوجد تعارض، يُسمح بالتحويل مع الحفاظ على كل learning data وتسجيل audit/analytics وفق القرار المعتمد.

### هل يلزم اعتماد؟

نعم. يلزم اعتماد تعديل قاعدة التحويل في `05_DATABASE.md` ومرجع Student Type policy قبل تنفيذ callable أو UI conversion.

## 4. التعارض الثالث: Gift Membership

### الوثيقة الأولى

`pasted_content_11.txt` يزيل Gift Membership من current implementation، لكنه يمنع حذف legacy database fields بصمت.

### الوثيقة الثانية

`docs/notion/05_DATABASE.md` ما زالت تعتبر Gift Membership عملية مدعومة، وتذكرها في Supported Membership Operations وAnalytics Policy وAnalytics Events، وتعرّف `is_gifted` و`gifted_by` في `subscriptions`.

### سبب التعارض

حذف Gift من التنفيذ الحالي مع بقاء Database reference يصفه كعملية مدعومة سيجعل الوثائق غير متسقة، كما قد يسمح بعودة UI/callable/provider/analytics مستقبلًا اعتمادًا على المرجع القديم. في المقابل، حذف الحقول من schema أو production data الآن يخالف أمر Teacher بعدم الحذف الصامت.

### أصغر إصلاح صحيح مقترح

تحديث Database Change إلى أن Gift Membership **deprecated/removed from current business flow**، مع إبقاء `is_gifted` و`gifted_by` legacy/deprecated مؤقتًا. إزالة Gift من Supported Operations وAnalytics event catalog للنسخة الحالية دون migration destructive. حذف الحقول يتطلب قرار migration منفصلًا.

### هل يلزم اعتماد؟

نعم. يلزم اعتماد Database Change لتصحيح الوثيقة، ولا يلزم حذف البيانات في هذه المرحلة.

## 5. Subject Access Database Change المطلوب

بعد حسم التعارضات أعلاه، يجب تسجيل التغيير التالي قبل تعديل `05_DATABASE.md`:

| العنصر | القرار المعتمد |
|---|---|
| Collection | `subject_access_assignments` Top-Level |
| Document ID | `{student_id}_{subject_id}` |
| Required fields | `student_id`, `subject_id`, `enabled`, `created_at`, `updated_at`, `created_by`, `updated_by`, `is_deleted`, `deleted_at`, `deleted_by` |
| Access order | Subject Access → Subscription → Active Plan → `plan_features` → Entitlement |
| Missing assignment | لا يمنح access |
| Disabled assignment | DENY حتى مع active subscription أو center_max |
| Free Plan | لا activation دون enabled Subject Access |
| Existing migration | active subscription أو clear learning-access evidence = enabled؛ خلاف ذلك disabled؛ مع preservation لكل learning data |
| New approval | Student Type + per-subject Toggle قبل Accept |
| Authority | Teacher أو Admin delegated by Teacher فقط |
| Audit | previous/new enabled state، actor، role، timestamp في `admin_audit_log` |
| Indexes | فقط ما تتطلبه queries الفعلية، والمتوقع `student_id + enabled` و`subject_id + enabled` |

## 6. Affected Files

### Documentation/schema

- `docs/notion/05_DATABASE.md`
- `05_DATABASE.md` إذا كان هذا النسخ الأعلى يُحافظ عليه بالتزامن مع نسخة Notion.
- `feature_14_membership_plans_implementation_plan.md`
- `feature_14_subject_access_schema_blocker_report.md`

### Backend

- `functions/src/index.ts`، خصوصًا `activateFreePlan` وmembership lifecycle وStudent Type operations.
- `firestore.rules`، لإضافة rules للـ collection الجديدة والمحافظة على delegated permission checks.
- `firestore.indexes.json`، بعد تأكيد query patterns.

### Flutter

- `lib/features/membership/domain/entities/student_subscription.dart`، للإبقاء على legacy gift fields وعدم استخدامها في current flow.
- `lib/features/membership/domain/repositories/membership_repository.dart`، بعد اعتماد removal من target contract.
- `lib/features/membership/data/datasources/membership_remote_data_source.dart`.
- `lib/features/membership/data/repositories/membership_repository_impl.dart`.
- `lib/features/membership/presentation/providers/membership_providers.dart`.
- `lib/features/student_dashboard/data/datasources/dashboard_remote_data_source.dart`.
- `lib/features/student_dashboard/domain/entities/dashboard_subject.dart`.
- `lib/features/student_dashboard/presentation/screens/student_dashboard_screen.dart`.
- `lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart`.
- `lib/features/admin/presentation/screens/admin_home_screen.dart`.

## 7. ما تم فعليًا قبل الإيقاف

تمت قراءة القرار النهائي، ومراجعة Database reference، وفحص نقاط membership/approval/permission/audit الحالية، والتحقق من مواضع Student Type و`activateFreePlan`. لم يتم تعديل أي ملف تنفيذي أو schema أو Rule أو index.

لم تُشغّل `flutter analyze` أو `flutter test` لأن قاعدة الإيقاف تمنع الوصول إلى مرحلة التنفيذ بعد اكتشاف التعارضات.

## 8. المطلوب من قرار Teacher قبل الاستئناف

يلزم اعتماد واحد من المسارين التاليين:

1. اعتماد أن `pasted_content_11.txt` هو التعديل الرسمي الذي يحل القواعد الثلاث القديمة، مع السماح بتحديث `05_DATABASE.md` وفق Database Change Authority؛ أو
2. تقديم قواعد بديلة محددة للتعامل مع Free Plan activation، وStudent Type conflict، وGift documentation.

إلى أن يتم ذلك، تبقى الحالة **BLOCKED**، ولا يجوز تعديل `functions/src/index.ts` أو `firestore.rules` أو Flutter implementation.
