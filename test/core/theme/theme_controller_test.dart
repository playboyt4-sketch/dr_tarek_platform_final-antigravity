import 'package:dr_tarek_platform/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('parseThemeMode', () {
    test('maps every persisted value', () {
      expect(parseThemeMode('light'), ThemeMode.light);
      expect(parseThemeMode('dark'), ThemeMode.dark);
      expect(parseThemeMode('system'), ThemeMode.system);
    });

    test('unknown, null or corrupt values fall back to system', () {
      expect(parseThemeMode(null), ThemeMode.system);
      expect(parseThemeMode(''), ThemeMode.system);
      expect(parseThemeMode('DARK'), ThemeMode.system);
      expect(parseThemeMode('sepia'), ThemeMode.system);
    });
  });

  group('loadPersistedThemeMode', () {
    test('resolves to light while the Dark release gate is closed', () async {
      expect(kDarkModeReleased, isFalse);
      expect(await loadPersistedThemeMode(), ThemeMode.light);
    });

    test('a stored dark mode is ignored while the gate is closed', () async {
      SharedPreferences.setMockInitialValues({kThemeModePrefsKey: 'dark'});
      expect(await loadPersistedThemeMode(), ThemeMode.light);
    });
  });

  group('ThemeController', () {
    test('starts from the bootstrap value', () {
      final container = ProviderContainer(
        overrides: [
          initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeControllerProvider), ThemeMode.dark);
    });

    test('defaults to light while the Dark release gate is closed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeControllerProvider), ThemeMode.light);
    });

    test('setThemeMode updates state and persists it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);

      expect(container.read(themeControllerProvider), ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kThemeModePrefsKey), 'dark');
    });

    test('cycle walks light → dark → system → light from the gated default',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(themeControllerProvider.notifier);

      // The gate makes light the bootstrap default; the controller API is
      // still exercised in full so it is ready when the gate opens.
      expect(container.read(themeControllerProvider), ThemeMode.light);
      await controller.cycle();
      expect(container.read(themeControllerProvider), ThemeMode.dark);
      await controller.cycle();
      expect(container.read(themeControllerProvider), ThemeMode.system);
      await controller.cycle();
      expect(container.read(themeControllerProvider), ThemeMode.light);
    });

    test('a round trip through storage keeps the chosen mode', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(themeControllerProvider.notifier)
          .setThemeMode(ThemeMode.light);

      // Simulate the next cold start.
      expect(await loadPersistedThemeMode(), ThemeMode.light);
    });
  });
}
