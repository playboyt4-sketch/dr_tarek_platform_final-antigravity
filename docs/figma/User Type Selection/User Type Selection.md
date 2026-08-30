### 📱 Screen 03: User Type Selection Gateway (`User Type Selection`)

#### 1. Visual Assets & Layout:
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).
* **Page Padding:** Horizontal `24px` (`spacing/24`).

#### 2. Header Elements:
* **Title:** `"I am a"`
  * TextStyle: `AppTypography.titleLarge` (`28px`, `Regular`, LineHeight `36px`).
  * Color: `AppColors.darkText` (`#111827`).
  * Alignment: Center.
* **Subtitle:** `"Select one that applies to you"`
  * TextStyle: `AppTypography.bodyRegular` (`14px`, `Regular`, LineHeight `20px`).
  * Color: `AppColors.mediumGray` (`#6B7280`).
  * Top Margin: `8px` (`spacing/8`).

#### 3. Selection Cards (Interactive Tiles):
1. **New Student Card (`طالب جديد`):**
   * Background: `AppColors.yellowGrade1` (`#F59E0B`).
   * Width: `345px` | Corner Radius: `16px` (`radius/md`).
   * Title: `"طالب جديد"` with `AppTypography.titleMedium` (`20px`, White `#FFFFFF`).
   * Illustration: `new_student_photo` (Top-right alignment).
   * Interaction: `OnTap` -> Navigates to `NewStudentWelcomeScreen` with a smooth horizontal slide transition (`Push Left`, `300ms`).

2. **Current Student Card (`طالب حالي`):**
   * Background: `AppColors.redGrade4` (`#DC2626`).
   * Width: `345px` | Corner Radius: `16px` (`radius/md`).
   * Title: `"طالب حالي"` with `AppTypography.titleMedium` (`20px`, White `#FFFFFF`).
   * Illustration: `current_student_photo`.
   * Interaction: `OnTap` -> Navigates to `CurrentStudentSignInScreen`.

#### 4. Footer & Secondary Gateway:
* **Brand Signature:** `Hero(tag: 'brand_logo_signature', child: LogoSignatureWidget(fontSize: 48))`
* **Academic Year Tag:** `"2026-2027"` with `AppTypography.captionSmall` (`12px`, `#6B7280`).
* **Admin / Teacher Icon Button:**
  * Dimensions: `40x40 px` circular avatar (`radius/full`).
  * Interaction: `OnTap` -> Opens `TeacherAdminLoginBottomSheet` or Admin Gateway.

#### 5. Flutter Reference Code:
```dart
class UserTypeSelectionScreen extends StatelessWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Text('I am a', style: AppTypography.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Select one that applies to you', style: AppTypography.bodyRegular.copyWith(color: AppColors.mediumGray)),
              const SizedBox(height: 24),
              // كارت طالب جديد
              Expanded(
                child: StudentTypeCard(
                  title: 'طالب جديد',
                  color: AppColors.yellowGrade1,
                  assetImage: 'assets/images/new_student.png',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewStudentWelcomeScreen())),
                ),
              ),
              const SizedBox(height: 16),
              // كارت طالب حالي
              Expanded(
                child: StudentTypeCard(
                  title: 'طالب حالي',
                  color: AppColors.redGrade4,
                  assetImage: 'assets/images/current_student.png',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrentStudentSignInScreen())),
                ),
              ),
              const SizedBox(height: 16),
              const Hero(tag: 'brand_logo_signature', child: LogoSignatureWidget(fontSize: 40)),
              Text('2026-2027', style: AppTypography.captionSmall.copyWith(color: AppColors.mediumGray)),
              const SizedBox(height: 8),
              IconButton(icon: const Icon(Icons.person_outline, size: 24), onPressed: () {}),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}