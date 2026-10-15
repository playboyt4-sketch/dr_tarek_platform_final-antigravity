### 📱 Screen 07: Student Profile Photo Upload (`New Student - photo`) — APPROVED

#### 1. Frame & Layout:
* **Dimensions:** `393px` (Width) × `852px` (Height).
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).

#### 2. Header Section & Floating Controls:
* **Header Artwork (`New Student - photo artwork`):**
  * Artwork: Student holding a camera and framed photo.
  * Dimensions: Width `369px` × Height `357px` (Positioned at `X: 12`, `Y: 50`).
  * Corner Radius: `35px` on all corners.
* **Floating Glass Back Button (`❖ button/back`):**
  * Dimensions: `44 × 44 px` circle (`radius/full`).
  * Position: `X: 24`, `Y: 64`.
  * Material: Liquid Glass (`Fill: White 25%`, `Stroke: White 35%`, `Blur: 20px`).
  * Action: `OnTap` -> `Navigator.pop(context)` (`Push Right →`, `300ms`, `EaseOut`).

#### 3. Title & Photo Upload Target:
* **Question Title (`Add a photo`):**
  * Position: `Y: 439`, Height `69px`, Width `393px`.
  * TextStyle: `AppTypography.titleLarge` (`28px`, `Regular`, LineHeight `36px`).
  * Color: `AppColors.darkText` (`#111827`).
  * Alignment: Center (`TextAlign.center`).
* **Circular Upload Container (`Photo Upload Area`):**
  * Dimensions: `159 × 159 px` (Perfect Circle, Centered at `X: 117`, `Y: 534`).
  * Border: `1.5px` Dashed Border (`#D1D5DB` gray).
  * Center Icon: Blue Plus Icon (`+`, `Color: #1D4ED8`, Size: `32px`).
  * Interaction: `OnTap` -> Opens Native Image Picker (Camera / Gallery).
  * State (When Photo Selected): Replaces dashed border with circular avatar preview (`ClipOval`) + small edit badge.

#### 4. Primary CTA Button (`Next`):
* **Component:** `❖ button/primary` (`Style = Solid`).
* **Label:** `"Next"` (`title/medium` 20px, White `#FFFFFF`).
* **Dimensions:** Width `345px` × Height `56px` (`radius/full` 9999px).
* **Position:** `X: 24`, `Y: 754`.
* **Interaction Logic:** `OnTap` -> Validates/Skips photo -> Navigates to `NewStudentGradeScreen` (`Push Left ←`, `300ms`, `EaseOut`).

#### 5. Flutter Reference Code:
```dart
class NewStudentPhotoScreen extends StatefulWidget {
  const NewStudentPhotoScreen({super.key});

  @override
  State<NewStudentPhotoScreen> createState() => _NewStudentPhotoScreenState();
}

class _NewStudentPhotoScreenState extends State<NewStudentPhotoScreen> {
  File? _imageFile;

  Future<void> _pickImage() async {
    // كود التقاط الصورة من المعرض أو الكاميرا
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // الهيدر مع زر الرجوع
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: Image.asset('assets/images/student_camera_art.png', width: 369, height: 357, fit: BoxFit.cover),
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
            Text('Add a photo', style: AppTypography.titleLarge),
            const Spacer(),
            // دائرة رفع الصورة المنقطة
            GestureDetector(
              onTap: _pickImage,
              child: DottedBorderCircle(
                size: 159,
                image: _imageFile,
              ),
            ),
            const Spacer(),
            // زر التالي
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: PrimaryButton(
                title: 'Next',
                variant: ButtonVariant.solid,
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NewStudentGradeScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}