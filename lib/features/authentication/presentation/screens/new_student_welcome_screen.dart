import 'package:flutter/material.dart';

import 'student_registration_wizard.dart';

class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  static const double designWidth = 393;
  static const double designHeight = 852;

  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color primaryBlue = Color(0xFF2563EB);

  static const double heroLeft = 12;
  static const double heroTop = 62;
  static const double heroWidth = 369;
  static const double heroHeight = 395;

  static const double titleTop = 477;
  static const double titleHeight = 116;

  static const double brandTop = 593;
  static const double brandHeight = 121;

  static const double subtitleTop = 719;
  static const double subtitleHeight = 29;

  static const double buttonLeft = 12;
  static const double buttonTop = 763;
  static const double buttonWidth = 369;
  static const double buttonHeight = 69;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final widthScale = constraints.maxWidth / designWidth;
          final heightScale = constraints.maxHeight / designHeight;
          final scale = widthScale < heightScale ? widthScale : heightScale;

          return Center(
            child: SizedBox(
              width: designWidth * scale,
              height: designHeight * scale,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: designWidth,
                  height: designHeight,
                  child: Stack(
                    children: [
                      const Positioned(
                        left: heroLeft,
                        top: heroTop,
                        width: heroWidth,
                        height: heroHeight,
                        child: Image(
                          image: AssetImage(
                            'assets/images/New Student - Welcome.png',
                          ),
                          width: heroWidth,
                          height: heroHeight,
                          fit: BoxFit.fill,
                        ),
                      ),

                      const Positioned(
                        left: 0,
                        top: titleTop,
                        width: designWidth,
                        height: titleHeight,
                        child: Text(
                          'Welcome to our\nsociety with',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),

                      const Positioned(
                        left: 0,
                        top: brandTop,
                        width: designWidth,
                        height: brandHeight,
                        child: Text(
                          'Tarek el araby',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Gardenia Summer',
                            fontSize: 128,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),

                      const Positioned(
                        left: 0,
                        top: subtitleTop,
                        width: designWidth,
                        height: subtitleHeight,
                        child: Text(
                          'Go pro to unlock our features',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                            height: 1.0,
                          ),
                        ),
                      ),

                      Positioned(
                        left: buttonLeft,
                        top: buttonTop,
                        width: buttonWidth,
                        height: buttonHeight,
                        child: Material(
                          color: primaryBlue,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const StudentRegistrationWizard(),
                                ),
                              );
                            },
                            child: const Center(
                              child: Text(
                                'Get started',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: backgroundColor,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
