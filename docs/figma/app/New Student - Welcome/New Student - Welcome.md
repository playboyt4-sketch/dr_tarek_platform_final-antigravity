### 📱 Screen 04: New Student Welcome (`New Student - Welcome`)

#### 1. Visual Assets & Structure:
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).
* **Header Illustration (`new_student_welcome_photo`):**
  * Concept: 4-piece Puzzle artwork featuring the 4 grade colors (Yellow, Blue, Green, Red).
  * Dimensions: Width `369px` × Height `395px` (Top-center aligned).
  * Top Margin: `50px` (directly below Status Bar).

#### 2. Typography & Brand Content:
* **Welcome Title:** `"Welcome to our community with"`
  * TextStyle: `AppTypography.titleLarge` (`28px`, `Regular`, LineHeight `36px`).
  * Color: `AppColors.darkText` (`#111827`).
  * Alignment: Center (`TextAlign.center`).
* **Brand Signature:**
  * Component: `❖ logo/signature`
  * Font Family: `Gardenia Summer` (128px).
  * Color: `AppColors.redGrade4` (`#DC2626` Brand Red Accent).
  * Alignment: Center.

#### 3. Primary CTA Button:
* **Component:** `❖ button/primary`
* **Variant:** `Style = Solid`
* **Label:** `"Get started"` (TextStyle: `title/medium` 20px, White `#FFFFFF`).
* **Dimensions:** Width `345px` × Height `56px` (`radius/full` 9999px).
* **Position:** Centered at `Bottom` with `24px` horizontal padding and `42px` bottom safe area.
* **Interaction Logic:** `OnTap` -> Navigates to `NewStudentNameScreen` with a horizontal slide transition (`Push Left`, `300ms`).

#### 4. Flutter Reference Code:
```dart
class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            // رسمة البازل المجمعة
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Image.asset('assets/images/welcome_puzzle.png', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            // عنوان الترحيب
            Text(
              'Welcome to our community\nwith',
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // التوقيع باللون الأحمر
            const LogoSignatureWidget(fontSize: 48, color: AppColors.redGrade4),
            const Spacer(),
            // زر البداية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: PrimaryButton(
                title: 'Get started',
                variant: ButtonVariant.solid,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NewStudentNameScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}