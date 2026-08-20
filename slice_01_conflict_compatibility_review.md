# تقرير Conflict & Compatibility Review — Slice 01

**المشروع:** Dr. Tarek Platform Flutter  
**النطاق:** Application Session & Routing Foundation  
**الحالة:** تمت المراجعة قبل أي تعديل كود خاص بـ Slice 01  
**المرجع الأعلى:** `docs/notion/00_MASTER_ARCHITECTURE.md`

## 1. خلاصة القرار

بعد مقارنة مواصفة `pasted_content_4.txt` مع المرجع المعماري الأعلى، والقرارات النهائية، ووثائق Firebase وFlutter، وبنية Authentication وDevice Binding وCustom Claims الحالية، لا يوجد **تعارض حقيقي** يمنع تنفيذ Slice 01.

المشكلات المكتشفة في `app_router.dart` و`SplashScreen` و`AuthGate` ليست قرارات معمارية متعارضة، بل فجوات تنفيذية: ملف التوجيه المركزي فارغ، شاشة البداية تنتقل بعد مهلة ثابتة إلى اختيار نوع المستخدم، و`AuthGate` يراقب `authProvider` وحده ولا يحوّل حالات claims أو device authorization أو account status إلى حالات جلسة تطبيقية.

بناءً على ذلك، القرار هو **المتابعة إلى التنفيذ** مع الحفاظ على كل القرارات المعتمدة وعدم إعادة بناء Authentication أو Device Binding أو قاعدة البيانات أو Membership أو Video Streaming.

## 2. المرجعيات والقواعد المحمية

| المرجع | القاعدة التي تم الحفاظ عليها | أثرها على Slice 01 |
|---|---|---|
| `00_MASTER_ARCHITECTURE.md` | Clean Architecture، Feature-First، وRepository Pattern هي الأساس الأعلى | ستضاف طبقة session في domain/presentation داخل feature authentication، دون إنشاء Architecture موازية |
| `FINAL_DECISIONS.md` | تسجيل الدخول يتم عبر Custom Token صادر من `verifyPhonePassword` ثم `signInWithCustomToken` | لا تغيير في datasource أو repository أو عقد تسجيل الدخول |
| `FINAL_DECISIONS.md` | Device Binding قائم على `onLoginAttempt` | سيُستدعى `DeviceBindingController` الحالي أثناء bootstrap، دون نسخ منطق التحقق |
| `06_FIREBASE_ARCHITECTURE.md` | Claims تتضمن role وstudent_type وplan_id وmax_devices وsubscription_status وapproved وforce_password_change | سيُعاد استخدام `customClaimsProvider` الحالي لاستخراج القرار session-wise |
| `07_FLUTTER_ARCHITECTURE.md` | Riverpod مع فصل domain/data/presentation وتوجيه مركزي | سيُنشأ `SessionState` و`sessionProvider` ضمن البنية الحالية، ويُربط به router/gate |
| `05_DATABASE.md` و`04_FEATURES.md` | عدم تغيير schema أو Membership rules أو قواعد الوصول المعتمدة | لن تُضاف حقول أو قواعد أعمال جديدة في Slice 01 |

## 3. نتائج المقارنة التفصيلية

### 3.1 Authentication وCustom Tokens

التنفيذ الحالي يحافظ على المسار المعتمد: `authProvider` يستخدم `AuthRepository`، و`AuthRepositoryImpl` يعتمد على `CustomTokenRemoteDataSource`، الذي يستدعي `verifyPhonePassword` ثم يوقع الدخول عبر Firebase Custom Token. مواصفة Slice 01 لا تطلب استبدال هذا المسار، بل تطلب وضعه داخل Application Session.

**النتيجة:** لا تعارض. التعديل المسموح هو إضافة bootstrap يستهلك ناتج Authentication الحالي، مع إبقاء `auth_provider.dart` وdatasource وrepository كما هي ما لم يكشف الاختبار حاجة تكاملية محدودة.

### 3.2 Claims وAccount/Role State

`customClaimsProvider` موجود بالفعل ويجدد token عبر `getIdTokenResult(true)` عند تغير حالة Firebase Auth، ثم يعرض claims الحالية. الحقول المطلوبة في Slice 01 متوافقة مع بنية claims الموجودة. لذلك لا حاجة إلى provider موازٍ أو schema جديد.

**النتيجة:** لا تعارض. سيُستهلك provider الحالي داخل session bootstrap، مع تحويل القيم الموجودة إلى حالات session المطلوبة فقط.

### 3.3 Device Binding

`DeviceBindingController` موجود ويستدعي repository الحالي للحصول على معلومات الجهاز ثم ينفذ `validateDevice`. شاشة Login الحالية تستدعيه يدويًا بعد نجاح Authentication. هذا يثبت أن منطق device authorization موجود، لكن نقطة استدعائه موزعة داخل الشاشة.

مواصفة Slice 01 تطلب توحيد القرار داخل Application Session، ولا تطلب تغيير عقد Cloud Function أو repository. لذلك سينتقل قرار التحقق إلى bootstrap المركزي، مع إزالة الازدواجية في واجهة Login فقط إذا لزم ذلك لتجنب تنفيذ التحقق مرتين.

**النتيجة:** لا تعارض. الدمج سيكون إعادة توصيل للمنطق القائم، لا إعادة بناء له.

### 3.4 Session States

المواصفة تطلب الحالات: `initializing`, `unauthenticated`, `authenticated`, `pendingApproval`, `rejected`, `disabled`, `unauthorizedDevice`, و`error`. هذه الحالات تمثل طبقة قرار تطبيقية فوق مصادر قائمة بالفعل: Firebase Auth، AuthUser، claims، وDevice Binding.

**النتيجة:** لا تعارض مع النموذج الحالي، بشرط ألا تُعامل الحالات الجديدة كقواعد Membership جديدة أو كبديل لـ `AuthUser`. ستكون `SessionState` مصدر الحقيقة الوحيد للتوجيه، بينما تظل `authProvider` مصدر بيانات المستخدم الحالي.

### 3.5 Routing وSplash وAuthGate

`app_router.dart` فارغ حاليًا، و`MaterialApp` يستخدم `SplashScreen` بوصفها `home`. `SplashScreen` تنتظر مهلة ثابتة ثم تنتقل دائمًا إلى `UserTypeSelectionScreen`. أما `AuthGate` فيراقب `authProvider` فقط، ويوجه المستخدم حسب وجود `AuthUser` والدور.

هذه السلوكيات لا تخالف قرارًا معماريًا Approved؛ لكنها لا تحقق متطلبات إعادة فتح التطبيق بجلسة صالحة، ولا تمنع الحالات pending/rejected/disabled/unauthorized-device من الوصول إلى destinations محمية.

**النتيجة:** فجوة تنفيذية، وليست Conflict. سيُبنى router مركزي يستهلك `SessionState`، وستتحول Splash إلى واجهة انتظار للتهيئة دون توجيه مستقل ينافس router.

## 4. Conflict Report — النتيجة الرسمية

| البند المطلوب عند وجود تعارض | النتيجة |
|---|---|
| الوثيقة الأولى | لا ينطبق؛ لم يوجد تعارض حقيقي |
| الوثيقة الثانية | لا ينطبق |
| القاعدة الأولى | لا ينطبق |
| القاعدة الثانية | لا ينطبق |
| سبب التعارض | لا يوجد تعارض بين المواصفة والقرارات Approved |
| الحل المقترح | دمج تنفيذي داخل البنية الحالية مع إعادة استخدام Authentication وClaims وDevice Binding |
| التأثير على الكود | إضافة session entity/provider، تفعيل AppRouter، تعديل App entry وSplash وAuthGate، وربط Login بالمسار المركزي عند الحاجة |

## 5. الملفات التي ستتغير في Slice 01

| الملف | الإجراء المتوقع | سبب الإجراء |
|---|---|---|
| `lib/features/authentication/domain/entities/session_state.dart` | إنشاء | تعريف الحالات التطبيقية المطلوبة بصورة typed وآمنة |
| `lib/features/authentication/presentation/providers/session_provider.dart` | إنشاء | تنفيذ bootstrap مركزي يربط Auth وclaims وaccount state وdevice authorization |
| `lib/core/routing/app_router.dart` | تنفيذ | جعل التوجيه مستهلكًا لـ `SessionState` فقط، دون Firebase/Firestore business logic |
| `lib/app/app.dart` | تعديل محدود | ربط `MaterialApp` بواجهة التطبيق/router المركزي بدل ترك Splash نقطة توجيه مستقلة |
| `lib/features/authentication/presentation/screens/splash_screen.dart` | تعديل محدود | عرض مرحلة التهيئة والانتظار، مع منع التوجيه الثابت إلى User Type |
| `lib/features/authentication/presentation/screens/auth_gate.dart` | تعديل | عرض destination حسب حالات session بدل `authProvider` وحده |
| `lib/features/authentication/presentation/screens/login_screen.dart` | تعديل تكاملي محتمل | منع التحقق المكرر من Device Binding وربط نجاح الدخول بالbootstrap المركزي |

## 6. الملفات والأنظمة المحمية من التغيير

لن تتغير قرارات أو عقود `AuthRepository` و`CustomTokenRemoteDataSource` وCloud Function `verifyPhonePassword`، ولن يعاد بناء `DeviceBindingController` أو `DeviceBindingRepository` أو Cloud Function `onLoginAttempt`. كما لن تتغير بنية Firestore أو Membership rules أو Video Streaming أو Offline DRM أو تصميم Dashboard.

سيُعاد استخدام `customClaimsProvider` الحالي، ولن يُنشأ provider آخر ينافسه لاستخراج claims. كذلك لن تُضاف business rules غير موثقة؛ وستقتصر عملية التحويل على الحالات التي طلبتها مواصفة Slice 01 والمعلومات الموجودة في `AuthUser` وclaims ونتيجة device authorization.

## 7. Acceptance Criteria وخطة التحقق

| الحالة | السلوك المتوقع بعد التنفيذ | طريقة التحقق |
|---|---|---|
| إعادة فتح التطبيق مع جلسة صالحة | الذهاب مباشرة إلى Student destination أو destination الدور الصحيح، دون User Type | اختبار provider/router واختبار runtime 가능한 في بيئة Firebase الحالية |
| Pending approval | منع الوصول إلى الوجهة المحمية وعرض حالة انتظار | unit/widget test للحالة |
| Rejected | منع الوصول وعرض rejection state | unit/widget test للحالة |
| Disabled | منع الوصول وعرض disabled state | unit/widget test للحالة |
| Unauthorized device | رفض الجلسة وعدم فتح destination | اختبار mock لنتيجة Device Binding |
| Router purity | عدم احتواء router على Firebase أو Firestore أو قواعد أعمال | فحص imports والكود، ثم `flutter analyze` |
| Single source of truth | اعتماد `SessionState` في التوجيه وعدم وجود routing متنافس داخل Splash/AuthGate/Login | فحص الاستخدامات واختبارات التوجيه |

## 8. قرار الانتقال

لا توجد نقطة تستوجب إيقاف التنفيذ أو طلب تعديل قرار Approved. ستبدأ مرحلة التنفيذ ضمن هذا النطاق فقط، مع الالتزام بأن أي تعارض جديد يظهر أثناء التنفيذ سيُوثق ويتوقف عنده العمل قبل تغيير القرار المعماري.

## المراجع

[1]: `docs/notion/00_MASTER_ARCHITECTURE.md` — المرجع المعماري الأعلى.  
[2]: `docs/notion/FINAL_DECISIONS.md` — القرارات النهائية المعتمدة.  
[3]: `docs/notion/06_FIREBASE_ARCHITECTURE .md` — بنية Firebase وCustom Claims.  
[4]: `docs/notion/07_FLUTTER_ARCHITECTURE.md` — بنية Flutter وRiverpod والتوجيه.  
[5]: `docs/notion/05_DATABASE.md` — قواعد قاعدة البيانات.  
[6]: `docs/notion/04_FEATURES.md` — نطاقات وقيود الميزات.  
[7]: `pasted_content_4.txt` — مواصفة Slice 01 محل المراجعة.

## 9. التنفيذ المنجز

تم تنفيذ Slice 01 ضمن الحدود المعتمدة. أضيف `SessionState` كـ sealed hierarchy، وأضيف `sessionProvider` بوصفه مصدر الحقيقة المركزي للجلسة. يبدأ bootstrap من `authProvider` الحالي، ثم يستهلك `customClaimsProvider` الحالي، ثم يمرر الحساب إلى `DeviceBindingController` الحالي، وبعد ذلك يصدر الحالة النهائية التي يستهلكها `AppRouter` و`AuthGate`.

تم تفعيل `AppRouter` داخل `MaterialApp`، وأصبح `SplashScreen` واجهة انتظار بصرية فقط بلا توجيه ذاتي. كما تم توسيع `AuthGate` للحالات unauthenticated وauthenticated وpending approval وrejected وdisabled وunauthorized device وerror. وتم تحديث LoginScreen لإزالة استدعاء Device Binding اليدوي المكرر والانتظار على session bootstrap المركزي بعد نجاح Custom Token login.

لم تُعدّل `auth_provider.dart` أو `customClaimsProvider` أو `DeviceBindingController` أو Cloud Functions أو Firestore schema أو Membership أو Video Streaming.

## 10. نتائج التحقق الفعلي

| التحقق | النتيجة | الملاحظة |
|---|---|---|
| Dart formatting | ناجح | تمت تهيئة كل الملفات الجديدة والمعدلة |
| `flutter analyze` | ناجح | `No issues found!` |
| `flutter test` قبل اختبارات Route Guard | ناجح | 15 اختبارًا مرّت |
| `flutter test` بعد اختبارات Route Guard | ناجح | 19 اختبارًا مرّت |
| Session state unit tests | ناجح | pending/rejected/disabled/approved مغطاة |
| AuthGate widget tests | ناجح | unauthenticated/pending/unauthorized device مغطاة |
| AppRouter provider override test | ناجح | يثبت أن AppRouter يستهلك sessionProvider المركزي |
| Router purity static check | ناجح | لا توجد Firebase/Firestore/Cloud Functions أو business logic داخل app_router.dart |
| Linux Debug build | ناجح | تم إنتاج `build/linux/x64/debug/bundle/flutter_analyzer_test` |
| Linux runtime launch | بدأ runtime ثم توقف بسبب إعداد منصة قائم | `firebase_options.dart` لا يعرّف FirebaseOptions لـ Linux؛ الخطأ حدث قبل منطق Slice 01 |

أثناء محاولة runtime الفعلية، بدأ Flutter engine وبدأ Dart VM service بنجاح، ثم توقف التطبيق عند `DefaultFirebaseOptions.currentPlatform` لأن فرع Linux في `lib/firebase_options.dart` يرمي `UnsupportedError`. لم يتم تعديل هذا الإعداد خارج نطاق Slice 01، لأن إضافة Firebase credentials لمنصة Linux قرار إعداد/بيئة مستقل وليس جزءًا من Application Session أو Routing Foundation.

## 11. حدود التحقق المتبقية

تم التحقق من session derivation وroute guard داخل اختبارات Flutter، كما تم بناء التطبيق كاملًا على Linux. أما اختبار login الحقيقي مع Firebase وDevice Binding فيتطلب منصة تملك FirebaseOptions صالحة وبيئة Firebase قابلة للاتصال؛ لذلك لم يُسجّل على أنه runtime pass في بيئة Linux الحالية. هذا القيد موثق بدل الادعاء بأن Firebase login flow اختُبر end-to-end.

## 12. خلاصة التسليم

Slice 01 منفذ ضمن القرارات المعتمدة، والتحليل والاختبارات وبناء التطبيق ناجحة. لا توجد تعارضات معمارية تستوجب عرضًا إضافيًا أو تغييرًا في Approved decisions. القيد الوحيد المفتوح للتشغيل الفعلي على Linux هو إعداد Firebase platform configuration الموجود مسبقًا في `firebase_options.dart`.
