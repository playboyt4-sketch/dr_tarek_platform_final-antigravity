# Feature 14 — Membership Plans وSubject Access
## Updated Implementation Plan قبل التنفيذ

**المشروع:** Dr. Tarek Platform  
**نوع الوثيقة:** Updated Implementation Plan فقط  
**الحالة التنفيذية:** **BLOCKED** — التخطيط مكتمل، والتنفيذ ممنوع حتى اعتماد هذه الخطة والـ Database Change Specification.  
**حالة Subject Access Schema Blocker:** **PASS** — قرار Teacher حسم استخدام Collection جديدة Top-Level.  
**التاريخ:** 15 أغسطس 2026  
**المرجع المعماري الأعلى:** [`docs/notion/00_MASTER_ARCHITECTURE.md`](docs/notion/00_MASTER_ARCHITECTURE.md)  
**مراجع القرارات:** [`FINAL_DECISIONS.md`](FINAL_DECISIONS.md)، [`pasted_content_8.txt`](../upload/pasted_content_8.txt)، [`pasted_content_10.txt`](../upload/pasted_content_10.txt)  
**Baseline Audit:** [`membership_plans_audit_gap_analysis.md`](membership_plans_audit_gap_analysis.md)

> هذه الوثيقة تحول قرار Teacher الأخير إلى خطة تنفيذ قابلة للتحقق. لا تعدل أي كود أو Cloud Function أو Firestore Rule أو Database document، ولا تعتبر أي مرحلة من Feature 14 مكتملة قبل تنفيذها واختبارها فعليًا.

## 1. القرار المعتمد الذي تُبنى عليه الخطة

تم حسم تعارض Subject Access باعتماد **Collection جديدة Top-Level** باسم `subject_access_assignments`. يكون لكل زوج `(student_id, subject_id)` مستند واحد بمعرّف deterministic هو `{student_id}_{subject_id}`. Subject Access مستقل عن Subscription، ولا يجوز اعتبار غياب assignment سماحًا تلقائيًا؛ غياب السجل أو وجوده مع `enabled: false` لا يمنح access.

يبدأ resolver دائمًا بـ Subject Access، ثم Subscription، ثم Active Plan، ثم `plan_features`، ثم Entitlement. لذلك فإن Subject Access المعطل يرفض الوصول حتى لو كان الاشتراك `active` والخطة `center_max` والـ feature matrix مفعلة. وينطبق الرفض أيضًا على first-open Free Plan activation.

| القرار | الحالة | أثر التنفيذ |
|---|---|---|
| Collection جديدة `subject_access_assignments` | **PASS** | لا تُضمّن Subject Access داخل `subscriptions` ولا `plans`. |
| Deterministic ID `{student_id}_{subject_id}` | **PASS** | يفرض uniqueness على الزوج دون collection إضافية لل uniqueness. |
| Missing assignment لا يساوي enabled | **PASS** | لا default access للطلاب الحاليين أو الجدد. |
| Existing-student migration | **PASS** | تُنشأ assignments من access evidence، مع الحفاظ على كل learning data. |
| New-student approval | **PASS** | Student Type وSubject Toggles يحددان قبل Accept. |
| Disabled Subject Access | **PASS** | Deny قبل subscription وplan وfeatures. |
| Teacher/Admin delegation | **PASS** | Teacher أو Admin مفوض صراحة فقط؛ الطالب لا يغير assignment. |
| Audit | **PASS** | كل mutation يسجل previous/new state وactor role في النظام القائم. |
| Database document | **BLOCKED** | يجب أولًا اعتماد Database Change Specification ثم تحديث `05_DATABASE.md` إلى النسخة التالية. |
| Application implementation | **BLOCKED** | ممنوع قبل تسليم واعتماد هذه الخطة. |

## 2. Updated Database Change Specification

### 2.1 التغيير المطلوب في `05_DATABASE.md`

قبل تعديل المرجع المعتمد [`docs/notion/05_DATABASE.md`](docs/notion/05_DATABASE.md)، يجب تسجيل Database Change Authority مستقل يصف التغيير التالي. بعد اعتماد التغيير، يُحدّث `05_DATABASE.md` إلى النسخة التالية؛ لا يجوز تعديل الملف بصمت.

**التغيير المقترح:** إضافة Collection Top-Level باسم `subject_access_assignments` مع schema والقيود والعلاقات والفهارس وأنماط القراءة وسياسة migration الموضحة أدناه.

### 2.2 Firestore collection وdocument schema

| الحقل | النوع | مطلوب؟ | القاعدة |
|---|---|---:|---|
| `student_id` | `String` | نعم | يطابق الطالب المستهدف، ويجب أن يطابق الجزء الأول من document ID. |
| `subject_id` | `String` | نعم | يطابق المادة المستهدفة، ويجب أن يطابق الجزء الثاني من document ID. |
| `enabled` | `Boolean` | نعم | الحالة الفعلية لـ Subject Access؛ لا تُستنتج من subscription. |
| `created_at` | `Timestamp` | نعم | وقت إنشاء assignment server-side. |
| `updated_at` | `Timestamp` | نعم | وقت آخر mutation server-side. |
| `created_by` | `String` | نعم | Actor ID الذي أنشأ assignment. |
| `updated_by` | `String` | نعم | Actor ID الذي نفذ آخر mutation. |
| `is_deleted` | `Boolean` | نعم | يتبع common soft-delete convention، ولا تتحول الوثيقة المحذوفة منطقيًا إلى access. |
| `deleted_at` | `Timestamp \| null` | نعم | يُملأ عند soft delete فقط. |
| `deleted_by` | `String \| null` | نعم | Actor ID الذي نفذ soft delete فقط. |

**Document ID:** `{student_id}_{subject_id}`. يجب على callable التحقق من تطابق ID مع الحقلين، ورفض أي mismatch أو محاولة إنشاء duplicate pair.

### 2.3 العلاقات والتمييز عن Subscription

العلاقة الوظيفية تكون كما يلي:

```text
Student
  ↓
Grade / Class Group
  ↓
Applicable Subjects
  ↓
subject_access_assignments/{student_id}_{subject_id}
  ↓
subscriptions/{student_id}_{subject_id}
  ↓
plans/{plan_id}
  ↓
plan_features/{plan_id}_{feature_key}
  ↓
Unified Entitlement
```

`subject_access_assignments` يقرر هل الطالب مصرح له أصلًا باستخدام المادة. أما `subscriptions` فتقرر حالة membership والخطة للمادة التي أصبح الطالب مصرحًا لها باستخدامها. لا يجوز دمج الحالتين في boolean واحد، ولا اعتبار active subscription بديلًا عن enabled Subject Access.

### 2.4 القيود

يجب تطبيق القيود التالية server-side، مع إبقاء Firestore client writes مغلقة:

1. لا يوجد أكثر من assignment واحد لكل `(student_id, subject_id)`؛ يضمن ذلك deterministic document ID.
2. لا يُسمح بقيم فارغة أو بمستند لا يطابق فيه document ID الحقول الأساسية.
3. لا يجوز للطالب إنشاء assignment أو تعديله أو soft-delete له.
4. لا يجوز لـ Admin منح نفسه delegated permission أو تعديل permission architecture بنفسه.
5. Teacher (Platform Owner) يستطيع mutation، وAdmin يستطيعها فقط عند وجود delegated permission فعالة صادرة من Teacher.
6. كل mutation server-side، وتُسجل في `admin_audit_log` القائم، ولا تُنشأ بنية audit ثانية.
7. `is_deleted: true` لا يمنح access، ولا يُستخدم كـ missing-assignment fallback.
8. لا تُحذف أو تُعدّل collections `subscriptions`, `learning_progress`, `lecture_progress`, `notes`, `exam_attempts`, `analytics`, أو `history` كجزء من migration.

### 2.5 الفهارس المطلوبة

لا تُضاف إلا الفهارس المطلوبة فعليًا. القرار المتوقع هو:

| Collection | الحقول | الغرض |
|---|---|---|
| `subject_access_assignments` | `student_id ASC`, `enabled ASC` | استرجاع assignments الخاصة بالطالب حسب الحالة. |
| `subject_access_assignments` | `subject_id ASC`, `enabled ASC` | استرجاع الطلاب المصرح لهم بالمادة حسب الحالة. |

يجب مطابقة هذه الحاجة مع query implementation الفعلي قبل تعديل [`firestore.indexes.json`](firestore.indexes.json). لا تُضاف فهارس إضافية للتخمين.

### 2.6 Query patterns المعتمدة

يستخدم Dashboard استعلام الطالب مع `student_id == currentStudentId` و`is_deleted == false`، ثم يربط النتائج بمواد grade/class group. ويجب أن يعالج التطبيق غياب assignment كحالة غير مفعلة، لا كسماح. أما entitlement request المحدد فيستخدم deterministic ID للزوج الحالي ويقرأ assignment الفعال قبل قراءة subscription.

أما الاستعلام العكسي للمشرفين، فيُستخدم فقط في العمليات المصرح بها وبـ server-side authorization، مع `subject_id == currentSubjectId` و`enabled == true` عند الحاجة. لا يُسمح باستعلام يسرّب assignments لطلاب خارج نطاق actor.

## 3. Updated Security Model

### 3.1 Firestore Rules

ستُضاف قواعد collection الجديدة فقط بعد اعتماد Database Change. الاتجاه الأمني المطلوب هو:

| العملية | Teacher | Admin مفوض | Admin غير مفوض | Student |
|---|---:|---:|---:|---:|
| قراءة assignment الخاص به | حسب الحاجة وبنطاقه | حسب الصلاحية والنطاق | **FAIL** | حسب current student فقط |
| إنشاء assignment | server-side فقط | server-side فقط | **FAIL** | **FAIL** |
| تعديل `enabled` | server-side فقط | server-side فقط | **FAIL** | **FAIL** |
| soft delete | server-side فقط | server-side فقط | **FAIL** | **FAIL** |
| تعديل `admin_permissions` لنفسه | **FAIL** | **FAIL** | **FAIL** | **FAIL** |

القاعدة العملية هي أن mutation يمر عبر Cloud Function محمية، وأن Rules لا تعتمد على `role == admin` وحدها؛ بل تستخدم helper الصلاحيات القائم، بما يتوافق مع `activeAdminPermission()` و`canManageStudents()` في [`firestore.rules`](firestore.rules). لا تُفتح client writes إلى collection الجديدة.

### 3.2 Authorization وAudit

يجب على backend تحديد actor من Firebase Auth claims/session، ثم التحقق من Teacher أو delegated permission المطلوبة، ثم تحميل الحالة السابقة، ثم كتابة الحالة الجديدة وaudit entry في عملية server-side منضبطة. يجب أن يحوي audit الحد الأدنى على `student`, `subject`, `previous_enabled`, `new_enabled`, `changed_by`, `actor_role`, وtimestamp، مع استخدام `admin_audit_log` الموجود.

## 4. Updated Migration Plan

### 4.1 Existing Students

لا يُستخدم rule من نوع `missing assignment = enabled`. تنشئ migration assignment لكل علاقة مادة قابلة للتقييم من بيانات الوصول القائمة. إذا وُجد active وغير deleted subject subscription أو clear existing learning-access evidence للمادة، تُنشأ assignment بـ `enabled: true`. إذا لم يوجد access evidence، تُنشأ assignment بـ `enabled: false`.

المقصود بـ clear existing learning-access evidence هو evidence موجود في البيانات المعتمدة التي يستخدمها النظام حاليًا؛ لا يجوز للمهاجر اختراع مصدر جديد أو اعتبار grade membership وحده دليل وصول.

### 4.2 Data preservation

المهاجر لا يعدل ولا يحذف `subscriptions` أو `learning_progress` أو `lecture_progress` أو `notes` أو `exam_attempts` أو `analytics` أو `history`. يجب أن يكون rerunnable/idempotent باستخدام deterministic IDs، وأن يسجل summary للـ created/updated/skipped/failed records قبل اعتماد النتائج.

### 4.3 New Students

لا يُفعّل أي subject تلقائيًا لكل مواد grade. أثناء Approval Workflow يختار reviewer `student_type` من `public_student` أو `center_student`، ويضبط Toggle لكل subject applicable، ثم ينفذ Accept. Acceptance ينشئ الطالب ويحفظ assignments المختارة قبل إتاحة الوصول.

### 4.4 Migration validation

لا تُعتبر migration ناجحة إلا بعد reconciliation يثبت أن كل access evidence السابق بقي صالحًا، وأنه لا توجد assignments مفعلة بلا evidence للموجودين، وأن الطلاب الجدد لا يملكون default-all-subjects access.

## 5. Updated Approval Workflow

يجب أن يقرأ Approval UI بيانات application والمواد applicable، ثم يعرض Student Type selector وSubject Access Toggle switches قبل Accept. يجب أن تكون الحالة المرئية Toggle أخضر عند `enabled` وoff عند `disabled`، دون استخدام نص ON/OFF كعنصر التحكم الأساسي، مع ترك القياسات والألوان النهائية لموافقة Figma المعتمدة.

تدفق Accept المخطط هو:

```text
Review Application
  ↓
Select public_student / center_student
  ↓
Configure Subject Access Toggles
  ↓
Server-side authorization
  ↓
Create student + assignments
  ↓
Persist approved_by + approved_at
  ↓
Write audit
  ↓
Expose allowed session/dashboard state
```

يجب أن يسجل Approval `approved_by` و`approved_at` مع attribution واضح. لا يجوز قبول طالب دون actor attribution، ولا يجوز أن يكتب Flutter هذه القيم كحقائق موثوقة؛ يحددها backend من actor والوقت server-side. Reject لا ينشئ student أو assignments مفعلة، وفق السلوك الموجود الذي يجب التحقق منه قبل التنفيذ وعدم اختراع بديل.

## 6. Updated Unified Entitlement Flow

العقد الموحد المقترح هو `EntitlementDecision`، ويستقبل على الأقل `studentId`, `subjectId`, و`featureKey`، ثم يمر بالترتيب التالي:

```text
1. Resolve current student and subject scope
2. Read active, non-deleted Subject Access Assignment
3. If missing or disabled: DENY
4. Read one subject-scoped subscription
5. If subscription is not eligible: DENY
6. Resolve active plan
7. Resolve plan_features for featureKey
8. Return ALLOW/DENY with reason and source metadata
```

يجب أن يحتوي القرار على outcome واضح مثل `allow` أو `deny`، وسبب denial قابل للاختبار، وstudent/subject scope، دون تحويله إلى claim global. `student_type` يمكن أن يبقى claim account-level، لكنه لا يغني عن server-side Subject Access وSubscription وPlan resolution.

`activateFreePlan` يجب أن يتحقق من Subject Access أولًا؛ فإذا كان assignment مفقودًا أو disabled يرفض first-open activation ولا ينشئ subscription. وينطبق نفس resolver على Dashboard open، Video signed URL، PDF/Notes/Offline، Chat، Notifications، وdirect routes. لا يجوز direct-route bypass من خلال Flutter navigation أو deep link.

## 7. Membership Plans وقرارات Teacher السابقة

تبقى الاشتراكات subject-scoped: اشتراك واحد active لكل `(student_id, subject_id)`. تبقى الخطط `public_free` للـ `public_student` و`center_free`, `center_pro`, `center_max` للـ `center_student` وفق القرارات المعتمدة. الدفع External Payment فقط؛ لا checkout أو gateway أو in-app payment.

Gift Membership خارج current-version business flow. لا تُضاف UI أو callable أو provider أو analytics أو test أو permission جديدة له. تبقى `is_gifted` و`gifted_by` كحقول legacy/deprecated في model الحالي إلى أن يُعتمد Database migration منفصل؛ لا تُحذف الآن ولا تُستخدم في التدفق الجديد.

## 8. Dashboard وChat وNotifications وTerm

### 8.1 Student Dashboard

يعرض Dashboard المواد applicable الناتجة من Student → Grade → Subjects، ويعرض لكل مادة Subject Access state وSubscription state وEntitlement state. المادة disabled لا تُفتح، ولا يُسمح بالوصول عبر direct route. المادة التي لا تملك subscription لا تُخفى تلقائيًا إذا كانت applicable، لكن فتح المحتوى يمر عبر resolver.

يجب تصحيح fallback الحالي في [`lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart`](lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart) من `'student'` إلى قيمة صحيحة من `public_student` أو `center_student` بحسب claims/profile، دون إضافة Student Type ثالث.

### 8.2 Center-only Chat

لا يملك `public_student` Center Chat. يمر Center Chat وDoctor Channel عبر Student Type وSubject Access وSubscription وfeature entitlement. Doctor هو Teacher (Platform Owner)، وDoctor Channel read-only للطالب. أي route أو button أو backend callable يسمح لـ public_student أو لمادة غير مصرح بها يُعد فشلًا أمنيًا.

### 8.3 Notifications

تظل system/auth/security notifications منفصلة. أما Center communication/learning notifications فتُتاح لـ `center_student` عند تحقق entitlement المناسب، ولا تُتاح كتجربة Center لـ `public_student`. لا يُنشأ notification architecture ثانية.

### 8.4 Term

Start Term وEnd Term انتقالان فوريان server-side مع actor وtimestamp وprevious/new state في audit. لا يُفترض أن End Term يلغي subscription أو Subject Access ما لم تعتمد وثيقة أخرى هذه القاعدة؛ لذلك يبقى تأثير Term على entitlement **BLOCKED** حتى يُثبت من المرجع المعتمد.

## 9. Exact Files to Modify بعد اعتماد الخطة

القائمة التالية تخطيطية تنفيذية دقيقة، وليست سجلًا لتعديلات تمت بالفعل.

| الملف | التعديل المخطط |
|---|---|
| `lib/features/membership/domain/entities/membership_entities.dart` | إضافة/تجميع عقود Subject Access و`EntitlementDecision` إذا كان هذا الملف هو entity barrel المعتمد. |
| `lib/features/membership/domain/entities/student_subscription.dart` | الإبقاء على gift legacy fields كـ deprecated وعدم استخدامها؛ لا حذف قبل migration approval. |
| `lib/features/membership/domain/repositories/membership_repository.dart` | إضافة Subject Access operations وإزالة `gift` من target contract فقط بعد اعتماد removal داخل current implementation scope. |
| `lib/features/membership/data/datasources/membership_remote_data_source.dart` | ربط callable/reads الخاصة بـ Subject Access دون direct writes إلى protected collection. |
| `lib/features/membership/data/repositories/membership_repository_impl.dart` | تنفيذ repository mapping للـ assignments والـ entitlement contract. |
| `lib/features/membership/presentation/providers/membership_providers.dart` | providers للـ assignment/status/decision؛ لا provider لـ Gift. |
| `lib/features/student_dashboard/data/datasources/dashboard_remote_data_source.dart` | قراءة Subject Access وSubscription state لكل مادة. |
| `lib/features/student_dashboard/data/repositories/dashboard_repository_impl.dart` | تحويل snapshot إلى subject state موحد. |
| `lib/features/student_dashboard/domain/entities/dashboard_subject.dart` | إضافة الحقول اللازمة لتمييز access/subscription/entitlement دون دمجها في state واحد. |
| `lib/features/student_dashboard/presentation/providers/dashboard_providers.dart` | توفير dashboard subject access state مع الحفاظ على Riverpod architecture القائمة. |
| `lib/features/student_dashboard/presentation/screens/student_dashboard_screen.dart` | منع فتح المادة disabled ومنع direct-route bypass ضمن navigation الحالي. |
| `lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart` | Center-only Chat gate وتصحيح Student Type fallback. |
| `lib/features/admin/presentation/screens/admin_home_screen.dart` | Approval UI، Student Type selection، Subject Access Toggle switches، وحالة delegated permission. |
| `functions/src/index.ts` | `setSubjectAccess` authorization/audit، Approval attribution، resolver integration، وFree Plan guard، دون إعادة بناء Video/Auth/Device Binding. |
| `firestore.rules` | قواعد collection الجديدة والقراءة المقيدة، مع إبقاء mutations server-side واستعمال permission helpers القائمة. |
| `firestore.indexes.json` | إضافة الفهرسين المطلوبين فقط بعد تأكيد queries الفعلية. |
| `docs/notion/05_DATABASE.md` | تحديث إلى next approved version بعد اعتماد Database Change Specification، وليس قبل ذلك. |

قد تتطلب Chat/Notifications/Term ملفات إضافية إذا كشف audit التنفيذ الفعلي عن feature-specific files غير ظاهرة في المسارات الحالية. لا تُضاف تلك الملفات إلا بعد تحديدها في code audit، ولا تُنشأ architecture موازية.

## 10. Exact Files to Add بعد اعتماد الخطة

| الملف الجديد | الغرض |
|---|---|
| `lib/features/membership/domain/entities/subject_access_assignment.dart` | Entity typed يطابق schema المعتمدة دون business defaults غير مصرح بها. |
| `lib/features/membership/domain/entities/entitlement_decision.dart` | عقد موحد لنتيجة ALLOW/DENY وسبب القرار ونطاق الطالب/المادة. |
| `lib/features/membership/domain/use_cases/set_subject_access_use_case.dart` | use case محلي يستدعي backend authorization ولا يكتب Firestore مباشرة. |
| `docs/database_changes/feature_14_subject_access_assignments_change.md` | Database Change Authority قبل تحديث `05_DATABASE.md`، ويحتوي collection/fields/relations/ID/constraints/indexes/rules/queries/migration/distinction. |
| `functions/src/subjectAccess.ts` | يُضاف فقط إذا كان فصل backend module متوافقًا مع convention الحالي؛ وإلا يبقى التنفيذ داخل `functions/src/index.ts` دون duplicate architecture. |
| `functions/src/entitlement.ts` | يُضاف فقط إذا كان فصل resolver متوافقًا مع convention الحالي؛ لا يُنشأ module ثانٍ يؤدي نفس وظيفة resolver الموجود. |

الملفان `subjectAccess.ts` و`entitlement.ts` مشروطان بنتيجة code audit قبل التنفيذ؛ لذلك لا يُعتبران إضافة إلزامية حتى يثبت أن فصل `index.ts` مطلوب معماريًا. الإضافة الإلزامية للتوثيق هي Database Change Authority والـ domain entities إذا لم تكن موجودة فعليًا.

## 11. Protected Files وBoundaries

لا تُعاد كتابة Authentication أو Session/Routing أو Device Binding أو Video player أو Bunny signed URL أو Offline DRM. لا يُغير `00_MASTER_ARCHITECTURE.md` أو `FINAL_DECISIONS.md`، ولا تُبدل claims architecture من أجل تعويض Subject Access. لا يُضاف checkout أو payment gateway أو Gift UI أو third Student Type.

لا تُحذف data collections القائمة ولا تُعاد تسمية subscription records. لا تُبنى audit collection ثانية؛ يستخدم التنفيذ `admin_audit_log` الموجود. ولا يُسمح للـ Flutter بأن يصبح authorization source الوحيد.

## 12. Updated Test Matrix

هذه الاختبارات تُنفذ لاحقًا في Phase I–J، ولا يُدعى نجاحها الآن.

| # | الاختبار | النتيجة المطلوبة |
|---:|---|---|
| 1 | Assignment deterministic ID | `student_subject` يطابق الحقلين ويمنع duplicate pair. |
| 2 | Missing assignment | **DENY**؛ لا يتحول إلى enabled. |
| 3 | `enabled: false` مع active subscription | **DENY**. |
| 4 | `enabled: true` مع inactive/missing subscription | **DENY**. |
| 5 | Active assignment + active subscription + enabled plan feature | **ALLOW**. |
| 6 | Disabled assignment يمنع `activateFreePlan` | لا تُنشأ subscription. |
| 7 | Student Subject A لا يفتح Subject B | **DENY**. |
| 8 | Teacher يغير Subject Access | **ALLOW** مع audit كامل. |
| 9 | Delegated Admin يغير Subject Access | **ALLOW** فقط عند permission فعالة من Teacher، مع audit. |
| 10 | Admin يحاول self-grant | **DENY**. |
| 11 | Student يحاول mutation | **DENY** من backend وRules. |
| 12 | Audit previous/new state | القيم الأربع actor/role/time وprevious/new محفوظة. |
| 13 | Approval attribution | `approved_by` و`approved_at` server-side وغير فارغين عند Accept. |
| 14 | Approval toggles | assignment state يطابق toggles قبل Accept. |
| 15 | New student no default-all | لا تُفعّل كل grade subjects تلقائيًا. |
| 16 | Existing migration active subscription/evidence | assignment `enabled: true` مع preservation للبيانات. |
| 17 | Existing migration بلا evidence | assignment `enabled: false`. |
| 18 | Migration preservation | لا تعديل أو حذف لأي learning data المحددة في القرار. |
| 19 | Dashboard state | يظهر access/subscription/entitlement لكل subject applicable. |
| 20 | Disabled subject route/deep link | **DENY** ولا يوجد bypass. |
| 21 | Public Student Chat | **DENY**. |
| 22 | Center Student Chat | **ALLOW** فقط بعد resolver. |
| 23 | Doctor Channel student reply | **DENY**؛ القراءة فقط. |
| 24 | Center communication notifications | public **DENY**، center **ALLOW** عند entitlement. |
| 25 | Start/End Term | انتقال فوري server-side مع audit. |
| 26 | Unauthorized Term mutation | **DENY** ولا تغيير state. |
| 27 | Gift operation | غير موجود في target flow ولا قابل للاستدعاء الجديد. |
| 28 | In-app payment | غير موجود. |
| 29 | Video regression | signed URL وquality/entitlement الحاليان لا يتدهوران. |
| 30 | Auth/Device Binding regression | Slice 01 وdevice authorization لا يتغيران. |
| 31 | `flutter analyze` | **NOT TESTED** قبل التنفيذ؛ يجب أن يكون **PASS** بعده. |
| 32 | `flutter test` | **NOT TESTED** قبل التنفيذ؛ يجب أن يكون **PASS** بعده. |

## 13. Implementation Order بعد اعتماد الخطة

| المرحلة | النطاق | شرط الخروج |
|---|---|---|
| A | Domain contracts | Entity/repository/decision contracts مع tests، دون backend mutation. |
| B | Database Change وSubject Access backend | اعتماد change، callable محمية، Rules، audit، indexes. |
| C | Unified Entitlement وFree Plan guard | resolver order ثابت واختبارات DENY/ALLOW. |
| D | Approval وDelegated Permissions | Student Type + toggles + attribution + audit. |
| E | Dashboard | state per subject ومنع direct-route bypass. |
| F | Chat/Notifications | Center-only gates وsubject isolation. |
| G | Term | immediate server-side transitions مع audit، دون اختراع تأثير access. |
| H | Regression/security | Rules، functions، Video/Auth/Device Binding regression. |
| I | Tests | unit/widget/integration/security/migration tests. |
| J | Validation report | `flutter analyze`, `flutter test`, Web build، Acceptance Matrix بحالات PASS/FAIL/BLOCKED/NOT TESTED فقط. |

## 14. Remaining Blockers قبل بدء التنفيذ

| العنصر | الحالة | سبب الحالة |
|---|---|---|
| Subject Access schema decision | **PASS** | حُسمت Collection والـ ID والحقول والسياسة. |
| Updated Database Change Authority | **BLOCKED** | يجب اعتماد الملف التوثيقي قبل تعديل `05_DATABASE.md`. |
| Approved next version of `05_DATABASE.md` | **BLOCKED** | لا يمكن تحديث المرجع قبل اعتماد change specification. |
| Exact evidence sources for existing-student migration | **BLOCKED** | يجب تثبيتها من schema/code الحالي، ولا يجوز اعتبار grade membership evidence تلقائيًا. |
| Final Figma styling for toggles | **BLOCKED** | القرار يفرض الالتزام بالـ Figma، لكن لا يوجد في القرار قياسات نهائية قابلة للتنفيذ. |
| Term effect on entitlement | **BLOCKED** | Start/End فوريان معتمدان، أما إيقاف access بسبب End Term فغير معتمد. |
| Function module split | **NOT TESTED** | يحتاج code audit قبل تقرير إضافة `subjectAccess.ts` أو إبقاء `index.ts` واحدًا. |
| Existing Chat/Notifications schema | **NOT TESTED** | يجب مطابقة data model الحالي قبل إضافة ملفات أو collections جديدة. |
| Application implementation | **BLOCKED** | Teacher طلب صراحة عدم التنفيذ قبل إعادة الخطة. |

لا توجد قاعدة إضافية مخترعة في هذه الخطة. أي تعارض جديد بين هذه الخطة و`00_MASTER_ARCHITECTURE.md` أو `FINAL_DECISIONS.md` يوقف التنفيذ فورًا ويُرفع كتقرير مستقل قبل تعديل أي ملف.

## 15. Final Planning Status

الخطة المحدثة **مكتملة** من ناحية المطلوب في قرار Teacher: Database Change Specification، Firestore data model، security model، migration plan، approval workflow، entitlement flow، test matrix، exact files to modify/add، والـ remaining blockers موثقة. التنفيذ نفسه **BLOCKED** حتى اعتماد الخطة وDatabase Change Authority. لم يتم في هذه المرحلة تعديل application code أو Cloud Functions أو Firestore Rules أو `05_DATABASE.md` أو indexes.

## References

[1]: ../upload/pasted_content_10.txt "Teacher Decision — Feature 14 Subject Access Schema Blocker Resolution"  
[2]: ../upload/pasted_content_8.txt "Teacher Decision Update — Gift, Payment, Subject Scope, Chat, and Term"  
[3]: docs/notion/00_MASTER_ARCHITECTURE.md "Approved Master Architecture"  
[4]: FINAL_DECISIONS.md "Approved Final Decisions"  
[5]: docs/notion/05_DATABASE.md "Approved Database Reference"  
[6]: firestore.rules "Current Firestore Security Rules"  
[7]: firestore.indexes.json "Current Firestore Index Configuration"  
[8]: functions/src/index.ts "Current Cloud Functions"  
[9]: lib/features/membership/domain/entities/student_subscription.dart "Current Student Subscription Entity"  
[10]: lib/features/membership/domain/repositories/membership_repository.dart "Current Membership Repository Contract"  
[11]: lib/features/student_dashboard/data/datasources/dashboard_remote_data_source.dart "Current Dashboard Remote Data Source"  
[12]: lib/features/admin/presentation/screens/admin_home_screen.dart "Current Admin Home Screen"  
[13]: lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart "Current Student Feature Hub"  
[14]: feature_14_subject_access_schema_blocker_report.md "Previous Subject Access Schema Blocker Report"  
[15]: membership_plans_audit_gap_analysis.md "Feature 14 Audit and Gap Analysis"  
