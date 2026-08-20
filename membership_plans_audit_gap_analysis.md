# Feature 14 — Membership Plans
## Audit & Gap Analysis

**المشروع:** Dr. Tarek Platform  
**نطاق المهمة:** تدقيق فقط؛ لا تعديل كود، لا إنشاء اختبارات، لا تشغيل اختبارات أو build، ولا تنفيذ إصلاحات.  
**تاريخ التدقيق:** 15 أغسطس 2026  
**المُعدّ:** Manus AI

> **الخلاصة التنفيذية:** توجد نواة تنفيذية حقيقية لـ Feature 14 عبر كيانات Membership، Repository، Cloud Functions، Firestore Rules، Riverpod providers، وVideo Entitlement. لكنها لا تحقق Feature 14 كاملة كما تصفها الوثائق. التنفيذ الحالي أقرب إلى **Membership Operations + Video Entitlement جزئي** منه إلى نظام Membership Plans متكامل ذي Feature Matrix شاملة وواجهة إدارية وعميل طالب متكاملين.

## 1. حدود التدقيق والمرجع الأعلى

اعتمد التدقيق على `00_MASTER_ARCHITECTURE.md` باعتباره المرجع الأعلى، ثم على القرارات والوثائق الوظيفية وقاعدة البيانات وFirebase وFlutter ذات الصلة. لم تُعتبر المواصفة الجديدة قرارًا معماريًا مستقلًا، ولم تُستخدم لتغيير Authentication أو Device Binding أو Database schema أو Video Streaming. يقتصر هذا التقرير على **الحالة الحالية** و**الفجوات** و**الملفات المتأثرة المحتملة مستقبلًا**.

تعرّف الوثيقة الوظيفية Feature 14 على Membership Plans باعتبارها نظامًا يدير وصول الطالب وفق Student Type وMembership Plan، مع تحكم مستقل في القدرات عبر Feature Matrix، وتضع Student Type وMembership Plan ضمن شروط ما قبل التفعيل.[1] كما تشترط أن تُسجل تغييرات العضوية والتحليلات، وأن تحفظ تغييرات الخطة بيانات الطالب وتقدمه وتاريخه.[1]

## 2. الحكم العام على الحالة الحالية

| المحور | الحالة الحالية | الحكم |
|---|---|---|
| Domain entities | موجودة، لكنها DTOs بسيطة نسبيًا | **Partial** |
| Repository/data source | موجودة وتغطي عدة عمليات | **Implemented surface** |
| Backend mutations | موجودة لمعظم العمليات المذكورة | **Partial / policy gaps** |
| Student Type rules | موجودة جزئيًا في الاعتماد واختيار الخطة | **Partial** |
| Feature Matrix | موجودة كـ `plan_features` وتُستخدم للفيديو | **Partial** |
| Entitlement enforcement | قوي نسبيًا للفيديو، غير موحد لبقية المنصة | **Partial** |
| Admin dashboard | شاشة جودة فيديو محدودة فقط ضمن ما تم العثور عليه | **Insufficient for Feature 14** |
| Student membership UI | عرض أولي للخطط فقط | **Insufficient** |
| Claims synchronization | موجود عند الاعتماد وتسجيل الدخول | **Partial / freshness risk** |
| Security Rules | تمنع الكتابة المباشرة وتحد القراءة | **Baseline only** |
| Lifecycle integrity | عمليات موجودة مع فجوات atomicity والاتجاهات | **Gap** |
| Automated tests | اختبار entitlement للفيديو فقط ضمن ما تم العثور عليه | **Insufficient** |
| Runtime validation | لم تُشغّل وفق نطاق التدقيق | **Not performed by design** |

**القرار التدقيقي:** Feature 14 **ليست مكتملة** وفق الوثائق المعتمدة. لا يوجد دليل على اكتمال جميع القدرات أو كل مسارات الإدارة والتحليلات، ولذلك لا يجوز إعلانها Production-complete بناءً على وجود الملفات والـ functions فقط.

## 3. خريطة التنفيذ الحالية

### 3.1 طبقة Domain

يعرّف `MembershipRepository` عمليات قراءة الخطط والخصائص والاشتراك الخاص بمادة، إضافة إلى `activateFreePlan` و`upgrade` و`downgrade` و`renew` و`freeze` و`resume` و`gift`.[2] هذا السطح يطابق جزءًا مهمًا من قائمة العمليات الوظيفية، لكنه لا يعرّف واجهة مستقلة لتغيير Student Type، أو تعيين خطة إداريًا، أو تقييم Entitlement موحد لكل قدرات المنصة.

`MembershipPlan` يحتوي على `id` و`planName` و`planKey` و`studentType` و`displayOrder` و`isActive`، ولا يحتوي على تمثيل مدمج لـ Feature Matrix أو تسعير أو محتوى تسويقي أو مدة أو حدود أجهزة.[3] أما `PlanFeature` فيحتوي على `featureKey` و`enabled` و`featureValue` الديناميكي، دون نوع موحد للمفاتيح والقيم أو تحقق domain-level للقدرات المدعومة.[4]

`MembershipSubscription` يمثل اشتراكًا subject-scoped ويحتوي على `status` و`startDate` و`endDate` وبيانات freeze/resume وgift و`renewalCount` و`previousPlanId`.[5] ويحسب `termLifecycle` محليًا؛ إذ يعتبر الاشتراك ذي `endDate == null` نشطًا محليًا ما دام تاريخ البدء قد حل، بينما تُحسم صلاحية بعض العمليات الخلفية أيضًا عبر `assertSubjectAccess`. هذا التوزيع يخلق خطر اختلاف تفسير الحالة بين العميل والخادم، خصوصًا عند وجود سجل بلا `endDate`.

### 3.2 طبقة Data وProviders

`MembershipRemoteDataSource` يقرأ الخطط النشطة حسب `student_type`، ويقرأ الاشتراك النشط حسب `student_id + subject_id`، ويقرأ `plan_features`، بينما تمرر عمليات التغيير إلى Cloud Functions ثم تعيد قراءة الاشتراك النشط.[6] `MembershipRepositoryImpl` هو adapter تمريري تقريبًا ولا يضيف orchestration أو policy.[7]

تقدم `membership_providers.dart` أربعة أسطح رئيسية: الخطط المتاحة، الاشتراك النشط، خصائص الخطة، وboolean access لخاصية واحدة.[8] لا يوجد في الطبقة المقروءة Membership/Entitlement facade موحد يعيد جميع صلاحيات الطالب للمنصة أو يحافظ على snapshot متسق بين الشاشة والفيديو وPDF والاختبارات والدردشة والتنزيلات.

### 3.3 طبقة Backend

توجد Cloud Functions فعلية لتفعيل الخطة المجانية، الترقية، التخفيض، التجديد، التجميد، الاستئناف، والإهداء. كما توجد `onStudentApproved` لتحديد Student Type والخطة الافتراضية وتحديث Custom Claims، وتوجد `enforceOneSubscriptionPerSubject` لمعالجة التكرار بعد إنشاء السجل.[9]

يوجد أيضًا `setPlanQualityFeature` لتعديل خصائص جودة الفيديو، و`generateBunnySignedUrl` للتحقق من الاشتراك subject-scoped و`video.access` وخصائص الجودة قبل إصدار الرابط الموقّع، و`revalidateOfflineAccess` لتقييم `offline.mode` وإرسال إشعارات revocation.[10] هذه أجزاء حقيقية ومهمة، لكنها لا تمثل وحدها Feature Matrix كاملة لكل القدرات المذكورة في الوثيقة.

## 4. مطابقة القواعد التجارية

| القاعدة المرجعية | دليل التنفيذ الحالي | الحالة | ملاحظة التدقيق |
|---|---|---|---|
| Student Types هما Public وCenter | `onStudentApproved` يتحقق من `public_student` و`center_student` | **Partial** | لا يظهر في البحث callable مستقل لتحويل Student Type من نوع إلى آخر. |
| Student Type يحدد الخطط المتاحة | `getPlans` يرشح حسب `student_type`، و`activateFreePlan` يتحقق من التطابق | **Implemented partially** | واجهة الطالب تستخدم fallback باسم `'student'` عند غياب النوع، وهو غير مطابق للقيم الرسمية. |
| Public Student يحصل على Public Free فقط | الاعتماد يحل default plan المطابق للنوع؛ لا يظهر enforcement شامل لكل حالات العرض والتغيير | **Partial** | يلزم إثبات server-side وUI للمنع الكامل من خطط Center. |
| Center Student يتاح له Center Free/Pro/Max | الاستعلام حسب النوع يسمح بالخطط النشطة المطابقة | **Partial** | لا يوجد تدقيق مركزي يثبت أن مجموعة الخطط المسموحة محصورة بهذه الخطط عند كل mutation. |
| Student لا يغير Student Type ذاتيًا | لم يظهر مسار طالب لتغيير النوع، والـ rules تمنع الكتابة المباشرة | **Partial** | لا يوجد audit مثبت لمسار admin/teacher لتغيير النوع نفسه. |
| الخطط لا تحتوي صلاحيات hardcoded | `plan_features` و`getPlanFeatures` موجودان | **Partial** | enforcement الشامل موجود بوضوح للفيديو وبعض offline فقط، وليس لكل capability المذكورة. |
| عمليات upgrade/downgrade/renew/gift/freeze/resume | Cloud Functions وRepository methods موجودة | **Implemented surface** | صحة directionality، atomicity، والقيود التجارية ليست مكتملة الإثبات. |
| التغييرات لا تفقد بيانات الطالب | لا توجد عملية حذف progress/notes/quizzes/exams في مسارات التغيير المقروءة | **Not proven** | غياب الحذف لا يثبت وجود اختبارات preservation أو transaction guarantees. |
| مدة العضوية configurable | `duration_type` و`start_date` و`end_date` موجودة | **Partial** | `MembershipPlan` نفسه لا يمثل مدة الخطة؛ منطق المدة موزع في backend/subscription. |
| التحليلات تسجل التوزيع والترقيات والانخفاضات والتجديد والانتهاء والنشاط | توجد `writeAnalyticsEvent` لعدة mutation events | **Partial** | لا يوجد دليل كافٍ على dashboards/aggregates أو تسجيل كل مؤشرات Feature 14 المطلوبة بدقة. |
| حدود الأجهزة من Feature Matrix | `onStudentApproved` و`onLoginAttempt` يقرآن `device.max_count` | **Partial** | يوجد enforcement في login، لكن لا يوجد تدقيق كامل لقواعد عدم قابلية التغيير للخطط الثلاث الأولى وموافقة Teacher لـ Center Max. |

## 5. Membership Lifecycle وغياب التناسق الذري

`enforceOneSubscriptionPerSubject` يعمل كـ `onDocumentCreated` بعد إنشاء السجل، ثم يحدد السجلات المكررة ويحذف/يغير حالة السجل الجديد ويسجل analytics.[9] هذا ليس transaction أو precondition يمنع التكرار قبل الكتابة. لذلك تبقى نافذة زمنية يمكن أن تحتوي على أكثر من سجل active، وقد يرى قارئ يستخدم `limit(1)` نتيجة غير حتمية قبل اكتمال trigger.

كما أن `activateFreePlan` يتحقق من وجود active subscription قبل الإنشاء، لكن فحص الوجود ثم الإنشاء ليس موثقًا كعملية atomic transaction أو idempotent request. يلزم اعتبار هذا **Integrity Gap** وليس مجرد نقص اختبار.

عمليات `upgrade` و`downgrade` تستخدم validator يتحقق من أن الخطة active وأن `student_type` متطابق. من القراءة الحالية لا يظهر تحقق واضح من أن الترقية يجب أن تتحرك إلى خطة أعلى أو أن التخفيض يجب أن يتحرك إلى خطة أدنى. كما لا يظهر enforcement صريح لتغيير Student Type المصاحب للتحويل Public↔Center، رغم أن Feature 14 تعد التحويل قدرة إدارية مستقلة.[1]

`MembershipSubscription.termLifecycle` يعامل `endDate == null` كحالة active محليًا، بينما الوثائق وقواعد التدقيق السابقة للمشروع تشدد على أن نهاية الاشتراك يجب أن تكون صريحة عندما تكون العضوية زمنية. هذا اختلاف مهم بين domain interpretation وقاعدة membership lifecycle المحتملة، ويحتاج قرارًا موثقًا قبل أي إصلاح.

## 6. Feature Matrix وEntitlements

الـ Feature Matrix ممثلة في Firestore عبر `plan_features`، وكل سجل يملك `feature_key` و`feature_value` و`enabled`. هذا يوفر أساسًا جيدًا للتهيئة، لكن النموذج الديناميكي لا يفرض قائمة capabilities أو schema لقيمها. ونتيجة ذلك أن أخطاء key أو value قد تمر حتى لو لم تكن مدعومة من أي consumer.

التنفيذ الحالي يستخدم صراحة مفاتيح `video.access` و`video.quality.*` و`video.quality.max` داخل `VideoEntitlementService` و`generateBunnySignedUrl`، ويستخدم `offline.mode` داخل `revalidateOfflineAccess`.[10] لم يظهر في التدقيق enforcement مماثل لـ PDF وQuiz وExam وNotes وChat وPicture-in-Picture وExport وNotifications وSecurity Features، وهي capabilities منصوص عليها في Feature 14.[1]

| Capability في Feature Matrix | Consumer/enforcement ظاهر | الحكم |
|---|---|---|
| `video.access` | `VideoEntitlementService` و`generateBunnySignedUrl` | **Implemented for video** |
| `video.quality.*` | خدمة الفيديو و`setPlanQualityFeature` | **Implemented partially** |
| `offline.mode` | `revalidateOfflineAccess` | **Backend check present** |
| Device limit | claims + `onLoginAttempt` | **Implemented partially** |
| PDF access | لا consumer واضح في نطاق التدقيق | **Gap / not evidenced** |
| Quiz access | لا consumer واضح | **Gap / not evidenced** |
| Exam access | لا consumer واضح | **Gap / not evidenced** |
| Notes / Chat | لا consumer واضح | **Gap / not evidenced** |
| PiP / Export / Notifications | لا consumer موحد واضح | **Gap / not evidenced** |
| Preview duration / preview lectures | لا enforcement كامل واضح | **Gap / not evidenced** |

هناك أيضًا ازدواج في entitlement logic للفيديو: العميل يقرأ subscription وfeatures محليًا عبر `VideoEntitlementService`، والخادم يعيد التحقق بشكل مستقل قبل إصدار signed URL. الازدواج مطلوب أمنيًا من حيث المبدأ، لكنه يحتاج contract موحدًا للـ feature keys وسبب الرفض حتى لا تختلف UX عن قرار الخادم.

## 7. Claims والمزامنة

تحديث claims عند اعتماد الطالب يضع `student_type` و`plan_id` و`max_devices` و`subscription_status` و`approved` ضمن claims.[9] كما أن مسار bootstrap/login يحل خطة المستخدم ويستخدم `max_devices` في Device Binding. هذا يدعم قرارات الأمان المعتمدة، لكنه يخلق مسألة freshness: تغييرات membership اللاحقة لا يظهر من السطح المقروء أنها تحدث claims دائمًا بعد كل upgrade/downgrade/renew/freeze/resume/gift.

بالتالي يوجد فرق محتمل بين **مصدر authorization server-side الحالي في Firestore** وبين **claims snapshot** المستخدم في الدخول وDevice Binding. لا يمكن اعتبار claims مصدرًا كافيًا لكل entitlement متغير دون آلية refresh موثقة بعد mutation أو دون حصر استخدام claims في القيم التي يسمح بتأخرها.

## 8. Security Rules والحدود الأمنية

تمنع `firestore.rules` الكتابة المباشرة من العميل إلى `plans` و`plan_features` و`subscriptions`، وتسمح بقراءة محدودة للخطط النشطة والخصائص المفعلة واشتراك الطالب نفسه. هذه حماية أساسية جيدة لأنها تدفع mutations إلى Cloud Functions.

لكن Rules لا تنفذ وحدها uniqueness لكل `student_id + subject_id`، ولا تتحقق من اتجاه upgrade/downgrade، ولا من مدة الاشتراك أو freeze semantics، ولا من صحة `feature_key` و`feature_value`. هذه القيود يجب أن تكون server-side داخل functions أو transaction layer، وتحتاج اختبارات authorization وinvariant مستقلة.

توجد نقطة تدقيق إضافية في `generateBunnySignedUrl`: الدالة تحل الاشتراك حسب subject، ثم تتحقق من خطة الاشتراك و`video.access` والجودة المطلوبة. هذا جيد للمحتوى المدفوع، لكنه لا يثبت دعم Public Free preview duration أو preview lectures كما تنص Feature 14؛ إذ لا يظهر في المسار المقروء enforcement للمدة أو عدد المحاضرات preview.

## 9. واجهة المستخدم والتكامل الوظيفي

واجهة `MembershipPlansScreen` في `student_feature_hub_screen.dart` تعرض قائمة الخطط من `availablePlansProvider` وتستخدم `user.studentType ?? 'student'` كقيمة fallback. هذا fallback لا يطابق `public_student` و`center_student` المعتمدين، وقد يؤدي إلى قائمة فارغة أو سلوك غير متوقع عندما لا تكون القيمة موجودة.

الشاشة الحالية تعرض اسم الخطة و`planKey` في بطاقات، لكنها لا تعرض في السطح المقروء الخطة الحالية، حالة الاشتراك، تاريخ الانتهاء، Feature Matrix، الفروقات بين الخطط، أو أزرار upgrade/downgrade/renew/freeze/resume/gift. لذلك فهي **عرض خطط أولي** وليست Membership Management UX كاملة.

أما `PlanQualityMatrixScreen` فهي شاشة إدارية محددة لجودة الفيديو باستخدام `CupertinoSwitch`. هذا ينسجم مع قرار استخدام `CupertinoSwitch` لعناصر التفعيل، لكنه لا يمثل Dashboard Feature Matrix العامة التي تتحكم في PDF وQuiz وExam وNotes وChat وOffline وExport وغيرها.

## 10. الاختبارات والتحقق

لم تُشغّل اختبارات أو build ضمن هذه المهمة، التزامًا بنطاق Audit-only. الملف المتخصص الذي تم العثور عليه هو `test/video_streaming/video_entitlement_test.dart`، ويغطي حالات entitlement للفيديو مثل subscription غير النشط، الاشتراك المنتهي/غير الصالح، غياب `endDate`، وحدود جودة الفيديو.

لم تُثبت في الملفات المقروءة اختبارات مباشرة للعمليات التالية: activateFreePlan، upgrade، downgrade، renew، freeze، resume، gift، تغيير Student Type، uniqueness للـ subject subscription، claims refresh بعد membership mutation، authorization لكل دور، Feature Matrix لغير الفيديو، أو preservation of student data بعد تغيير الخطة.

بيئة التدقيق الحالية هي Ubuntu 24.04.4 LTS على Linux x86_64، مع Flutter 3.47.0 وDart 3.13.0، ويوجد جهاز Linux desktop واحد فقط. لا يوجد Android emulator/device أو iOS simulator/device. لذلك لا يمكن إصدار حكم runtime على Android/iOS من هذه البيئة.[11]

## 11. الفجوات المصنفة

| المعرف | الفجوة | الخطورة | الدليل | الأثر |
|---|---|---|---|---|
| GAP-01 | لا توجد طبقة موحدة لكل Entitlements | High | providers وVideoEntitlement فقط | اختلاف enforcement بين features |
| GAP-02 | Feature Matrix منفذة بوضوح للفيديو/offline فقط | High | functions/video consumers | PDF/Exam/Quiz وغيرها قد لا تكون محمية بالـ plan |
| GAP-03 | Student Type conversion غير ظاهر كمسار backend مستقل | High | functions search | عدم اكتمال قاعدة Public↔Center |
| GAP-04 | fallback `'student'` في واجهة الخطط | High | `student_feature_hub_screen.dart` | لا يطابق القيم الرسمية وقد يعرض plans خاطئة/فارغة |
| GAP-05 | upgrade/downgrade directionality غير مثبتة | High | backend validator/mutation surface | يمكن أن تتحول العملية إلى مجرد تغيير خطة بلا اتجاه تجاري |
| GAP-06 | duplicate subscription يعالج بعد الإنشاء | High | `enforceOneSubscriptionPerSubject` | نافذة inconsistency ونتائج `limit(1)` غير حتمية |
| GAP-07 | claims freshness بعد mutations غير مثبتة | High | claims عند approval/login مقابل mutation functions | authorization snapshot قديم |
| GAP-08 | `endDate == null` يفسر محليًا كـ active | High | `StudentSubscription.termLifecycle` | اختلاف client/server في صلاحية الاشتراك |
| GAP-09 | UI الطالب لا يدير membership lifecycle | Medium | `MembershipPlansScreen` | لا يستطيع الطالب رؤية الحالة/الانتهاء/الخيارات كاملة |
| GAP-10 | Admin Feature Matrix أضيق من Feature 14 | Medium | `PlanQualityMatrixScreen` | الإدارة لا تهيئ كل capabilities المطلوبة |
| GAP-11 | analytics موجودة كevents لكن coverage غير مثبت | Medium | `writeAnalyticsEvent` calls | مؤشرات distribution/rates قد لا تكون قابلة للتقرير بدقة |
| GAP-12 | اختبارات membership المباشرة غير كافية | High | test inventory | regressions في lifecycle/security قد تمر دون كشف |
| GAP-13 | لا يوجد دليل على preview duration/lecture enforcement | High | video signed URL path | Public Free business rule قد لا يطبق كاملًا |

## 12. الملفات الحالية والملفات المتأثرة المحتملة

### ملفات تمت قراءتها أو تمثل التنفيذ الحالي

| الطبقة | الملفات |
|---|---|
| Domain | `lib/features/membership/domain/entities/membership_plan.dart`, `plan_feature.dart`, `student_subscription.dart`, `membership_entities.dart` |
| Repository | `lib/features/membership/domain/repositories/membership_repository.dart`, `data/repositories/membership_repository_impl.dart` |
| Data | `lib/features/membership/data/datasources/membership_remote_data_source.dart` |
| Providers | `lib/features/membership/presentation/providers/membership_providers.dart` |
| Student UI | `lib/features/student_platform/presentation/screens/student_feature_hub_screen.dart` |
| Video entitlement | `lib/features/video_streaming/data/services/video_source_resolver.dart`, `presentation/providers/video_streaming_providers.dart` |
| Backend | `functions/src/index.ts` |
| Security | `firestore.rules` |
| Tests | `test/video_streaming/video_entitlement_test.dart` |

### ملفات قد تتأثر في مرحلة تنفيذ لاحقة فقط

هذه ليست توصية تنفيذية ضمن هذا التدقيق، بل خريطة أثر محتملة إذا تمت الموافقة على مرحلة implementation: Membership entities/domain policy، repository/data source، membership providers، Student Feature Hub، Admin Feature Matrix، Cloud Functions، Firestore Rules، claims refresh integration، entitlement consumers للـ PDF/Quiz/Exam/Chat/Notes/Offline/Export، analytics aggregation، واختبارات lifecycle/security.

## 13. ما هو خارج النطاق أو مؤجل

لا يتضمن هذا التدقيق أي تعديل على Video Streaming، Offline DRM، Authentication، Device Binding، Database schema، أو Routing. كما لم تُخترع قواعد جديدة لتحديد أسعار الخطط أو اتجاهات الترقية أو سياسة Student Type conversion. أي فجوة تحتاج قرارًا تجاريًا غير محسوم يجب عرضها على صاحب القرار قبل التنفيذ.

## 14. الخلاصة والتوصية الإجرائية

الحالة الحالية ليست غيابًا كاملًا لـ Membership؛ بل توجد **نواة تشغيلية** جيدة تعتمد على Cloud Functions وFirestore وFeature Matrix جزئية، ويظهر تكامل أمني فعلي مع Video Entitlement وDevice Binding. لكن Feature 14 كما تصفها الوثيقة أوسع من التنفيذ الحالي، وأكبر الفجوات هي: غياب entitlement facade موحد، عدم إثبات enforcement لكل capabilities، عدم وجود Student Type conversion واضح، ضعف atomicity في uniqueness، عدم إثبات claims freshness، وعدم اكتمال واجهات الطالب والإدارة والاختبارات.

التوصية الصحيحة بعد هذا التقرير هي فتح مرحلة منفصلة بعنوان **Feature 14 Implementation Planning & Decision Review**، تبدأ بحسم القواعد غير المحسومة: directionality للترقية والتخفيض، سياسة `endDate == null`، آلية Student Type conversion، claims refresh بعد mutation، preview semantics، وtransaction/idempotency strategy. لا ينبغي بدء تعديل الكود قبل اعتماد هذه القرارات.

## المراجع

[1]: docs/notion/04_FEATURES.md#feature-14-membership-plans "04_FEATURES.md — Feature 14 Membership Plans"
[2]: lib/features/membership/domain/repositories/membership_repository.dart "MembershipRepository contract"
[3]: lib/features/membership/domain/entities/membership_plan.dart "MembershipPlan entity"
[4]: lib/features/membership/domain/entities/plan_feature.dart "PlanFeature entity"
[5]: lib/features/membership/domain/entities/student_subscription.dart "MembershipSubscription entity"
[6]: lib/features/membership/data/datasources/membership_remote_data_source.dart "MembershipRemoteDataSource"
[7]: lib/features/membership/data/repositories/membership_repository_impl.dart "MembershipRepositoryImpl"
[8]: lib/features/membership/presentation/providers/membership_providers.dart "Membership Riverpod providers"
[9]: functions/src/index.ts "Cloud Functions: approval, claims, lifecycle, duplicate-subscription handling"
[10]: lib/features/video_streaming/data/services/video_source_resolver.dart "VideoEntitlementService and VideoSourceResolver"
[11]: docs/notion/07_FLUTTER_ARCHITECTURE.md "Flutter architecture and platform context"
[12]: docs/notion/00_MASTER_ARCHITECTURE.md "Master architecture reference"
[13]: docs/notion/05_DATABASE.md "Database schema reference"
[14]: firestore.rules "Firestore security rules"
