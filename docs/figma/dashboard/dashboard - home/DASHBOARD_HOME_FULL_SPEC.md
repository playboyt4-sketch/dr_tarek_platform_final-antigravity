# 🚀 Engineering Implementation Specification: Dashboard Home, Full Menu & Animated Menu Button

**المشروع المستهدف:** `D:\antigravity\dr_tarek_platform_final\dashboard`  
**المرجع التصميمي:** ملف Figma المعتمد لشاشات `# dashboard - home` و `# dashboard - full menu` ومكون `the menu`.  
**مقاس الشاشة المعتمد:** `1280px × 800px` (Safe Laptop Viewport) بنظام شبكة `1120px` وهوامش جانبية `80px`.

---

## 1. 📁 خريطة الملفات والتعديلات المطلوبة (File Structure & Changes)

```text
dashboard/
├── lib/
│   ├── app/
│   │   └── shell/
│   │       ├── dashboard_shell.dart              # تعديل: إزالة الـ Sidebar الثابت ودمج الهيدر وقائمة الـ Overlay
│   │       └── dashboard_full_menu.dart           # إنشاء جديد: واجهة القائمة المنبثقة الكاملة (Full Menu Overlay)
│   ├── core/
│   │   └── widgets/
│   │       └── animated_menu_button.dart         # إنشاء جديد: مكون زر المنيو التفاعلي المتحرك (the menu)
│   └── features/
│       └── home/
│           └── presentation/
│               ├── screens/
│               │   └── dashboard_home_screen.dart # إعادة بناء شاملة بالمللي مطابقة للفيجما
│               └── widgets/
│                   ├── home_top_bar.dart          # الهيدر العلوي المتناسق
│                   ├── grade_pie_chart_card.dart  # كارت المخطط الدائري العام (Frame 42)
│                   ├── grade_breakdown_card.dart  # كروت الفرق الأربعة (2x2 Grid)
│                   ├── quick_action_card.dart     # كروت الإجراءات السريعة (Upload & Announcement)
│                   └── student_activity_chart.dart# كارت الشارت الأسبوعي المنحني (Student Activity)