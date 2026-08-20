import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const Color backgroundColor = Color(0xFFFFFFFF);
  static const Color logoColor = Colors.black;

  static const double designWidth = 393;
  static const double logoTop = 366;
  static const double logoFontSize = 170;
  static const Duration logoFadeDuration = Duration(milliseconds: 300);
  static const String logoText = 'Tarek el araby';
  static const String logoFontFamily = 'Gardenia Summer';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: SplashScreen.logoFadeDuration,
      lowerBound: 0,
      upperBound: 1,
    )..forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final scale = screenWidth / SplashScreen.designWidth;

    return Scaffold(
      backgroundColor: SplashScreen.backgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: SplashScreen.logoTop * scale,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _logoController,
              child: Hero(
                tag: 'splash-logo',
                child: Text(
                  SplashScreen.logoText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: SplashScreen.logoFontFamily,
                    fontSize: SplashScreen.logoFontSize * scale,
                    color: SplashScreen.logoColor,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
