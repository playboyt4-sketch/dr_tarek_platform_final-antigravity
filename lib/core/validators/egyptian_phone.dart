/// Shared Egyptian mobile-number convention for Registration V1.
///
/// Single source of truth for the business format already used across the
/// app (`AuthPhoneField`, `StudentRegistrationWizard`, backend
/// `normalizeEgyptianPhone`): an 11-digit Egyptian mobile number starting
/// with `01`, **without** a country code.
///
/// V1 explicitly does NOT support the country-code form (`+20...` is
/// rejected). No `+20` conversion happens here — values are stored exactly
/// as entered (trimmed).
library;

/// Egyptian mobile numbers: `010`, `011`, `012`, `015` + 8 digits.
final RegExp egyptianPhoneRegExp = RegExp(r'^01[0125]\d{8}$');

/// Trims surrounding whitespace. Preserves the V1 representation convention:
/// no country-code handling, no `010...` → `+20...` conversion.
String normalizeEgyptianPhone(String raw) => raw.trim();

/// True when [normalized] (already trimmed) satisfies the V1 format.
bool isValidEgyptianPhone(String normalized) =>
    egyptianPhoneRegExp.hasMatch(normalized);
