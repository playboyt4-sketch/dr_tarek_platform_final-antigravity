import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization/locale_controller.dart';
import '../core/routing/app_router.dart';
import '../core/security/app_lock_gate.dart';
import '../core/security/screen_guard.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../l10n/generated/app_localizations.dart';

class DrTarekPlatformApp extends ConsumerWidget {
  const DrTarekPlatformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      // ADR-009: Light Mode is the canonical approved design and remains
      // byte-identical; Dark Mode is an additive rendering of the same design
      // system. `system` is the default appearance and follows live OS
      // changes. Changing the mode only swaps the theme — the router instance
      // and all widget state (navigation, form data, auth) are preserved.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // --- i18n wiring ---
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: locale.languageCode == 'ar'
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: ValueListenableBuilder<bool>(
          valueListenable: ScreenGuard.isRecording,
          builder: (context, isRecording, _) {
            final appChild = AppLockGate(
              child: child ?? const SizedBox.shrink(),
            );
            if (!isRecording) return appChild;
            return Stack(
              fit: StackFit.expand,
              children: [
                appChild,
                Positioned.fill(
                  child: AbsorbPointer(
                    absorbing: true,
                    child: Container(
                      color: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off_rounded,
                              size: 64,
                              color: Colors.white,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'تسجيل الشاشة غير مسموح',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'يرجى إيقاف تسجيل أو مشاركة الشاشة للمتابعة',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      routerConfig: appRouter,
    );
  }
}
