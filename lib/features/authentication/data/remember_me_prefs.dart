import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the login "Remember me" choice (default true = current
/// behavior: the Firebase session survives app restarts).
const String rememberMePrefsKey = 'remember_me';
const String rememberedPhonePrefsKey = 'remembered_phone';
const String rememberedPasswordStorageKey = 'remembered_password';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

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

/// Reads the persisted encrypted password from FlutterSecureStorage if rememberMe is enabled.
Future<String?> loadRememberedPassword() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(rememberMePrefsKey) ?? true;
    if (!rememberMe) return null;
    return await _secureStorage.read(key: rememberedPasswordStorageKey);
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

/// Persists or clears the remembered password in encrypted FlutterSecureStorage.
Future<void> saveRememberedPassword({required bool rememberMe, String? password}) async {
  try {
    if (rememberMe && password != null && password.isNotEmpty) {
      await _secureStorage.write(key: rememberedPasswordStorageKey, value: password);
    } else {
      await _secureStorage.delete(key: rememberedPasswordStorageKey);
    }
  } catch (_) {
    // Best-effort
  }
}

/// Clears all remembered credentials (both phone and password) immediately.
Future<void> clearRememberedCredentials() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(rememberedPhonePrefsKey);
    await _secureStorage.delete(key: rememberedPasswordStorageKey);
  } catch (_) {}
}
