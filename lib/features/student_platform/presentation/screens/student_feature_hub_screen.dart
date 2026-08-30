import 'package:flutter/material.dart';

import '../../../authentication/domain/entities/auth_user.dart';
import '../../../bookmarks/presentation/screens/student_bookmarks_screen.dart';
import '../../../exams/presentation/screens/published_exams_screen.dart';
import '../../../membership/presentation/screens/membership_plans_screen.dart';
import '../../../notes/presentation/screens/student_notes_screen.dart';
import '../../../notifications/presentation/screens/notifications_list_screen.dart';
import '../../../profile/presentation/screens/student_profile_screen.dart';
import '../../../timeline_quizzes/presentation/screens/published_quizzes_screen.dart';

/// Student feature hub — pure navigation shell.
/// Every feature screen lives in its own feature module and talks to
/// repositories; this file contains no data access or business logic.
/// TODO: replace with Figma-precise geometry when 03_UI_UX.md is Approved for these screens.
class StudentFeatureHubScreen extends StatelessWidget {
  final AuthUser user;

  /// When true the hub renders without its own Scaffold/AppBar so it can be
  /// embedded inside the student home tab shell.
  final bool embedded;

  const StudentFeatureHubScreen({required this.user, this.embedded = false, super.key});

  List<_FeatureItem> _buildFeatures(BuildContext context) {
    return <_FeatureItem>[
      _FeatureItem(
        'الاختبارات القصيرة',
        Icons.quiz_outlined,
        () => _open(context, QuizzesScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'الامتحانات',
        Icons.assignment_outlined,
        () => _open(context, ExamsScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'ملاحظاتي',
        Icons.note_alt_outlined,
        () => _open(context, NotesScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'المحفوظات',
        Icons.bookmark_border_rounded,
        () => _open(context, BookmarksScreen(studentId: user.id)),
      ),
      // "Questions to Admin" system was removed from the current phase;
      // Firestore rules deny the `questions` collection server-side.
      _FeatureItem(
        'الإشعارات',
        Icons.notifications_none_rounded,
        () => _open(context, NotificationsScreen(studentId: user.id)),
      ),
      _FeatureItem(
        'الخطط والاشتراكات',
        Icons.workspace_premium_outlined,
        () => _open(context, MembershipPlansScreen(user: user)),
      ),
      _FeatureItem(
        'ملفي الشخصي',
        Icons.person_outline_rounded,
        () => _open(context, StudentProfileScreen(user: user)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final features = _buildFeatures(context);

    final list = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: features.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final feature = features[index];
        return Card(
          child: ListTile(
            leading: Icon(feature.icon, color: const Color(0xFF2563EB)),
            title: Text(feature.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: feature.onOpen,
          ),
        );
      },
    );

    if (embedded) {
      return list;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('مركز الميزات')),
      body: list,
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _FeatureItem {
  final String label;
  final IconData icon;
  final VoidCallback onOpen;

  const _FeatureItem(this.label, this.icon, this.onOpen);
}
