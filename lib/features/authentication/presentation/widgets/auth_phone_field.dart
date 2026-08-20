import 'package:flutter/material.dart';

class AuthPhoneField extends StatelessWidget {
  final TextEditingController controller;

  const AuthPhoneField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      decoration: const InputDecoration(
        labelText: 'Phone Number',
        hintText: '01000000000',
        border: OutlineInputBorder(),
      ),
    );
  }
}
