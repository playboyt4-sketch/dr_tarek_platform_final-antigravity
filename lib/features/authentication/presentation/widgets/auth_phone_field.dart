import 'package:flutter/material.dart';

import '../../../../../l10n/generated/app_localizations.dart';

class AuthPhoneField extends StatelessWidget {
  final TextEditingController controller;

  const AuthPhoneField({super.key, required this.controller});

  static final RegExp _egyptianPhone = RegExp(r'^01[0125]\d{8}$');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      autofillHints: const [AutofillHints.telephoneNumber],
      validator: (value) {
        final normalized = value?.trim() ?? '';
        if (normalized.isEmpty) return l10n.errorValidation;
        if (!_egyptianPhone.hasMatch(normalized)) return l10n.errorValidation;
        return null;
      },
      decoration: InputDecoration(
        labelText: l10n.loginPhoneHint,
        hintText: '01000000000',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
