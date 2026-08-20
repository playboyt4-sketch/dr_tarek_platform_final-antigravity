# تقرير تنفيذ مواصفة الأولويات 0–8

## النتيجة العامة

تم تنفيذ المواصفة داخل المعمارية الحالية لمشروع `dr_tarek_platform` دون إنشاء Firebase أو repositories أو models موازية. تم الحفاظ على مسار الفيديو الحالي، Riverpod، MembershipRepository، Firestore، Cloud Functions، وشاشات الإدارة والداشبورد القائمة، مع إضافة التكاملات المطلوبة في مواضعها الحالية.

## حالة البنود

| الأولوية | التنفيذ | الحالة |
|---:|---|---|
| 0 | استقرار تشغيل الفيديو عبر silent refresh للرابط الموقّع، قياس buffering، وdowngrade تلقائي عند التقطيع المستمر | منفذ |
| 1 | إصلاح Continue Watching عبر دمج السجلات المحلية والسحابية بعد إزالة قيد `completed == false` من الاستعلام، وتصحيح تظليل الحلقة بربط `episodeId` و`seasonId` | منفذ ومختبر |
| 2 | جودة ديناميكية لكل خطة عبر `plan_features`، دعم `video.quality.<value>`، توافق `video.quality.max` القديم، شاشة `PlanQualityMatrixScreen` بمفاتيح `CupertinoSwitch`، وحفظ التغييرات عبر callable Function محمية | منفذ |
| 3 | adaptive quality، silent refresh، network recovery، downgrade، والحفاظ على الاختيار اليدوي للجودة أثناء الجلسة | منفذ |
| 4 | فصل حالة الاشتراك عن دورة الفترة الأكاديمية، والتحقق من `status == active` ووجود `endDate` صريح وكون الاشتراك داخل الفترة | منفذ ومختبر |
| 5 | بناء `UserAvatar` في `lib/core/widgets/user_avatar.dart` من المرجع البصري `الافتار.html`، مع ring حسب الدور، badge حسب الخطة، placeholder زجاجي، وصورة cover، ثم ربطه فعليًا داخل `_GreetingCard` بدل `CircleAvatar` | منفذ |
| 6 | device binding بمعرّف ثابت مخزن في `FlutterSecureStorage`، rate limiting ذري في Cloud Functions، التحقق من نهاية الاشتراك، وwatermark مرئي منخفض التباين داخل المشغل | منفذ |
| 7 | haptic feedback عند seek وتبديل الحلقة وتخطي المقدمة، prefetch قصير للرابط الموقّع للحلقة التالية، و`Skip Intro` مشروط فقط بوجود metadata | منفذ |
| 8 | تشغيل الاختبارات والتحليل وبناء Cloud Functions وتوثيق القيود والقرارات | ناجح |

## UserAvatar

المكوّن الجديد هو Flutter widget حقيقي وقابل لإعادة الاستخدام، وليس تحويلًا لملف HTML داخل WebView. تم وضعه في `lib/core/widgets/user_avatar.dart`، ويقبل role وstudent type وplan وprofile photo، ويستخدم design tokens داخل `AppColors`. تم استبدال `CircleAvatar` في `_GreetingCard` باستدعاء `UserAvatar.fromAuthValues` مع تمرير بيانات `AuthUser` الحالية.

## Skip Intro وBunny quality support

لا يظهر زر `Skip Intro` إلا إذا احتوت بيانات الحلقة على `skip_intro_start` و`skip_intro_end` أو `intro_start` و`intro_end`. عند غياب metadata لا يتم اختراع نافذة زمنية ولا يظهر الزر.

يدعم التطبيق قيم الجودة التي يعرّفها backend و`plan_features` من 144p إلى 4K. لم يتم افتراض أن كل فيديو Bunny مُشفّر فعليًا بكل هذه الجودات؛ الجودات المتاحة فعليًا تظل مرتبطة بالـ encodings الموجودة في Bunny وبالـ plan features المفعلة. عند غياب إعداد جودة صالح يتم رفض entitlement بدل فتح جودة غير مؤكدة.

## التحقق المنفذ

تم تشغيل الأوامر التالية بنجاح:

```text
flutter test
11 tests passed

flutter analyze
No issues found!

functions: npm run build
TypeScript compilation succeeded
```

يشمل الاختبار مسار الاستعادة المحلي لـ Episode 1 عند الموضع `03:24`، Continue Watching، حدود seek، completion، التنقل بين الحلقات، الجودة، entitlement، رفض الاشتراك غير النشط، ورفض الاشتراك الذي يفتقد `endDate`.

لم يتم إجراء smoke test حي على جهاز Android أو iOS متصل بخدمات Firebase وBunny الحقيقية داخل البيئة الحالية، كما لم يتم إنشاء APK لأن Android SDK غير متاح في sandbox. لذلك لا يدّعي هذا التقرير التحقق من سلوك الجهاز الفعلي أو توفر encoding محدد في حساب Bunny الإنتاجي.

## الملفات الأساسية

- `lib/core/widgets/user_avatar.dart`
- `lib/features/student_dashboard/presentation/screens/student_dashboard_screen.dart`
- `lib/features/video_streaming/presentation/controllers/video_playback_controller.dart`
- `lib/features/video_streaming/presentation/screens/video_streaming_screen.dart`
- `lib/features/video_streaming/data/services/video_source_resolver.dart`
- `lib/features/video_streaming/domain/entities/playback_entities.dart`
- `lib/features/subject_navigation/domain/entities/subject_learning_entities.dart`
- `lib/features/subject_navigation/data/datasources/subject_navigation_remote_data_source.dart`
- `lib/features/admin/presentation/screens/plan_quality_matrix_screen.dart`
- `functions/src/index.ts`
- `test/video_streaming/video_entitlement_test.dart`
- `priority_execution_spec.md`

تم إعداد هذا التقرير بواسطة **Manus AI**.
