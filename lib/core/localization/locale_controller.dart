import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'dart:ui' show Locale;

/// Supported locales, ordered by default preference (Arabic first).
const List<Locale> kSupportedLocales = [Locale('ar'), Locale('en')];

const String _prefsKey = 'app_locale';

/// Provided at bootstrap with the persisted locale so the first frame
/// is rendered in the correct language without a flash.
final initialLocaleProvider = Provider<Locale>(
  (ref) => throw UnimplementedError('initialLocaleProvider must be overridden'),
);

/// Current app locale controller.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => ref.watch(initialLocaleProvider);

  Future<void> setLocale(Locale locale) async {
    final normalized = kSupportedLocales.firstWhere(
      (l) => l.languageCode == locale.languageCode,
      orElse: () => const Locale('ar'),
    );
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized.languageCode);
  }
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);

/// Loads the persisted locale at startup; defaults to Arabic.
Future<Locale> loadPersistedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_prefsKey);
  return kSupportedLocales.any((l) => l.languageCode == code)
      ? Locale(code!)
      : const Locale('ar');
}
