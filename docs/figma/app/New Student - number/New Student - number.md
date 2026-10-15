### 📱 Screen 06: Student Phone Number Entry (`New Student - number`) — APPROVED

#### 1. Frame & Canvas:
* **Dimensions:** `393px` (Width) × `852px` (Height).
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).

#### 2. Header Section & Floating Controls:
* **Header Artwork (`New Student - number photo`):**
  * Artwork: Student talking on the phone with phone bubble icon.
  * Dimensions: Width `369px` × Height `355px` (Positioned at `X: 12`, `Y: 50`).
  * Corner Radius: `35px` on all corners.
* **Floating Glass Back Button (`❖ button/back`):**
  * Dimensions: `44 × 44 px` circle (`radius/full`).
  * Position: `X: 24`, `Y: 64`.
  * Material: Liquid Glass (`Fill: White 25%`, `Stroke: White 35%`, `Blur: 20px`).
  * Action: `OnTap` -> `Navigator.pop(context)` (`Push Right →`, `300ms`, `EaseOut`).

#### 3. Title & Phone Input Form:
* **Question Title (`Your phone number?`):**
  * Position: `Y: 437`, Height `64px`.
  * TextStyle: `AppTypography.titleLarge` (`28px`, `Regular`, LineHeight `36px`).
  * Color: `AppColors.darkText` (`#111827`).
  * Alignment: Center.
* **Phone Input Field Container:**
  * Dimensions: Width `345px` × Height `56px` to `64px` (Positioned at `X: 24`, `Y: 608`).
  * Corner Radius: `16px` (`radius/md`).
  * Border: `1px` subtle outline (`#E5E7EB`).
  * Label: `"phone number"` (`caption/small` 12px, `#6B7280`).
  * Hint / Placeholder: `"Enter your phone number"` (`body/regular` 14px, `#9CA3AF`).
  * Input Type: `TextInputType.phone` (Numeric keyboard with country code validation).

#### 4. Primary CTA Button (`Next`):
* **Component:** `❖ button/primary` (`Style = Solid`).
* **Label:** `"Next"` (`title/medium` 20px, White `#FFFFFF`).
* **Dimensions:** Width `345px` × Height `56px` (`radius/full` 9999px).
* **Position:** `X: 24`, `Y: 754`.
* **Interaction Logic:** `OnTap` -> Validates phone number format -> Navigates to `NewStudentPhotoScreen` (`Push Left ←`, `300ms`, `EaseOut`).

#### 5. Flutter Reference Code:
```dart
class NewStudentNumberScreen extends StatefulWidget {
  const NewStudentNumberScreen({super.key});

  @override
  State<NewStudentNumberScreen> createState() => _NewStudentNumberScreenState();
}

class _NewStudentNumberScreenState extends State<NewStudentNumberScreen> {
  final TextEditingController _phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // الهيدر التوضيحي مع زر الرجوع
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(35),
                      child: Image.asset('assets/images/student_phone_art.png', width: 369, height: 355, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 24,
                    child: GlassBackButton(onPressed: () => Navigator.pop(context)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Your phone number?', style: AppTypography.titleLarge),
              const SizedBox(height: 16),
              // حقل إدخال رقم الهاتف
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: CustomInputField(
                  controller: _phoneController,
                  label: 'phone number',
                  hint: 'Enter your phone number',
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(height: 32),
              // زر التالي
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: PrimaryButton(
                  title: 'Next',
                  variant: ButtonVariant.solid,
                  onPressed: () {
                    if (_phoneController.text.trim().isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NewStudentPhotoScreen()));
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}