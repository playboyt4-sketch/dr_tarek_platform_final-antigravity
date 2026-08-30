# 📱 Component / Overlay: Minimalist Photo Picker Action Sheet (modal/photo-picker) — APPROVED

---

## 1. Overview & Behavior (نظرة عامة وسلوك المكون)
قائمة سفلية منبثقة بنمط الزجاج المثلج الكثيف (Heavy Frosted Glass) تتيح للطالب اختيار مصدر الصورة الشخصية (الكاميرا أو معرض الصور) بدون أزرار إغلاق تقليدية، معتمدة على إيماءات السحب واللمس الحديثة.

---

## 2. Frame Dimensions & Material (الأبعاد وخامة الزجاج)
* Frame Name: modal/photo-picker (أو New Student - upload photo).
* Width (العرض): 393px (مطابق لعرض شاشة الموبايل بالكامل).
* Height (الارتفاع المعتمد): 350px.
* Corner Radius (الزوايا): 
  - Top-Left: 24px
  - Top-Right: 24px
  - Bottom-Left: 0px
  - Bottom-Right: 0px
* Material & Effects (الخامة والتأثيرات الزجاجية):
  - Background Fill: AppColors.white (#FFFFFF) بنسبة شفافية 80%.
  - Border Stroke: 1px Inside بلون rgba(255, 255, 255, 0.40).
  - Backdrop Filter: Background blur: 40px (يحجب ويموه أي نصوص أو أزرار بالصفحة الخلفية ويعكس الإضاءة).

---

## 3. Internal Elements & Action Rows (عناصر القائمة الداخلية)

* Top Drag Handle (مقبض السحب العلوي):
  - Dimensions: Width 36px x Height 4px.
  - Corner Radius: 9999px (radius/full).
  - Color: #E5E7EB (Light Gray).
  - Position: Top-center aligned (X: 179, Y: 12).

* Row 01: Camera Action Button (Take a photo):
  - Container: Auto Layout Frame بعرض 345px x ارتفاع 54px عند موقع X: 24, Y: 45.
  - Corner Radius: 16px (radius/md).
  - Background Fill: #F9FAFB (Soft Light Gray) with 1px border #E5E7EB.
  - Leading Icon: Camera Icon (24px, Color: #111827).
  - Label: "Take a photo" (TextStyle: AppTypography.titleMedium 20px, Color: #111827).
  - Interaction: OnTap -> Opens Device Camera via ImageSource.camera -> Returns File -> Closes Sheet.

* Row 02: Gallery Action Button (Choose from gallery):
  - Container: Auto Layout Frame بعرض 345px x ارتفاع 54px عند موقع X: 24, Y: 115.
  - Corner Radius: 16px (radius/md).
  - Background Fill: #F9FAFB (Soft Light Gray) with 1px border #E5E7EB.
  - Leading Icon: Gallery Icon (24px, Color: #111827).
  - Label: "Choose from gallery" (TextStyle: AppTypography.titleMedium 20px, Color: #111827).
  - Interaction: OnTap -> Opens Device Gallery via ImageSource.gallery -> Returns File -> Closes Sheet.

---

## 4. Dismissal Gestures & Prototype Config (إيماءات وإعدادات البروتايب)
* Opening Trigger: OnTap على الدائرة المنقطة Group 3 في شاشة New Student - photo.
* Action: Open overlay -> Target: New Student - upload photo.
* Overlay Position: Bottom center.
* Dimming Scrim: Add background behind overlay enabled with #000000 at 40% opacity.
* Entrance Animation: Move in (Direction: Up, 300ms, EaseOut).
* Dismiss Gesture 1 (Swipe): OnDrag لأسفل على الإطار -> Close overlay.
* Dismiss Gesture 2 (Scrim Tap): Close when clicking outside enabled.

---

## 5. Flutter Production Code (Height: 350px)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoPickerActionSheet extends StatelessWidget {
  final Function(ImageSource source) onSourceSelected;

  const PhotoPickerActionSheet({
    super.key,
    required this.onSourceSelected,
  });

  /// دالة استدعاء القائمة السفلية
  static Future<ImageSource?> show(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      barrierColor: Colors.black.withOpacity(0.40),
      builder: (ctx) => PhotoPickerActionSheet(
        onSourceSelected: (source) => Navigator.pop(ctx, source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: double.infinity,
          height: 350,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.80),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.40)),
          ),
          child: Column(
            children: [
              // 1. مقبض السحب
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              const SizedBox(height: 28),
              // 2. زر الكاميرا
              _buildOptionTile(
                icon: Icons.camera_alt_outlined,
                title: 'Take a photo',
                onTap: () => onSourceSelected(ImageSource.camera),
              ),
              const SizedBox(height: 16),
              // 3. زر المعرض
              _buildOptionTile(
                icon: Icons.photo_library_outlined,
                title: 'Choose from gallery',
                onTap: () => onSourceSelected(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: const Color(0xFF111827)),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}