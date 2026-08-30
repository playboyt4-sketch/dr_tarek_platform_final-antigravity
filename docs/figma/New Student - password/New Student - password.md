# 📱 Screen 09: Student Password & Security (New Student - password) — APPROVED

---

## 1. Overview & Purpose (نظرة عامة والهدف)
الشاشة التاسعة في رحلة تسجيل الطالب الجديد، تتيح للطالب إنشاء وتأكيد كلمة مرور آمنة لحسابه، مع إرشادات متطلبات كلمة المرور بنمط الخط الرفيع (Thin) وخاصية إظهار/إخفاء الرمز.

---

## 2. Frame Dimensions & Canvas (الأبعاد والإطار)
* Frame Name: New Student - password.
* Width (العرض): 393px (مطابق لعرض شاشة الموبايل).
* Height (الارتفاع): 852px.
* Background Canvas: AppColors.white (#FFFFFF).

---

## 3. Header Section & Back Navigation (الهيدر وزر الرجوع)
* Header Artwork (student_security_shield_art):
  - الرسمة: طالب يحمل درع الحماية الأزرق ورمز قفل الأمان.
  - Dimensions: Width 369px x Height 325px.
  - Position: X: 12, Y: 50.
  - Corner Radius: 35px على جميع الزوايا.
* Floating Glass Back Button (❖ button/back):
  - Dimensions: 44 x 44 px circle (radius/full).
  - Position: X: 24, Y: 64.
  - Material: Liquid Glass (Fill: White 25%, Stroke: White 35%, Blur: 20px).
  - Icon: White Chevron Left (<, 20px).
  - Interaction: OnTap -> Navigator.pop(context) (Slide Right →, 300ms, EaseOut).

---

## 4. Title & Security Form (العنوان وحقول كلمة المرور)
* Question Title: "Secure your account"
  - Position: X: 10 (Centered), Y: 407, Width: 374px, Height: 68px.
  - TextStyle: AppTypography.titleLarge (Google Sans Flex, 28px, Regular, LineHeight 36px).
  - Color: AppColors.darkText (#111827).
  - Alignment: Center.

* Password Input Field 01 (Enter password):
  - Dimensions: Width 345px x Height 56px, Corner Radius 16px (radius/md).
  - Position: X: 24, Y: 501.5.
  - Border: 1px outline (#E5E7EB).
  - Hint: "Enter password" (body/regular 14px, #9CA3AF).
  - Obscure Text: Enabled (••••••••).

* Password Policy Helper Text (نص إرشادات كلمة المرور):
  - Text: "كلمة المرور يجب أن تحتوي على 8 أحرف ورقم على الأقل"
  - Position: X: 24, Y: 584, Width: 356px, Height: 31px.
  - TextStyle: AppTypography.bodyThin (Google Sans Flex, 14px, Thin, LineHeight 20px).
  - Color: AppColors.mediumGray (#6B7280).
  - Alignment: Center.

* Password Input Field 02 (Re-Enter password):
  - Dimensions: Width 345px x Height 56px, Corner Radius 16px (radius/md).
  - Position: X: 24, Y: 630.
  - Border: 1px outline (#E5E7EB).
  - Hint: "Re-Enter password" (body/regular 14px, #9CA3AF).
  - Trailing Icon: Eye Toggle Icon (Icons.visibility_off_outlined, 24px, #6B7280) لتبديل الرؤية.

---

## 5. Primary CTA Button (زر المتابعة)
* Component: ❖ button/primary (Variant: Style = Solid).
* Label: "Next" (TextStyle: title/medium 20px, White #FFFFFF).
* Dimensions: Width 345px x Height 56px (radius/full 9999px).
* Position: X: 24, Y: 754.
* Interaction Logic: OnTap -> Validates password match -> Navigates to NewStudentEndScreen (Slide Left ←, 300ms, EaseOut).

---

## 6. Flutter Production Code (كود فلاتر الكامل للشاشة)

import 'package:flutter/material.dart';

class NewStudentPasswordScreen extends StatefulWidget {
  const NewStudentPasswordScreen({super.key});

  @override
  State<NewStudentPasswordScreen> createState() => _NewStudentPasswordScreenState();
}

class _NewStudentPasswordScreenState extends State<NewStudentPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscureConfirmPassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 1. الهيدر مع زر الرجوع
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(35),
                      child: Image.asset(
                        'assets/images/student_shield_art.png',
                        width: 369,
                        height: 325,
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
                'Secure your account',
                style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF111827),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // 3. حقل كلمة المرور الأول
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    hintStyle: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 4. نص إرشادات كلمة المرور (بنمط Thin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'كلمة المرور يجب أن تحتوي على 8 أحرف ورقم على الأقل',
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 13,
                    fontWeight: FontWeight.w100, // Thin Weight
                    color: Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // 5. حقل تأكيد كلمة المرور مع أيقونة العين
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    hintText: 'Re-Enter password',
                    hintStyle: const TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF6B7280),
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 6. زر التالي
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
                      if (_passwordController.text.isNotEmpty &&
                          _passwordController.text == _confirmPasswordController.text) {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const NewStudentEndScreen(),
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
                      }
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