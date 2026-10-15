# 📐 Interactive Component Specification: The Menu Icon (`the menu`)

---

## 1. 📋 Component Overview (نظرة عامة على المكون)
مكون تفاعلي ذو حالتين (Interactive Component Set) يمثل زر فتح وإغلاق القائمة في لوحة التحكم (Tarek el araby Platform - Dashboard).
يتحول المكون بحركة فيزيائية ناعمة وانسيابية (Morphing Animation) من خطين أفقيين متوازيين إلى علامة X عند النقر، والعكس.

---

## 2. 📐 Master Component Setup (إعدادات المكون الرئيسي)
* اسم المكون في Figma: `the menu`
* عدد الحالات (Variants): حالتان (2 Variants):
  1. `list icone` (الحالة الافتراضية - القائمة مغلقة)
  2. `x` (الحالة النشطة - القائمة مفتوحة)
* أبعاد الحاوية لكل حالة: 80px × 80px
* لون الخطوط الأساسي: #000000 (أسود نقي 100%)
* نصف قطر الحواف (Corner Radius): 9999px (أطراف دائرية بالكامل لجميع الخطوط)
* سمك الخط (Stroke Height): 1px
* طول الخط (Stroke Width): 80px

---

## 3. 🧩 Variants Breakdown (المواصفات الهندسية لكل حالة)

### الحالة الأولى: القائمة مغلقة (`list icone` - Default State)
* اسم الـ Variant: `list icone`
* الأبعاد: W: 80px, H: 80px
* نوع التوزيع (Auto Layout):
  * الاتجاه (Flow): رأسي (Vertical)
  * المحاذاة (Alignment): وسط بالكامل (Center Alignment)
  * المسافة البينية بين الخطين (Gap): 10px
* الخط العلوي (`Line 1`):
  * الأبعاد: W: 80px (Fill container) × H: 1px
  * الموقع الرأسي: Y: 34px
  * زاوية الدوران: 0°
* الخط السفلي (`Line 2`):
  * الأبعاد: W: 80px (Fill container) × H: 1px
  * الموقع الرأسي: Y: 45px
  * زاوية الدوران: 0°
* التوسيط الرأسي:
  * المسافة من سقف الفريم إلى Line 1: 34px
  * المسافة من Line 2 إلى أرضية الفريم: 34px
  * (النتيجة: توسيط هندسي كامل في منتصف الفريم)

---

### الحالة الثانية: القائمة مفتوحة (`x` - Active / Close State)
* اسم الـ Variant: `x`
* الأبعاد: W: 80px, H: 80px
* المحاذاة: توسيط في السنتر (Center Alignment)
* الخط المائل الأول (`Line 1`):
  * الأبعاد: W: 80px × H: 1px
  * زاوية الدوران (Rotation): -45°
  * الموقع: X: 11px, Y: 11px
* الخط المائل الثاني (`Line 2`):
  * الأبعاد: W: 80px × H: 1px
  * زاوية الدوران (Rotation): +45°
  * الموقع: X: 11px, Y: 11px
* نقطة المركز: يتقاطع الخطان في نقطة المركز الدقيقة (40px, 40px) داخل مربع الـ 80 × 80.

---

## 4. 🎬 Interaction & Animation Specs (خصائص الحركة والتفاعل)

| الخاصية | من القائمة إلى X (`list icone` ➔ `x`) | من X إلى القائمة (`x` ➔ `list icone`) |
| :--- | :--- | :--- |
| **المشغّل (Trigger)** | `On click` (عند النقر) | `On click` (عند النقر) |
| **الإجراء (Action)** | `Change to` ➔ `x` | `Change to` ➔ `list icone` |
| **نوع التحريك (Animation)** | **`Smart animate`** | **`Smart animate`** |
| **منحنى التسارع (Easing)** | **`Ease out`** (خروج ناعم) | **`Ease out`** |
| **زمن الانتقال (Duration)** | **`300ms`** | **`300ms`** |

---

## 5. 💻 Flutter Implementation Notes (ملاحظات التنفيذ البرمجي)

```dart
// Custom Animated Menu Toggle Widget
class AnimatedMenuButton extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onTap;

  const AnimatedMenuButton({
    super.key,
    required this.isOpen,
    required this.onTap,
  });

  @override
  State<AnimatedMenuButton> createState() => _AnimatedMenuButtonState();
}

class _AnimatedMenuButtonState extends State<AnimatedMenuButton> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Line 1
            AnimatedRotation(
              turns: widget.isOpen ? -45 / 360 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, widget.isOpen ? 0 : -5.5, 0),
                width: 80,
                height: 1,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
            // Line 2
            AnimatedRotation(
              turns: widget.isOpen ? 45 / 360 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, widget.isOpen ? 0 : 5.5, 0),
                width: 80,
                height: 1,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}