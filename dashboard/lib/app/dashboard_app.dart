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
      home: const DashboardRouter(),
    );
  }
}
