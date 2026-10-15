# 🚀 Engineering Implementation Specification: Platform Feature Matrix & Plan Management (المواصفات الهندسية الشاملة لشاشة التحكم في مميزات وباقات المنصة)

**المشروع المستهدف:** `dashboard/` (تطبيق لوحة تحكم المنصة المبني بـ Flutter Web / Desktop)  
**المرجع التصميمي:** شاشة `# Subscription` في Figma، مكون زر المنيو التفاعلي `the menu`، والصورة البانورامية الشاملة `Subscription.jpg`.  
**مقاس الشاشة المعتمد:** `1280px × Auto` (Safe Laptop Viewport) بنظام شبكة `1120px` وهوامش أمان جانبية `80px`.

---

## 1. 📋 Architectural Overview & Core Layout (نظرة عامة والهيكل العام)

تعتمد الشاشة على نمط **الواجهة الموحدة ذات التمرير الرأسي المستمر (Continuous Vertical Flow) مع هيدر علوي ثلاثي المستويات مثبت بالكامل (Fixed / Sticky Header)** مدعوماً بتقنية التزامن المزدوج للتمرير (**Scrollspy & Anchor Navigation**).

```text
===================================================================================================
[ FIXED STICKY HEADER — يظل ثابتاً في سقف الشاشة طوال التمرير ]
  Level 0:  [the menu ICON (80x80)]                 Tarek el araby Platform
  Level 1:  [Plans Tabs]:        ( Public FREE )  ( Center FREE )  ( Center PRO )  ( Center MAX )
  Level 2:  [Category Tabs]:     [Video & Media] [Pdf & docs] [Learning] [Productivity] [Device] [Profile]
===================================================================================================
[ SCROLLABLE BODY AREA — منطقة المحتوى القابلة للتمرير مع Scrollspy ]
  
  +--- [ Container 1: Video & Media ] -------------------------------------------------------------+
  |    Video access ----------------------------------------------------------------- [Toggle ON]  |
  |    Video Rolling Window / hours --------------------------------------------------- [Badge 24] |
  |    Video Resolution (144p -> 4Kp) ----------------------------------------------- [Toggles...] |
  |    Video Playback Speed (X0.50 -> X4.00) ---------------------------------------- [Toggles...] |
  |    Video Picture-in-Picture / Cast / Resume / Skip / Heatmap -------------------- [Toggles...] |
  |    Video Offline Mode (Offline + Student Quality Choice + Limit 24) ------------- [Box Stack]  |
  |    Video Security (Watermark + Screen Record Detect + Screenshot Prevent) ------- [Toggles ON] |
  +------------------------------------------------------------------------------------------------+
                                              [Gap: 32px]
  +--- [ Container 2: Pdf & documents ] -----------------------------------------------------------+
  |    PDF access ------------------------------------------------------------------- [Toggle ON]  |
  |    PDF Offline Mode + Limit per subject ------------------------------------ [Toggle + Badge] |
  |    PDF Security (Watermark + Screen Record Detect + Screenshot Prevent) --------- [Toggles ON] |
  |    PDF Search within / Table of contents / Zoom control / Bookmarks ------------- [Toggles ON] |
  +------------------------------------------------------------------------------------------------+
                                              [Gap: 32px]
  +--- [ Container 3: Learning & Assessment ] -----------------------------------------------------+
  |    Exams access / Timeline Video Quizzes / Review Exam Solutions ---------------- [Toggles...] |
  |    Exam Retake Attempts Limit ------------------------------------------------------ [Badge 2] |
  |    Anti-Cheat Exam Protection / Enforced Countdown Timer / Shuffle Choices ------ [Toggles ON] |
  |    Self-Practice Question Bank / Performance Analytics / Prerequisite Gate ------ [Toggles...] |
  +------------------------------------------------------------------------------------------------+
                                              [Gap: 32px]
  +--- [ Container 4: Productivity ] --------------------------------------------------------------+
  |    Create Personal Note / Create Bookmarks / Course Progress Tracking ----------- [Toggles...] |
  |    Search in Personal Notes / Export Personal Notes ----------------------------- [Toggles...] |
  |    Study Reminders & Schedule / Lecture Revision Tagging ------------------------ [Toggles...] |
  +------------------------------------------------------------------------------------------------+
                                              [Gap: 32px]
  +--- [ Container 5: Device & Security ] ---------------------------------------------------------+
  |    Max active devices -------------------------------------------------------------- [Badge 1] |
  |    View security score / Block Root & Emulators --------------------------------- [Toggles ON] |
  +------------------------------------------------------------------------------------------------+
                                              [Gap: 32px]
  +--- [ Container 6: Profile & Account ] ---------------------------------------------------------+
  |    Edit full name / Edit profile photo / View membership details ---------------- [Toggles ON] |
  +------------------------------------------------------------------------------------------------+