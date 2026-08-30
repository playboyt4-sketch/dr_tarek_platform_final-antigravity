/// Egyptian mobile number format for V1 (per FINAL_DECISIONS Section 3):
/// 11 digits starting with 010/011/012/015, no country code.
final RegExp egyptianPhoneRegExp = RegExp(r'^01[0125]\d{8}$');

/// Pure domain validation. UI widgets never implement business rules.
bool isValidEgyptianPhoneNumber(String input) =>
    egyptianPhoneRegExp.hasMatch(input.trim());
