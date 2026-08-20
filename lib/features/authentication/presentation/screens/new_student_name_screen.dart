import 'package:flutter/material.dart';

class NewStudentNameScreen extends StatelessWidget {
  const NewStudentNameScreen({super.key});

  static const double designWidth = 393;
  static const double designHeight = 852;

  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color inputBorderColor = Color(0xFFD0D0D0);
  static const Color secondaryTextColor = Color(0xFF9A9A9A);

  static const double heroLeft = 6;
  static const double heroTop = 60;
  static const double heroWidth = 381;
  static const double heroHeight = 502;

  static const double inputLeft = 23;
  static const double inputTop = 608;
  static const double inputWidth = 347;
  static const double inputHeight = 69;

  static const double buttonLeft = 23;
  static const double buttonTop = 713;
  static const double buttonWidth = 347;
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
                            'assets/images/New Student - name.png',
                          ),
                          width: heroWidth,
                          height: heroHeight,
                          fit: BoxFit.fill,
                        ),
                      ),

                      Positioned(
                        left: inputLeft,
                        top: inputTop,
                        width: inputWidth,
                        height: inputHeight,
                        child: TextField(
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            color: secondaryTextColor,
                            height: 1.0,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            labelStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              color: secondaryTextColor,
                              height: 1.0,
                            ),
                            floatingLabelStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              color: secondaryTextColor,
                              height: 1.0,
                            ),
                            hintText: 'Enter your full name',
                            hintStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.w400,
                              color: secondaryTextColor,
                              height: 1.0,
                            ),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 18,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: inputBorderColor,
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: inputBorderColor,
                                width: 1,
                              ),
                            ),
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
                            onTap: () {},
                            child: const Center(
                              child: Text(
                                'Next',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
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
