import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/home_stats_provider.dart';

/// Dashboard home content (Figma frame 457:421): brand title, the
/// "Analytics & Reports" section heading over a 3 px rule, live platform
/// stat cards and a bordered panel reserved for detailed charts.
class DashboardHomeScreen extends ConsumerWidget {
  const DashboardHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = context.rs;
    final statsAsync = ref.watch(homeStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: 'Tarek el araby ',
            style: AppTypography.homeTitleHeavy(fontSize: rs(96)),
            children: <InlineSpan>[
              TextSpan(
                text: 'Platform',
                style: AppTypography.homeTitleLight(fontSize: rs(96)),
              ),
            ],
          ),
        ),
        SizedBox(height: rs(140)),
        Text(
          'Analytics & Reports',
          style: AppTypography.sectionHeading(fontSize: rs(32)),
        ),
        SizedBox(height: rs(14)),
        Container(
          width: rs(880),
          height: rs(3),
          color: AppColors.ink,
        ),
        SizedBox(height: rs(30)),
        statsAsync.when(
          loading: () => Padding(
            padding: EdgeInsets.symmetric(vertical: rs(48)),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.ink),
            ),
          ),
          error: (Object error, StackTrace _) => Text(
            'Could not load platform stats. Please refresh later.',
            style: AppTypography.statLabel(fontSize: rs(22)),
          ),
          data: (HomeStats stats) => Wrap(
            spacing: rs(24),
            runSpacing: rs(24),
            children: <Widget>[
              _StatCard(value: stats.students, label: 'Students'),
              _StatCard(value: stats.subjects, label: 'Subjects'),
              _StatCard(
                value: stats.pendingApplications,
                label: 'Pending Applications',
              ),
              _StatCard(value: stats.staff, label: 'Staff'),
            ],
          ),
        ),
        SizedBox(height: rs(24)),
        Container(
          height: rs(420),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.inputStroke, width: 1.5),
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: Text(
            'Charts and detailed reports will appear here',
            style: AppTypography.statLabel(fontSize: rs(24)),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final int value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      width: rs(220),
      padding: EdgeInsets.symmetric(
        horizontal: rs(24),
        vertical: rs(28),
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.inputStroke, width: 1.5),
        borderRadius: BorderRadius.circular(28),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$value',
            style: AppTypography.statValue(fontSize: rs(44)),
          ),
          SizedBox(height: rs(10)),
          Text(
            label,
            style: AppTypography.statLabel(fontSize: rs(20)),
          ),
        ],
      ),
    );
  }
}
