import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'dashboard_router.dart';

class DashboardApp extends ConsumerWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Dr Tarek Dashboard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Deep-link support: on web the live URL path (`/doctor`, `/admin`)
      // becomes the initial route via the Hosting SPA rewrite; elsewhere
      // this falls back to `/`. Path selection is UX-only — the session
      // role rendered by [DashboardRouter] decides actual access.
      initialRoute: Uri.base.path,
      onGenerateRoute: buildDashboardRoute,
    );
  }
}
