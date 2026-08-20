# Feature 14 — Membership Plans
## التقرير النهائي الموحد للتحقق والتنفيذ

**المشروع:** Dr. Tarek Platform — Flutter/Firebase  
**النطاق:** Membership Plans + Student Subject Access + Approval Integration  
**المرجع:** Database v1.8 والوثائق المعمارية المعتمدة  
**حالة التسليم:** لا يمكن إعلان Feature 14 مكتملة بالكامل؛ توجد عناصر **BLOCKED** موثقة أدناه.

> تم الحفاظ على قرارات Authentication وDevice Binding وVideo Streaming المعتمدة، ولم تتم إعادة بنائها أو استبدالها.

## ملخص الحالة

| الحالة | النتيجة |
|---|---|
| **PASS** | Domain/Data foundation، Subject Access، Unified Entitlement، Free Plan guards، Approval attribution، delegated authorization، Dashboard، Chat/Notifications boundaries، Gift removal، Functions build، Firestore/Storage Rules validation، `flutter analyze`، و`flutter test` الكامل. |
| **FAIL** | لا توجد نتيجة فشل نهائية بعد الإصلاحات والتحقق الأخير. ظهرت أخطاء اختبارية أثناء التطوير وتم إصلاحها في test code فقط. |
| **BLOCKED** | Academic Term server-side lifecycle transitions: لا توجد في المصادر المعتمدة بنية تخزين دقيقة ومكتملة تسمح بتنفيذ transitions/audit دون اختراع schema. |
| **NOT TESTED** | Figma/pixel-level visual acceptance، وruntime integration عبر Firebase production أو أجهزة Android/iOS فعلية غير متاحة في البيئة الحالية. |

## PASS — ما تم تنفيذه والتحقق منه

### Subject Access foundation

تم تنفيذ `SubjectAccessAssignment` ككيان مستقل عن Subscription، مع deterministic document ID، وحالات `enabled` و`is_deleted`، وقراءة student-scoped. تم الحفاظ على ترتيب entitlement المعتمد بحيث يكون Subject Access هو البوابة الأولى، ويمنع `disabled` أو المحذوف الوصول حتى عند وجود Subscription نشطة.

تم تنفيذ Firestore model وDataSource وRepository وRiverpod wiring والفهارس المعتمدة. جميع تغييرات Subject Access تمر عبر callable server-side `setSubjectAccess`؛ لا توجد Flutter direct writes إلى collection الخاصة بالتعيينات. الطالب لا يستطيع إنشاء أو تعديل أو حذف assignment، ولا يوجد self-grant.

### Unified Entitlement

تمت إضافة `EntitlementDecision` و`EntitlementResolver` داخل membership domain، مع ترتيب صريح:

> Subject Access → Subscription → Active Plan → plan_features → Entitlement

تغطي اختبارات resolver حالات الرفض عند غياب أو تعطيل كل gate، وحالة السماح عند اكتمال السلسلة. تم إصلاح assertions الاختبارية لتستخدم contract الفعلي (`isAllowed` و`reason == 'allowed'`) دون تعديل production behavior.

تمت إضافة Active Plan lookup إلى Membership Repository/DataSource/Providers. كما تم ربط Subject Access guard قبل Subscription في Free Plan وVideo وOffline وPDF وLecture resource gates الموجودة في Functions، دون إعادة بناء Video/Auth/Device Binding.

### Approval وDelegated Admin Authorization

تم تنفيذ مسار approval server-side مع attribution صريح بواسطة:

```text
approved_by = authorization.actorId
approved_at = FieldValue.serverTimestamp()
```

تتم صلاحية الإدارة عبر Teacher أو Admin الذي يملك delegated permission المعتمد، وليس عبر شرط hardcoded يعتمد على `role == admin` وحده. تم استخدام `admin_audit_log` الموجود، مع إبقاء audit writes server-side.

تمت إضافة Student Type conversion مع حفظ learning data وعدم إنشاء مسار موازي، كما تم ربط Admin Home الحالية بعناصر approval وStudent Type وper-subject toggles. التبديلات تبدأ disabled افتراضيًا، ولا تنفذ direct Firestore mutations من الواجهة.

### Membership Plans وGift Membership

تم الحفاظ على membership lifecycle والـlegacy fields `is_gifted` و`gifted_by` في schema/mapping دون استخدامها في current flow. تم حذف Gift callable وGift wrapper وGift repository API وGift use case غير المستخدم، ولم تعد توجد مراجع current-flow لـGift في `lib` أو `functions/src` أو `test` وفق الفحص النصي النهائي.

لم تتم إضافة checkout أو gateway أو in-app payment؛ يظل التدفق متوافقًا مع قرار **External Payment فقط**.

### Dashboard وChat وNotifications

تم توسيع Dashboard subject state ليعرض حالات Subject Access وSubscription وEntitlement بدل إخفاء المادة تلقائيًا عند غياب Subscription. يمنع المسار الحالي فتح مادة disabled أو غير entitled.

تم تطبيق Center-only Chat على مسارات الواجهة في Student Feature Hub وDashboard، وعلى Firestore Rules باستخدام `student_type`. كما تم تقييد Chat notifications إلى `center_student` أو الإدارة/Teacher، مع إبقاء notifications الشخصية غير المتعلقة بالـChat متاحة لمالكها وفق قواعد الملكية الحالية.

### Firestore Rules وFirebase integration

تمت إضافة والتحقق من قواعد `subject_access_assignments` بحيث:

1. الطالب يقرأ assignment الخاص به فقط إذا كان غير محذوف.
2. قراءة assignment لطالب آخر مرفوضة.
3. قراءة assignment المحذوفة مرفوضة.
4. Teacher يملك القراءة الإدارية.
5. Admin يملك القراءة الإدارية فقط عند تحقق `canManageStudents()`.
6. create مرفوض لأي Client.
7. update مرفوض لأي Client.
8. delete مرفوض لأي Client.

تم التحقق من `firestore.indexes.json` باستخدام validator مؤقت comment-aware خارج المشروع، لأن Firebase configuration الحالي يسمح بالتعليقات. لم يتم تعديل ملف الفهارس.

## PASS — أوامر التحقق الفعلية

| التحقق | الأمر/النتيجة |
|---|---|
| Rules Unit Testing dependency | تم تحديث `security-tests` إلى `@firebase/rules-unit-testing@5.0.1` مع الإبقاء على Firebase 12.17.1. |
| Firebase Emulator Rules validation | `npx --yes firebase-tools emulators:exec --config /tmp/feature14.firebase.json --only firestore,storage "npm test"` — **PASS**؛ انتهى script برمز 0 وظهر `Firestore and Storage rules tests passed.` |
| Functions compilation | `npm --prefix functions run build` — **PASS**. |
| Firestore indexes validation | validator comment-aware — **PASS**؛ لم يستخدم `JSON.parse` مباشرة ولم يعدل المصدر. |
| Focused Flutter tests | `flutter test test/membership/entitlement_resolver_test.dart test/subject_access/subject_access_assignment_test.dart test/video_streaming/video_entitlement_test.dart` — **PASS**؛ `+15: All tests passed!` |
| Flutter analyzer | `flutter analyze` — **PASS**؛ `No issues found!` |
| Full Flutter tests | `flutter test` — **PASS**؛ `+44: All tests passed!` |

## FAIL

لا توجد نتيجة **FAIL** نهائية في التحقق الأخير.

أثناء إضافة اختبارات resolver ظهرت نتيجتان اختباريتان غير صحيحتين: استخدام getter غير موجود (`allowed`) وتوقع `reason == null` رغم أن contract يحدد `reason == 'allowed'`. تم إصلاح test file فقط إلى `isAllowed` و`'allowed'`. بعد الإصلاح نجحت الاختبارات المركزة، ولم يتم تعديل production code بسبب هذين الخطأين.

كما فشل أمر مراجعة غير وظيفي حاول استخدام `git status` لأن مجلد المشروع ليس Git repository. عولج ذلك بإجراء المراجعة النصية المباشرة، ولا يمثل فشلًا في الكود أو acceptance criteria.

## BLOCKED — Academic Term Lifecycle

لم يتم اختراع collection أو fields جديدة لتنفيذ Academic Term transitions. توضح ADR-003 ومواد Feature 14 الحالات والسلوك المطلوب، لكن المصادر التي تم فحصها لا تقدم contract تخزين مكتملًا يحدد بصورة كافية:

- collection/document path الرسمي للفترات الأكاديمية؛
- أسماء كل حقول start/end/status transition؛
- بنية audit الخاصة بكل transition؛
- علاقة الفترة الحالية بالـsubjects/subscriptions عند الانتقال الفوري.

لذلك فإن تنفيذ callable transitions الآن سيخالف قاعدة عدم اختراع Database schema، وقد يغيّر business rules المعتمدة. هذا الجزء مصنف **BLOCKED** وليس **FAIL**.

**أصغر إجراء مطلوب لفك الحظر:** اعتماد schema/contract صريح للفترات الأكاديمية وحقول transition/audit من Platform Owner، ثم تنفيذ server-side transitions في callable transaction مع اختباراتها. لا ينبغي تعديل الكود الحالي لتخمين هذه البنية.

## NOT TESTED

| البند | الحالة والسبب |
|---|---|
| Figma/pixel-level visual acceptance | **NOT TESTED**؛ تم فحص وثيقة التصميم المحلية ووجود Presentation Scaffolding، لكن لا توجد جلسة Figma تفاعلية أو acceptance بصري يدوي يمكن اعتمادها كاختبار نهائي. هذا لا يمنع التحقق البرمجي. |
| Android/iOS runtime | **NOT TESTED**؛ لا يوجد emulator Android/iOS في البيئة. |
| Firebase production deployment | **NOT TESTED**؛ تم استخدام Emulator فقط، ولم يتم تنفيذ deploy أو اختبار بيانات production. |
| Real external payment provider | **NOT TESTED**؛ لا يوجد checkout/provider ضمن النطاق الحالي، وتم التحقق فقط من عدم إدخال payment implementation جديد. |

## الملفات الرئيسية التي تم تعديلها

تم تعديل ملفات dependency وSecurity Rules والاختبارات وطبقات Feature 14، ومن أبرزها:

| المسار | الغرض |
|---|---|
| `security-tests/package.json` و`security-tests/package-lock.json` | ترقية Rules Unit Testing إلى 5.0.1 المتوافق مع Firebase 12. |
| `security-tests/rules.test.js` | إضافة حالات Subject Access الثماني داخل الاختبارات الموجودة. |
| `firestore.rules` | Subject Access server-only mutations، delegated administrative reads، Center-only Chat، وتقييد Chat notifications. |
| `firestore.indexes.json` | كان يحتوي الفهارس المعتمدة؛ لم يتم تعديله أثناء آخر validation. |
| `functions/src/index.ts` | `setSubjectAccess`، approval attribution، delegated authorization، entitlement guards، Student Type conversion، وإزالة Gift callable. |
| `lib/features/subject_access/**` | mutation contract منفصل وcallable wiring مع إبقاء read contracts. |
| `lib/features/membership/**` | Entitlement decision/resolver، Active Plan lookup، إزالة Gift API، وproviders. |
| `lib/features/student_dashboard/**` | subject access states، filtering، والحماية من فتح المواد غير المسموح بها. |
| `lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart` | Center-only Chat ورفض fallback غير الصالح لـStudent Type. |
| `lib/features/admin/presentation/screens/admin_home_screen.dart` | Approval workflow UI ضمن Admin Home الحالية. |
| `test/membership/entitlement_resolver_test.dart` | اختبارات ترتيب entitlement. |
| اختبارات Subject Access وVideo entitlement | تحديث fakes/compatibility فقط للحفاظ على contracts الحالية. |

## الخلاصة النهائية

**Feature 14 ليست مكتملة بالكامل بعد.** الجزء الأكبر من Membership Plans وSubject Access وApproval Integration وUnified Entitlement تم تنفيذه والتحقق منه بنجاح، وجميع اختبارات Flutter النهائية وSecurity Rules Emulator validation نجحت. لكن Academic Term server-side lifecycle ما زال **BLOCKED** بسبب غياب schema تخزين مكتملة ومعتمدة تسمح بالتنفيذ دون اختراع Database structure. كما أن الاختبارات البصرية وproduction runtime مصنفة **NOT TESTED**.

لا يوجد سبب تقني حالي لتعديل Video/Auth/Device Binding، ولا توجد نتيجة FAIL نهائية تستوجب تغيير architecture أو business rules.

## المراجع المحلية

1. `05_DATABASE_v1.8.md` — Database v1.8 المعتمد.
2. `feature_14_database_change_authority.md` — Database Change Authority.
3. `feature_14_membership_plans_implementation_plan.md` — خطة تنفيذ Feature 14.
4. `docs/notion/00_MASTER_ARCHITECTURE.md` — المرجع المعماري الأعلى.
5. `docs/notion/FINAL_DECISIONS.md` — القرارات النهائية المعتمدة.
6. `16_ADR_003_Academic_Term_Lifecycle.md` — ADR-003 الخاص بدورة Academic Term.
7. `firestore.rules` و`firestore.indexes.json` — قواعد وفهارس Firebase الحالية.
