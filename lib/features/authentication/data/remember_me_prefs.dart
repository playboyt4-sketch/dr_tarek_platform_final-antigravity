import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the login "Remember me" choice (default true = current
/// behavior: the Firebase session survives app restarts).
const String rememberMePrefsKey = 'remember_me';

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
