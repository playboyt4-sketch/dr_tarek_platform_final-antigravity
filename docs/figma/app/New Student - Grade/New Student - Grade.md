# 📱 Screen 08: Student Grade Selection (New Student - Grade) — APPROVED

---

## 1. Overview & Purpose (نظرة عامة والهدف)
الشاشة الثامنة في رحلة تسجيل الطالب الجديد، تتيح للطالب تحديد فرقته الدراسية من بين الفرق الأربعة (الأولى، الثانية، الثالثة، الرابعة) عبر كروت كبسولية تفاعلية تعكس ألوان وهوية الفرق المعتمدة في نظام التصميم.

---

## 2. Frame Dimensions & Layout (أبعاد الإطار والتخطيط)
* Frame Name: New Student - Grade (أو grades selection).
* Width (العرض): 393px (مطابق لعرض شاشة الموبايل).
* Height (الارتفاع): 852px.
* Background Canvas: AppColors.white (#FFFFFF).

---

## 3. Header Section & Back Navigation (الهيدر وزر الرجوع)
* Header Artwork (student_grade_art):
  - الرسمة: طالب يحمل كتباً ويرتدي قبعة التخرج.
  - Dimensions: Width 369px x Height 324px.
  - Position: X: 12, Y: 50.
  - Corner Radius: 35px على جميع الزوايا.
* Floating Glass Back Button (❖ button/back):
  - Dimensions: 44 x 44 px circle (radius/full).
  - Position: X: 24, Y: 64 (عائم فوق الرسمة بالزاوية العلوية اليسرى).
  - Material: Liquid Glass (Fill: White 25%, Stroke: White 35%, Blur: 20px).
  - Icon: White Chevron Left (<, 20px).
  - Interaction: OnTap -> Navigator.pop(context) (Slide Right →, 300ms, EaseOut).

---

## 4. Title & Question (العنوان الرئيسي)
* Question Title: "Which year are you in?"
* Position: X: 0 (Centered), Y: 406, Width: 393px, Height: 69px.
* TextStyle: AppTypography.titleLarge (Google Sans Flex, 28px, Regular, LineHeight 36px).
* Color: AppColors.darkText (#111827).
* Alignment: Center.

---

## 5. Selectable Grade Capsules List (قائمة كروت الفرق التفاعلية)
* Container Frame: Auto Layout رأسي باسم grades.
* Position: متمركز تماماً عند X: 24.
* Width: 345px.
* Vertical Gap (المسافة بين الكروت): 12px.
* Capsule Dimensions: كل كارت أبعاده 345px x 60px بزوايا كاملة 9999px (radius/full).
* Elevation / Shadow: Drop shadow ناعم (Y: 4, Blur: 12, Color: rgba(0, 0, 0, 0.08)).

### تفاصيل الكروت الأربعة:
1. Grade one (الفرقة الأولى):
   - Background Fill: #F59E0B (أصفر كهرماني دافئ).
   - Label: "Grade one" (TextStyle: title/medium 20px, White #FFFFFF).
   - Number Badge: دائرة 36 x 36 px بخلفية زجاجية شفافة 25% ورقم "1".
2. Grade two (الفرقة الثانية):
   - Background Fill: #1D4ED8 (أزرق ملكي).
   - Label: "Grade two" (TextStyle: title/medium 20px, White #FFFFFF).
   - Number Badge: دائرة 36 x 36 px بخلفية زجاجية شفافة 25% ورقم "2".
3. Grade three (الفرقة الثالثة):
   - Background Fill: #15803D (أخضر غابي).
   - Label: "Grade three" (TextStyle: title/medium 20px, White #FFFFFF).
   - Number Badge: دائرة 36 x 36 px بخلفية زجاجية شفافة 25% ورقم "3".
4. Grade four (الفرقة الرابعة):
   - Background Fill: #DC2626 (أحمر ياقوتي).
   - Label: "Grade four" (TextStyle: title/medium 20px, White #FFFFFF).
   - Number Badge: دائرة 36 x 36 px بخلفية زجاجية شفافة 25% ورقم "4".

---

## 6. Primary CTA Button (زر المتابعة)
* Component: ❖ button/primary (Variant: Style = Solid).
* Label: "Next" (TextStyle: title/medium 20px, White #FFFFFF).
* Dimensions: Width 345px x Height 56px (radius/full 9999px).
* Position: X: 24, Y: 754 (متمركز في الأسفل بهامش 24px يميناً ويساراً).
* Interaction Logic: OnTap -> يحفظ الفرقة المختارة وينتقل إلى NewStudentPasswordScreen (Slide Left ←, 300ms, EaseOut).

---

## 7. Flutter Production Code (كود فلاتر الكامل للشاشة)

import 'package:flutter/material.dart';

enum AcademicGrade { grade1, grade2, grade3, grade4 }

class NewStudentGradeScreen extends StatefulWidget {
  const NewStudentGradeScreen({super.key});

  @override
  State<NewStudentGradeScreen> createState() => _NewStudentGradeScreenState();
}

class _NewStudentGradeScreenState extends State<NewStudentGradeScreen> {
  AcademicGrade _selectedGrade = AcademicGrade.grade1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Column(
          children: [
            // 1. الهيدر مع زر الرجوع العائم
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: Image.asset(
                      'assets/images/student_grade_art.png',
                      width: 369,
                      height: 324,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 24,
                  child: GlassBackButton(onPressed: () => Navigator.pop(context)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. العنوان الرئيسي
            const Text(
              'Which year are you in?',
              style: TextStyle(
                fontFamily: 'Google Sans Flex',
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // 3. قائمة كروت الفرق الكبسولية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  GradeCapsuleTile(
                    title: 'Grade one',
                    gradeNumber: '1',
                    backgroundColor: const Color(0xFFF59E0B),
                    isSelected: _selectedGrade == AcademicGrade.grade1,
                    onTap: () => setState(() => _selectedGrade = AcademicGrade.grade1),
                  ),
                  const SizedBox(height: 12),
                  GradeCapsuleTile(
                    title: 'Grade two',
                    gradeNumber: '2',
                    backgroundColor: const Color(0xFF1D4ED8),
                    isSelected: _selectedGrade == AcademicGrade.grade2,
                    onTap: () => setState(() => _selectedGrade = AcademicGrade.grade2),
                  ),
                  const SizedBox(height: 12),
                  GradeCapsuleTile(
                    title: 'Grade three',
                    gradeNumber: '3',
                    backgroundColor: const Color(0xFF15803D),
                    isSelected: _selectedGrade == AcademicGrade.grade3,
                    onTap: () => setState(() => _selectedGrade = AcademicGrade.grade3),
                  ),
                  const SizedBox(height: 12),
                  GradeCapsuleTile(
                    title: 'Grade four',
                    gradeNumber: '4',
                    backgroundColor: const Color(0xFFDC2626),
                    isSelected: _selectedGrade == AcademicGrade.grade4,
                    onTap: () => setState(() => _selectedGrade = AcademicGrade.grade4),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // 4. زر التالي
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: SizedBox(
                width: 345,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const NewStudentPasswordScreen(),
                        transitionsBuilder: (_, animation, __, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(1.0, 0.0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                    );
                  },
                  child: const Text(
                    'Next',
                    style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GradeCapsuleTile extends StatelessWidget {
  final String title;
  final String gradeNumber;
  final Color backgroundColor;
  final bool isSelected;
  final VoidCallback onTap;

  const GradeCapsuleTile({
    super.key,
    required this.title,
    required this.gradeNumber,
    required this.backgroundColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 345,
      height: 60,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(9999),
        border: isSelected ? Border.all(color: Colors.white, width: 3.0) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    gradeNumber,
                    style: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const GlassBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 44,
        height: 44,
        color: Colors.white.withOpacity(0.25),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
    );
  }
}