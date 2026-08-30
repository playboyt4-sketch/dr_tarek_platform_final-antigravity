import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import 'student_registration_wizard.dart';

class NewStudentWelcomeScreen extends StatelessWidget {
  const NewStudentWelcomeScreen({super.key});

  static const Color backgroundColor = Color(0xFFFFFCF7);
  static const Color primaryBlue = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.pagePadding,
              vertical: rs(24),
            ),
            child: context.centerContent(
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: rs(16)),
                  // Hero Image
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: rs(370),
                        maxHeight: rs(400),
                      ),
                      child: Image.asset(
                        'assets/images/New Student - Welcome .png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return SizedBox(
                            height: rs(200),
                            child:
                                Icon(Icons.school, size: rs(80), color: primaryBlue),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: rs(32)),
                  // Welcome Title
                  Text(
                    'Welcome to our\nsociety with',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: rs(40),
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: rs(12)),
                  // Brand Text (Signature style)
                  Text(
                    'Tarek el araby',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Gardenia Summer',
                      fontSize: rs(88),
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: rs(8)),
                  // Subtitle
                  Text(
                    'Go pro to unlock our features',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: rs(20),
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: rs(48)),
                  // Get Started Button
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      height: rs(64),
                      child: Material(
                        color: primaryBlue,
                        borderRadius: BorderRadius.circular(rs(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(rs(12)),
                          onTap: () => _openRegistration(context),
                          child: Center(
                            child: Text(
                              'Get started',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: rs(22),
                                fontWeight: FontWeight.w700,
                                color: backgroundColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: rs(24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openRegistration(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StudentRegistrationWizard()),
    );
  }
}
