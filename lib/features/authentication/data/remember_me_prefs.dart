import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the login "Remember me" choice (default true = current
/// behavior: the Firebase session survives app restarts).
const String rememberMePrefsKey = 'remember_me';
const String rememberedPhonePrefsKey = 'remembered_phone';

/// Reads the persisted "Remember me" choice (true when unset).
Future<bool> loadRememberMeChoice() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(rememberMePrefsKey) ?? true;
  } catch (_) {
    return true;
  }
}

/// Persists the login "Remember me" choice. Best-effort, never throws.
Future<void> saveRememberMeChoice(bool rememberMe) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(rememberMePrefsKey, rememberMe);
  } catch (_) {
    // Persistence is a convenience — login must never fail because of it.
  }
}

/// Reads the persisted phone number if rememberMe is enabled.
Future<String?> loadRememberedPhone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(rememberMePrefsKey) ?? true;
    if (!rememberMe) return null;
    return prefs.getString(rememberedPhonePrefsKey);
  } catch (_) {
    return null;
  }
}

/// Persists or clears the remembered phone number based on [rememberMe].
/// NEVER stores passwords in SharedPreferences.
Future<void> saveRememberedPhone({required bool rememberMe, String? phone}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe && phone != null && phone.trim().isNotEmpty) {
      await prefs.setString(rememberedPhonePrefsKey, phone.trim());
    } else {
      await prefs.remove(rememberedPhonePrefsKey);
    }
  } catch (_) {
    // Best-effort
  }
}
