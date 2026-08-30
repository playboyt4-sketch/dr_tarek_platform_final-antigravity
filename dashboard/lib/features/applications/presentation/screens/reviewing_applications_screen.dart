import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/dashboard_filter_dropdown.dart';
import '../../domain/entities/join_application.dart';
import '../../domain/grade.dart';
import '../providers/join_applications_provider.dart';

class ReviewingApplicationsScreen extends ConsumerStatefulWidget {
  const ReviewingApplicationsScreen({super.key});

  @override
  ConsumerState<ReviewingApplicationsScreen> createState() =>
      _ReviewingApplicationsScreenState();
}

class _ReviewingApplicationsScreenState
    extends ConsumerState<ReviewingApplicationsScreen> {
  static const String allGrades = 'all';

  static final Map<String, String> gradeFilters = <String, String>{
    allGrades: 'الكل',
    for (final String key in canonicalGradeKeys) key: gradeDisplayName(key),
  };

  String _selectedGrade = allGrades;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final AsyncValue<List<JoinApplication>> applicationsAsync =
        ref.watch(joinApplicationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Joining Applications',
          style: AppTypography.sectionHeading(fontSize: rs(32)),
        ),
        SizedBox(height: rs(14)),
        Container(width: rs(880), height: rs(3), color: AppColors.ink),
        SizedBox(height: rs(30)),
        DashboardFilterDropdown<String>(
          value: _selectedGrade,
          items: gradeFilters,
          onChanged: (String? value) =>
              setState(() => _selectedGrade = value ?? allGrades),
        ),
        SizedBox(height: rs(24)),
        applicationsAsync.when(
          loading: () => Padding(
            padding: EdgeInsets.symmetric(vertical: rs(48)),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.ink),
            ),
          ),
          error: (Object error, StackTrace _) => Text(
            'تعذر تحميل طلبات الانضمام.',
            style: AppTypography.statLabel(fontSize: rs(24)),
          ),
          data: (List<JoinApplication> applications) {
            final List<JoinApplication> filtered =
                _selectedGrade == allGrades
                    ? applications
                    : applications
                        .where(
                          (JoinApplication app) =>
                              app.gradeKey == _selectedGrade,
                        )
                        .toList(growable: false);
            if (filtered.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: rs(48)),
                child: Center(
                  child: Text(
                    'لا توجد طلبات انضمام حالياً.',
                    style: AppTypography.statLabel(fontSize: rs(24)),
                  ),
                ),
              );
            }
            return Column(
              children: <Widget>[
                for (final JoinApplication application in filtered)
                  Padding(
                    padding: EdgeInsets.only(bottom: rs(16)),
                    child: _ApplicationCard(application: application),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final JoinApplication application;

  const _ApplicationCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final String? studentType = studentTypeDisplayName(application.studentType);
    final DateTime? createdAt = application.createdAt;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: rs(28), vertical: rs(26)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.inputStroke, width: 1.5),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  application.fullName,
                  style: AppTypography.statValue(fontSize: rs(30)),
                ),
                SizedBox(height: rs(10)),
                Text(
                  application.phone,
                  style: AppTypography.statLabel(fontSize: rs(22)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _GradeChip(label: gradeDisplayName(application.gradeKey)),
              if (studentType != null) ...<Widget>[
                SizedBox(height: rs(10)),
                _InfoChip(label: studentType),
              ],
              if (createdAt != null) ...<Widget>[
                SizedBox(height: rs(10)),
                Text(
                  '${createdAt.year}/'
                  '${createdAt.month.toString().padLeft(2, '0')}/'
                  '${createdAt.day.toString().padLeft(2, '0')}',
                  style: AppTypography.statLabel(fontSize: rs(20)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  final String label;

  const _GradeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: rs(18), vertical: rs(8)),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(rs(100)),
      ),
      child: Text(
        label,
        style: AppTypography.buttonLabel(fontSize: rs(20)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: rs(18), vertical: rs(8)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.inputStroke, width: 1.5),
        borderRadius: BorderRadius.circular(rs(100)),
      ),
      child: Text(
        label,
        style: AppTypography.statLabel(fontSize: rs(20)),
      ),
    );
  }
}
