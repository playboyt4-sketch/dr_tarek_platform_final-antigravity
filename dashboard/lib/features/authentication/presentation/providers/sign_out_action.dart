import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../../../applications/presentation/providers/join_applications_provider.dart';
import '../../../archive/presentation/providers/archive_provider.dart';
import '../../../home/presentation/providers/home_stats_provider.dart';
import '../../../students/presentation/providers/grade_pending_requests_provider.dart';
import '../../../students/presentation/providers/grade_students_provider.dart';
import 'auth_providers.dart';
import 'login_controller.dart';

/// Prompts the staff member to confirm signing out, calls Firebase sign-out,
/// resets/invalidates session and cached admin state, and returns immediately to
/// the login screen via [sessionProvider] / [DashboardRouter].
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Sign Out'),
      content: const Text(
        'Are you sure you want to sign out of the dashboard?\n'
        'هل أنت متأكد من تسجيل الخروج من لوحة التحكم؟',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sign Out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await ref.read(authRepositoryProvider).logout();
  } catch (_) {
    await FirebaseAuth.instance.signOut();
  }

  resetDashboardSessionProviders(ref);
}

/// Clears cached Riverpod session & admin dashboard providers on sign-out.
void resetDashboardSessionProviders(WidgetRef ref) {
  ref.read(loginControllerProvider.notifier).reset();
  ref.invalidate(sessionProvider);
  ref.invalidate(homeStatsProvider);
  ref.invalidate(homeAnalyticsProvider);
  ref.invalidate(gradeStudentsProvider);
  ref.invalidate(gradePendingRequestsProvider);
  ref.invalidate(gradeSubjectsProvider);
  ref.invalidate(joinApplicationsProvider);
  ref.invalidate(archivedStudentsProvider);
  ref.invalidate(archivedSubjectsProvider);
  ref.invalidate(archivedLecturesProvider);
}
