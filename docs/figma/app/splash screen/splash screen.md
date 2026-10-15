### 📱 Screen 01 & 02: Splash Flow (`Splash Screen-START` & `Splash Screen-END`)

#### 1. Visual Assets & Tokens:
* **Background Canvas:** `AppColors.white` (`#FFFFFF`).
* **Logo Component (`❖ logo/signature`):** 
  * Font Family: `Gardenia Summer` (Brand Signature Font).
  * Font Size: `128px` (Regular).
  * Color: `AppColors.black` (`#000000`).
  * Alignment: Perfectly centered horizontally and vertically (`Alignment.center`).

#### 2. Animation & Timing Pipeline:
1. **Initial State (START):** The logo begins fully transparent (`Opacity: 0.0`).
2. **Fade-In Transition:** 
   * Trigger: `After delay: 300ms`.
   * Animation: Smooth `Fade-in / Smart Animate` to `Opacity: 1.0` with duration `800ms` (`Curves.easeOut`).
3. **Hold State (END):** The logo remains visible and static for **`5000ms` (5 seconds)**.
4. **Shared Element Exit Transition:** 
   * Transition Type: `Hero Animation / Shared Element Transition`.
   * The `logo/signature` smoothly glides from screen center to the bottom footer position of `UserTypeSelectionScreen` over `800ms` (`Curves.easeOut`).

#### 3. Flutter Reference Code (Logic & Layout):
```dart
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    // 1. بدء الظهور بعد 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _opacity = 1.0);
    });

    // 2. الانتظار 5 ثوان ثم الانتقال بالـ Hero Animation
    Future.delayed(const Duration(milliseconds: 5800), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder: (_, __, ___) => const UserTypeSelectionScreen(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: Hero(
          tag: 'brand_logo_signature',
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            child: const LogoSignatureWidget(fontSize: 128),
          ),
        ),
      ),
    );
  }
}