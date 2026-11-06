import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted appearance preference key.
///
/// Mirrors `app_locale` in [LocaleController]: local-only, no Firebase, no
/// schema, no authentication dependency.
const String kThemeModePrefsKey = 'app_theme_mode';

/// ADR-009 release gate for Dark Mode.
///
/// 37 of the 48 inventoried screens remain Light-only (owner decision D7), so
/// the QA report forbids exposing Dark Mode to users until those screens have
/// approved Dark specifications. While this is `false`, the bootstrap always
/// resolves to [ThemeMode.light] regardless of the OS brightness or a stored
/// preference; the Light theme stays byte-identical to the approved design.
///
/// Flip to `true` only after the remaining screens are migrated and the
/// on-device QA gate in `docs/theme-migration/PHASE_9_QA_REPORT.md` passes.
const bool kDarkModeReleased = false;

/// Provided at bootstrap with the persisted appearance so the first frame is
/// rendered in the correct brightness, with no flash of the wrong theme.
///
/// While [kDarkModeReleased] is `false` this is [ThemeMode.light]; widget
/// tests and previews that do not override it therefore get the approved
/// behaviour. Tests that exercise the Dark wiring override this provider
/// explicitly.
final initialThemeModeProvider = Provider<ThemeMode>(
  (ref) => kDarkModeReleased ? ThemeMode.system : ThemeMode.light,
);

/// Current appearance controller.
///
/// Changing the mode only swaps the `MaterialApp` theme; it does not rebuild
/// the router, so navigation state, form data and authentication are
/// preserved.
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModePrefsKey, mode.name);
  }

  /// Cycles system → light → dark → system.
  Future<void> cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    return setThemeMode(next);
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// Loads the persisted appearance at startup.
///
/// While [kDarkModeReleased] is `false`, the gate forces [ThemeMode.light] so
/// a stored `dark`/`system` value cannot expose the partially migrated Dark
/// theme to testers. Never throws: a persistence failure must not block boot.
Future<ThemeMode> loadPersistedThemeMode() async {
  if (!kDarkModeReleased) return ThemeMode.light;
  try {
    final prefs = await SharedPreferences.getInstance();
    return parseThemeMode(prefs.getString(kThemeModePrefsKey));
  } catch (_) {
    return ThemeMode.system;
  }
}

/// Maps a persisted string to a [ThemeMode]. Unknown input → `system`.
ThemeMode parseThemeMode(String? raw) {
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
