# Feature 14 — Membership Plans
## Updated Implementation Planning Report

**المشروع:** Dr. Tarek Platform  
**نوع المخرج:** Implementation Planning Report فقط  
**حالة التنفيذ:** لم يبدأ التنفيذ. لا تعديل على كود التطبيق، أو Cloud Functions، أو Firestore Rules، أو Database schema. لا اختبارات جديدة ولا build ضمن هذه المرحلة.  
**المرجع الأعلى:** `docs/notion/00_MASTER_ARCHITECTURE.md`  
**المرجع الوظيفي الأساسي:** `pasted_content_7.txt`  
**تحديث القرارات:** `pasted_content_8.txt` — Teacher (Platform Owner) Decision Update  
**Baseline:** `membership_plans_audit_gap_analysis.md`  
**التاريخ:** 15 أغسطس 2026

> **الغرض:** تحويل قرارات Teacher الصريحة إلى خطة تنفيذ قابلة للتقسيم، مع فصل ما حُسم نهائيًا عما لا يزال يحتاج قرارًا. هذه الوثيقة لا تنفذ أي إصلاح ولا تعيد فتح قرار محسوم.

## 1. Executive Summary

أصبحت Membership **subject-scoped إلزاميًا**. كل مادة لها اشتراك مستقل لكل طالب، وكل entitlement يجب أن يُحل مقابل اشتراك المادة الحالية، وليس مقابل خطة global على مستوى الحساب. public_student يملك `public_free` فقط، ولا يملك Center Chat أو تجربة Center communication notifications. center_student يملك `center_free` و`center_pro` و`center_max`، ويمكنه استخدام Center Chat وتجربة Center communication notifications وفق Feature Matrix.[1]

تم حذف Gift Membership من النسخة الحالية بالكامل من نطاق التنفيذ والخطة والاختبارات والـ analytics والـ Feature Matrix. لا يجوز حذف حقول `is_gifted` و`gifted_by` من الإنتاج أو تعديل Database specification بصمت؛ المطلوب أولًا إعداد Database Decision Change / migration note ثم تنفيذ migration منفصلة بعد الاعتماد.[1]

لا توجد مدفوعات داخل المنصة في النسخة الحالية. الدفع يتم خارج التطبيق، ثم يسجل Admin أو Teacher الدفع يدويًا، ثم تنفذ عملية Membership assignment. لا يوجد checkout أو card payment أو gateway أو online renewal payment أو promo-code flow.[1]

## 2. Decisions Applied — Not Open for Reinterpretation

| القرار | ما تم تثبيته في الخطة |
|---|---|
| Chat | Center-only؛ Public Student لا يملك Chat. Center Chat يتكون من Admin Chat ثنائي الاتجاه وDoctor Channel أحادي الاتجاه للقراءة فقط. Doctor هو Teacher (Platform Owner)، وليس role جديدًا. |
| Chat scope | كل Doctor Channel مرتبط بمادة، والطالب يرى قنوات المواد التي هو enrolled فيها فقط. |
| Notifications | Center Student يحصل على Center communication/learning notifications. Public Student لا يحصل على هذه التجربة، مع إبقاء authentication/security/system notifications عند الحاجة. |
| Subscription scope | اشتراك مستقل لكل `(student_id + subject_id)`؛ exactly one active subscription لكل pair. |
| Dashboard subject model | الطالب يرى كل مواد grade/class group الخاصة به، مع subscription status مستقل لكل مادة. لا تُخفى المادة لمجرد عدم وجود اشتراك؛ المحتوى يظل محميًا بالـ entitlement. |
| Academic Year/Term visibility | لا يظهر Academic Year أو Term كحقل student-facing عادي. |
| Start Term | زر Teacher/Admin ينقل الحالة فورًا من NOT STARTED إلى STARTED، ويحفظها server-side ويسجل audit. ليس scheduling. |
| End Term | زر Teacher/Admin ينقل الحالة فورًا من STARTED إلى ENDED، ويحفظها server-side ويسجل audit. ليس future end date. |
| Gift Membership | محذوف بالكامل من current version: لا UI ولا callable ولا repository method ولا provider ولا analytics ولا Feature Matrix permission ولا business logic. |
| Payments | External payment فقط. Manual payment logging بواسطة Admin/Teacher، ثم Membership assignment. لا online checkout أو gateway أو subscription purchase داخل التطبيق. |
| Entitlement | Subject-scoped فقط: current student → current subject → subject subscription → active plan → plan_features → entitlement. |
| Student Types | `public_student` و`center_student` فقط؛ لا third type. Public = `public_free` فقط. Center = `center_free`/`center_pro`/`center_max`. |

## 3. Target Architecture

تتبع كل Feature حساسة السلسلة التالية:

```text
Current Student
    ↓
Current Subject
    ↓
Subscription for This Subject
    ↓
Active Plan
    ↓
plan_features
    ↓
Subject-Scoped Entitlement
    ↓
Feature Access
```

لا يجوز استخدام `global_plan` أو تحويل خطة مادة واحدة إلى authorization لكل المواد. يمكن أن يحتفظ الحساب بـ claims محدودة لأغراض login/device policy، لكن claims لا تستبدل subject-scoped entitlement.

```text
Grade / Class Group
    ↓
Assigned Subjects
    ↓
Subscription State per Subject
    ↓
Entitlement for Current Subject
    ↓
Content / Chat / Notifications / Membership Action
```

يكون Firestore وCloud Functions مصدر القرار الملزم للعمليات والتفويض. يستهلك Flutter contracts موحدة لتحسين UX وعرض الحالة، لكنه لا يكون مصدر authorization الوحيد.

## 4. Current Architecture Baseline

يحتوي المشروع على Domain entities لـ `MembershipPlan` و`PlanFeature` و`StudentSubscription`، و`MembershipRepository` و`MembershipRemoteDataSource` وRiverpod providers، إضافة إلى Cloud Functions تقرأ الخطط والـ features وتنفذ عمليات lifecycle حالية.[2] [3] [4] [5]

يوجد entitlement server-side واضح للفيديو والجودة وOffline وPDF access/download، ويستهلك Video resolver الاشتراك الخاص بالمادة عند إصدار signed URL.[6] هذه الأجزاء لا تُعاد كتابتها؛ المطلوب لاحقًا توحيد عقد القرار مع بقية consumers مع الإبقاء على server validation.

| المجال | الوضع الحالي من الـ Audit | أثر قرارات Teacher |
|---|---|---|
| Membership entities | موجودة subject-scoped، وتحتوي حقول gift legacy | إزالة gift من التنفيذ المستقبلي، مع migration note للحقول |
| Subscription operations | lifecycle موجود جزئيًا | الإبقاء على activation/upgrade/downgrade/renew/freeze/resume حسب policy؛ حذف gift |
| Feature Matrix | موجودة ومستخدمة بوضوح في Video/Offline/PDF | إضافة Chat/Notifications وغيرها فقط بعد key reconciliation |
| Student Dashboard | يحتاج subject list مع status لكل مادة | لا إخفاء شامل للمواد؛ لا Term/A.Y. في العرض الطلابي |
| Chat | لا entitlement contract موحد مثبت لكل قنوات Center | Center-only + subject-scoped + Doctor read-only |
| Notifications | لا تجربة Center communication موحدة مثبتة | Center-only للتجربة التعليمية/التواصلية، مع إبقاء system notifications |
| Term/System Settings | lifecycle موجود في سياق سابق لكنه يحتاج button transition exact | Start/End فوريان server-side ومؤرشفان |
| Payments | `payment_logs` collection موجودة | external/manual only؛ لا payment flow داخل Flutter |

## 5. Dependency Map

| Feature/Subsystem | يعتمد على | يقدم إلى | التغيير المطلوب في الخطة |
|---|---|---|---|
| Feature 02 — Student Dashboard | Student profile، grade/class group، assigned subjects، subject subscriptions، entitlement snapshot | Subject cards، status لكل مادة، navigation إلى current subject | عرض جميع المواد التابعة للمجموعة، إظهار Active/Expired/Plan/Not Active، وعدم عرض Academic Year/Term |
| Feature 12 — Chat | `student_type`، enrolled subject، subject subscription/entitlement، Teacher role | Admin Chat وDoctor Channel | Public blocked؛ Center allowed؛ Doctor channel read-only؛ subject isolation |
| Feature 13 — Notifications | `student_type`، notification category، applicable feature entitlement، subject scope عند الحاجة | Center communication/learning notifications وsystem notifications | Public blocked فقط من Center experience؛ لا حذف infrastructure العام |
| Feature 14 — Membership | Student Type، plans، plan_features، subject subscriptions، lifecycle، payment log | Entitlement decisions وsubscription status | source of subject-specific membership decisions |
| Term/System Settings | authorized Teacher/Admin، persisted term state، audit trail | current term state وgating context | START/END immediate server-side transitions؛ لا student-facing Term field |
| Payment Logging | external payment confirmation من خارج النظام، authorized actor | payment log ثم membership assignment | manual logging فقط؛ payment log لا يمنح access بذاته |
| Video Streaming | subject subscription + video feature keys | signed URL/player entitlement | reuse current resolver/security مع subject-scoped contract |
| PDF/Notes/Offline | subject subscription + corresponding feature key | content operation authorization | contracts فقط في مراحل Feature 14، دون إعادة بناء UI/DRM |

## 6. Files to Modify in Future Implementation

هذه قائمة تخطيطية فقط، ولا تعني أن التعديل بدأ.

| الملف/المجموعة | الغرض | حدود التعديل |
|---|---|---|
| `lib/features/membership/domain/entities/**` | typed subject subscription/plan/feature/entitlement contracts | لا global authorization ولا gift contracts |
| `lib/features/membership/domain/repositories/**` | subject-scoped membership operations وentitlement facade | حذف gift method من target design؛ عدم الكتابة المباشرة إلى protected collections |
| `lib/features/membership/data/**` | استدعاء backend وقراءة status لكل subject | لا payment gateway ولا checkout |
| `lib/features/membership/presentation/providers/**` | snapshot/status per subject وmutation states | لا provider لـ gift ولا global plan provider |
| `lib/features/student_dashboard/**` | subject list وsubscription status cards | لا إخفاء المواد غير المشتركة، ولا Term/A.Y. للطالب |
| `lib/features/chat/**` أو feature 12 implementation area | Center Chat وDoctor Channel contracts | public deny؛ subject enrollment؛ Doctor no-reply |
| `lib/features/notifications/**` أو feature 13 implementation area | Center communication notifications | لا إزالة system/auth/security notifications |
| `lib/features/term/**` أو System Settings area | Start/End immediate transitions | authorized server-side + audit |
| `lib/features/payment_logging/**` أو existing payment-log area | manual external payment logging | لا checkout أو gateway أو online renewal |
| `lib/features/video_streaming/data/services/video_source_resolver.dart` | استهلاك shared subject entitlement | لا إعادة بناء player أو signed URL security |
| `functions/src/index.ts` أو backend modules | policy، lifecycle، payment-linked assignment، chat/notification entitlement | authorization server-side |
| `firestore.rules` | فقط إذا أثبتت Emulator tests فجوة | لا فتح client writes |

## 7. Files and Areas That Must Not Be Modified

`00_MASTER_ARCHITECTURE.md` و`FINAL_DECISIONS.md` والـ approved architecture لا تُعدل. كما لا تُعاد كتابة Authentication أو Device Binding أو Video player internals أو Offline DRM لمجرد ربط entitlement.

لا تُحذف حقول `is_gifted` و`gifted_by` من Database specification أو production data ضمن Feature 14 implementation. تُسجل كم deprecated/removed في Database Decision Change / migration note، ثم يُنفذ أي حذف بعد اعتماد منفصل.[1]

لا يُنشأ أي UI نهائي لـ Membership قبل Figma/visual approval. ولا تُضاف ملفات Payment Gateway أو Checkout أو Promo Code أو Online Renewal إلى المشروع الحالي.

## 8. Backend Changes Required

### 8.1 Subject-scoped subscription service

يجب أن يقبل كل entitlement request `studentId` و`subjectId` و`featureKey`، وأن يتحقق من أن الطالب يرى أو يدرس المادة، ثم يقرأ subscription الخاصة بالpair فقط. لا يجوز أن يعيد service خطة account-global.

### 8.2 Student Type eligibility

يستخدم backend helper واحدًا:

| Student Type | Plans |
|---|---|
| `public_student` | `public_free` فقط |
| `center_student` | `center_free`, `center_pro`, `center_max` |

Public لا يحصل على Chat أو Center communication notification entitlement حتى لو وُجدت feature key في plan data. Center يحصل عليهما فقط عند تحقق Student Type والـ applicable feature entitlement.

### 8.3 Chat authorization

يجب أن يميز backend بين `admin_chat` و`doctor_channel`. Admin Chat ثنائي الاتجاه. Doctor Channel مرتبط بمادة، والطالب يستطيع القراءة فقط؛ أي reply من الطالب يُرفض server-side. Doctor ليس role جديدًا؛ هو `teacher`، المعروض كـ Teacher (Platform Owner). يجب التحقق من enrolled-subject relationship قبل القراءة أو الإرسال.

### 8.4 Notifications authorization

يُحافظ على system/auth/security notifications. أما communication/learning notification experience فتحتاج resolver يعتمد على `student_type` وapplicable feature entitlement، ويمنع Public Student من Center categories فقط.

### 8.5 Term operations

يحتاج backend إلى عمليتين محميتين دلاليًا مثل `startTerm` و`endTerm` وفق convention المشروع. `startTerm` يكتب الحالة STARTED فور الضغط، و`endTerm` يكتب ENDED فور الضغط. يجب رفض start غير المصرح به وend غير المصرح به، وحفظ actor وtimestamp وprevious/new state في audit. لا تُنشأ future-start أو future-end states إلا إذا وثيقة أخرى معتمدة فرضتها.

### 8.6 External payment and membership assignment

لا ينشئ النظام payment intent أو checkout. التدفق هو:

```text
External Payment Outside Platform
        ↓
Authorized Teacher/Admin records payment
        ↓
Payment Log
        ↓
Membership Assignment / Mutation
        ↓
Subject-Scoped Entitlement
```

`payment_logs` لا يمنح access تلقائيًا بمجرد وجود السجل. يجب أن تكون membership assignment عملية مستقلة ومصرحًا بها، وأن تتحقق من الطالب والمادة والخطة والـ Student Type، مع منع تكرار العملية والـ duplicate active subscription.

### 8.7 Gift removal

لا تُضاف أي callable أو repository/provider/analytics أو feature permission لـ Gift Membership. أي existing implementation references لـ `is_gifted` و`gifted_by` تُعامل كـ deprecated compatibility fields حتى تعتمد Database migration، ولا تُستخدم في current-version business flow.

## 9. Database Changes Required

لا يتم تعديل schema بصمت.

| الحاجة | وضعها |
|---|---|
| Subject-scoped subscriptions | موجودة ومُلزمة: one active per `(student_id + subject_id)` |
| Student Type values | موجودة/معتمدة: Public وCenter فقط |
| `payment_logs` | تبقى valid للمدفوعات الخارجية المسجلة يدويًا |
| Term state/audit | يجب مطابقة collection الحالية؛ إن لم تكفِ، يُرفع schema decision قبل الإضافة |
| Chat subject channels | يجب توثيق subject relation وdoctor channel mode إذا لم تكن موجودة في Database docs |
| Notification categories | يجب توثيق category/subject scope إذا لم تكن schema الحالية تكفي |
| `is_gifted`, `gifted_by` | deprecated/removed من Membership current version، لكن لا حذف قبل Database Decision Change/migration approval |
| idempotency/operation log | أي collection جديدة تحتاج تحديث 05_DATABASE وRules قبل التنفيذ |

المطلوب الأول في Database work هو إعداد **Database Decision Change / migration note** للحقول gift، وليس حذفها مباشرة.

## 10. Security Rules Changes Required

المبدأ هو إبقاء direct client writes إلى plans وplan_features وsubscriptions وstudent_type وterm state وpayment logs مغلقة أو محدودة حسب القواعد الحالية، وتمرير mutations عبر Cloud Functions.

| المجال | القاعدة المطلوبة |
|---|---|
| Membership | الطالب لا يكتب subscription أو plan مباشرة |
| Subject isolation | الطالب يقرأ فقط subjects/subscriptions/channels المسموحة له |
| Chat | Public deny؛ Center subject-scoped؛ Doctor channel no student write |
| Notifications | Public deny لفئات Center communication فقط؛ system notifications لا تُحذف تلقائيًا |
| Term | Teacher/Admin فقط يستطيع Start/End؛ الطالب لا يكتب state |
| Payments | Teacher/Admin فقط يسجل external payment log؛ الطالب لا يكتب payment log |
| Student Type | لا client mutation؛ conversion/assignment server-side |
| Gift | لا rules/path جديدة current version |

لا يضاف Rule إلا إذا ثبت gap فعلي في Emulator/security review، ولا تُفتح collection جديدة ليلًا عبر permissive wildcard.

## 11. Claims and Entitlement Changes

الـ entitlement يظل subject-scoped ولا يوضع في claim global. `student_type` يمكن أن يبقى claim account-level، لكن Chat وNotifications وcontent access لا تعتمد على claim وحده؛ يجب أن تمر عبر current subject subscription وplan_features.

يجب الحذر خصوصًا من `plan_id` و`max_devices` إذا كانت الاشتراكات متعددة المواد. لا تُحدّث claims membership إلا للقيم التي يحتاجها consumer محدد وبـ scope واضح. Chat وnotification category authorization يجب أن يكون server-resolved، لا مجرد `student_type == center_student` في Flutter.

## 12. Term/System Settings Dependency

| العملية | قبل | بعد | المتطلبات |
|---|---|---|---|
| Start Term | NOT STARTED | STARTED فورًا | authorized Teacher/Admin، server persistence، audit |
| End Term | STARTED | ENDED فورًا | authorized Teacher/Admin، server persistence، audit |

لا يظهر Academic Year/Term للطالب كحقل عادي. إذا كان Term state يؤثر على membership/content availability، فيجب أن يضاف ذلك إلى entitlement resolver صراحة بعد توثيق القاعدة؛ لا يُفترض أن انتهاء term يلغي subscription تلقائيًا لأن هذا غير مقرر في `pasted_content_8.txt`.

## 13. Required Test Matrix

| # | الاختبار المطلوب | النتيجة المتوقعة |
|---:|---|---|
| 1 | Public Student يفتح Center Chat | رفض |
| 2 | Center Student يفتح Chat | سماح عند تحقق entitlement |
| 3 | Public Student يقرأ Center communication notifications | رفض |
| 4 | Center Student يستقبل communication notifications | سماح عند تحقق entitlement |
| 5 | Dashboard يعرض كل subjects التابعة لـ grade/class | لا تُخفى المادة بسبب غياب subscription |
| 6 | كل subject يعرض subscription state الخاص به | Active/Expired/Plan/Not Active لكل مادة |
| 7 | اشتراك Subject A لا يخول Subject B | رفض |
| 8 | Subject A entitlement يستخدم Subscription A | نجاح/رفض مستقل |
| 9 | Subject B entitlement يستخدم Subscription B | نجاح/رفض مستقل |
| 10 | Start Term | server state = STARTED فورًا |
| 11 | End Term | server state = ENDED فورًا |
| 12 | unauthorized Start Term | رفض ولا تغيير state |
| 13 | unauthorized End Term | رفض ولا تغيير state |
| 14 | Gift Membership executable operation | غير موجود/غير قابل للاستدعاء |
| 15 | In-app payment/checkout | غير موجود |
| 16 | manual external payment log | يعمل فقط لـ Teacher/Admin |
| 17 | payment log وحده | لا يتجاوز membership authorization |

تضاف إلى ذلك اختبارات concurrency وidempotency للـ subscription pair، اختبارات Chat Doctor Channel read-only، اختبارات عدم تسرب subject data، واختبارات regression للفيديو وPDF وOffline.

## 14. Implementation Order

| المرحلة | النطاق | شرط الخروج |
|---|---|---|
| 0 | تثبيت key catalog وsubject scope وcurrent schema map | لا global membership ولا keys مخترعة |
| 1 | Subject entitlement contract | unit tests للـ current subject resolution |
| 2 | Membership operations وmanual payment assignment | authorization + idempotency tests |
| 3 | Dashboard subject model | subject list/status tests؛ لا Term/A.Y. في student UI |
| 4 | Chat entitlement and channel rules | Public blocked، Center allowed، Doctor read-only |
| 5 | Notification category entitlement | Center communication فقط؛ system notifications محفوظة |
| 6 | Term Start/End operations | immediate persistence + audit + security tests |
| 7 | Video/PDF/Notes/Offline adapters | reuse current security and subject resolver |
| 8 | Database Decision Change for deprecated gift fields | approval قبل migration |
| 9 | final Membership UI بعد Figma | widget/runtime validation |
| 10 | full platform validation | PASS/FAIL/BLOCKED report لكل منصة |

## 15. Genuine Remaining Blockers

القرارات التالية لم تُحسم في `pasted_content_8.txt`، ولذلك تبقى blockers حقيقية ولا يجوز اختراع إجابة لها:

1. **Student Type conversion:** عند تحويل طالب Center إلى Public أو العكس، ما مصير الاشتراكات الحالية غير المتوافقة؟ هل تُحوّل إلى Free matching target أم تُطلب تسوية لكل مادة أم يُرفض التحويل حتى يقرر المسؤول؟
2. **Freeze/Resume semantics:** هل يوقف freeze entitlement فورًا؟ وهل يمدد end date بعد resume؟ وهل lifetime قابل للتجميد؟
3. **Subscription duration arithmetic:** طريقة حساب weekly/monthly/semester/annual وrenewal بعد expiration.
4. **Feature keys غير الموحدة:** المفاتيح الدقيقة لـ Preview Duration وVideo Download وQuiz/Exam/Notes/Chat/Notifications/PIP/Export وغيرها إذا لم تكن موجودة في code/schema الحالي.
5. **Payment-to-assignment operation contract:** هل يسجل Teacher/Admin payment ثم ينفذ assign كخطوتين مستقلتين أم callable orchestration واحدًا، مع الحفاظ على أن payment log وحده لا يمنح access؟
6. **Term interaction with access:** هل STARTED/ENDED يؤثر في أي entitlement أم أنه system state/audit فقط؟
7. **Chat/notification data schema:** إذا لم تكن subject channel/category collections موثقة، يلزم Database decision قبل التنفيذ.
8. **Idempotency storage:** هل سيُستخدم deterministic subscription record أم coordination/operation log يحتاج schema جديدًا؟
9. **Final Membership UI/Figma:** لا يمكن اعتماد الشكل النهائي قبل المرجع البصري المطلوب.

## 16. Final Status

Feature 14 **لم تُنفذ** في هذه المرحلة. تم تحديث الخطة لتطبيق قرارات Teacher العشرة، وإزالة Gift Membership والمدفوعات الداخلية من نطاق التنفيذ، والإبقاء على external payment/manual logging، وإضافة dependencies والاختبارات المطلوبة.

أي مرحلة تنفيذ لاحقة يجب أن تبدأ بقرار Database Change للحقول deprecated الخاصة بـ Gift، ثم key/schema reconciliation، ثم subject-scoped entitlement وmanual payment assignment، قبل بناء أي UI نهائي.

## References

[1]: ../pasted_content_8.txt "Teacher Platform Owner Decision Update — Feature 14"
[2]: ../pasted_content_7.txt "Feature 14 Implementation Planning Review"
[3]: ./membership_plans_audit_gap_analysis.md "Feature 14 Audit & Gap Analysis baseline"
[4]: ../docs/notion/00_MASTER_ARCHITECTURE.md "Master architecture reference"
[5]: ../docs/notion/FINAL_DECISIONS.md "Approved final decisions"
[6]: ../docs/notion/04_FEATURES.md "Functional feature reference"
[7]: ../docs/notion/05_DATABASE.md "Database reference"
[8]: ../docs/notion/06_FIREBASE_ARCHITECTURE%20.md "Firebase architecture reference"
[9]: ../lib/features/membership/domain/entities/membership_plan.dart "MembershipPlan entity"
[10]: ../lib/features/membership/domain/entities/plan_feature.dart "PlanFeature entity"
[11]: ../lib/features/membership/domain/entities/student_subscription.dart "StudentSubscription entity"
[12]: ../lib/features/membership/domain/repositories/membership_repository.dart "Membership repository contract"
[13]: ../lib/features/membership/data/datasources/membership_remote_data_source.dart "Membership remote datasource"
[14]: ../functions/src/index.ts "Membership Cloud Functions"
[15]: ../firestore.rules "Firestore security rules"
[16]: ../lib/features/video_streaming/data/services/video_source_resolver.dart "Video entitlement integration"
