import 'package:flutter/material.dart';

import '../../../../../l10n/generated/app_localizations.dart';

class AuthPasswordField extends StatefulWidget {
  final TextEditingController controller;

  const AuthPasswordField({super.key, required this.controller});

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) =>
          (value == null || value.isEmpty) ? l10n.errorValidation : null,
      decoration: InputDecoration(
        labelText: l10n.loginPasswordHint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: () {
            setState(() {
              _obscure = !_obscure;
            });
          },
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}
