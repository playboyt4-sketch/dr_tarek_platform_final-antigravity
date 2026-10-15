import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../applications/presentation/widgets/application_decision_dialog.dart';
import '../providers/grade_pending_requests_provider.dart';
import '../providers/grade_students_provider.dart';
import 'grade_students_screen.dart'
    show gradeAccent;

const List<({String key, String label})> _grades =
    <({String key, String label})>[
  (key: 'grade_one', label: 'Grade One'),
  (key: 'grade_two', label: 'Grade Two'),
  (key: 'grade_three', label: 'Grade Three'),
  (key: 'grade_four', label: 'Grade Four'),
];

/// Grade pending-requests screen (`# Grade- Grade one pending requests`):
/// fixed 1280 x 800 canvas, pure white.
///
/// - header: brand 540 x 80 at (370, 24); the unified shell draws the
///   single fixed menu button at (80, 24, 80 x 80);
/// - grades nav 660 x 40 at (310, 136) with a 1 px #979797 outer stroke,
///   pills 160 x 32 (gap 4), active pill filled with the grade accent;
/// - sub tabs 336 x 40 at (472, 190), Students active / Subjects;
/// - title banner 448 x 76 at (416, 270): full capsule, 1.5 px accent
///   stroke, "Pending Requests" 30 Medium #374151, perfectly centered;
/// - requests table (78, 420, 1120 x 390): radius 16, 1 px #E5E7EB
///   border, soft shadow, 40 px sticky header (6 columns) + 48 px
///   scrollable rows, 88 x 32 View buttons opening the shared
///   [ApplicationDecisionDialog] with automatic table refresh.
class GradePendingRequestsScreen extends ConsumerStatefulWidget {
  final String initialGradeKey;
  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onStudentsTab;
  final ValueChanged<String>? onSubjectsTab;

  /// When provided, View navigates to the full review screen instead of
  /// opening the inline decision dialog.
  final ValueChanged<PendingRequestRow>? onViewRequest;

  const GradePendingRequestsScreen({
    super.key,
    this.initialGradeKey = 'grade_one',
    this.onMenuPressed,
    this.onStudentsTab,
    this.onSubjectsTab,
    this.onViewRequest,
  });

  @override
  ConsumerState<GradePendingRequestsScreen> createState() =>
      _GradePendingRequestsScreenState();
}

class _GradePendingRequestsScreenState
    extends ConsumerState<GradePendingRequestsScreen> {
  late String _gradeKey = widget.initialGradeKey;

  Color get _accent => gradeAccent(_gradeKey);

  Future<void> _openDecision(PendingRequestRow row) async {
    if (widget.onViewRequest != null) {
      widget.onViewRequest!(row);
      return;
    }
    final String? message =
        await showApplicationDecisionDialog(context, row.application);
    if (!mounted) return;
    if (message != null) {
      ref.invalidate(gradePendingRequestsProvider(_gradeKey));
      // Approved students join the Students table: refresh it too so no
      // manual reload is needed.
      ref.invalidate(gradeStudentsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      child: SingleChildScrollView(
        clipBehavior: Clip.antiAlias,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 1280,
            height: 800,
            child: Stack(
              children: <Widget>[
                const Positioned(
                  left: 370,
                  top: 24,
                  width: 540,
                  height: 80,
                  child: IgnorePointer(child: _BrandLockup()),
                ),
                Positioned(
                  left: 310,
                  top: 136,
                  width: 660,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFF979797),
                        width: 1,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (int i = 0; i < _grades.length; i++)
                          ...<Widget>[
                          if (i > 0) const SizedBox(width: 4),
                          _GradePill(
                            label: _grades[i].label,
                            active: _grades[i].key == _gradeKey,
                            accent: gradeAccent(_grades[i].key),
                            onTap: () => setState(
                              () => _gradeKey = _grades[i].key,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 472,
                  top: 190,
                  width: 336,
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _SectionTab(
                        label: 'Students',
                        active: true,
                        accent: _accent,
                        onTap: () =>
                            widget.onStudentsTab?.call(_gradeKey),
                      ),
                      const SizedBox(width: 4),
                      _SectionTab(
                        label: 'Subjects',
                        active: false,
                        accent: _accent,
                        onTap: () =>
                            widget.onSubjectsTab?.call(_gradeKey),
                      ),
                    ],
                  ),
                ),
                // # pending requests banner (416, 270, 448 x 76).
                Positioned(
                  left: 416,
                  top: 270,
                  width: 448,
                  height: 76,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: _accent, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Pending Requests',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
                _PendingRequestsTable(
                  gradeKey: _gradeKey,
                  accent: _accent,
                  onView: _openDecision,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: 'Tarek el araby ',
              style: AppTypography.homeBrandHeavy(fontSize: 48),
            ),
            TextSpan(
              text: 'Platform',
              style: AppTypography.homeBrandLight(fontSize: 48).copyWith(
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        maxLines: 1,
      ),
    );
  }
}

class _GradePill extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _GradePill({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 32,
      child: Material(
        color: active ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF374151),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SectionTab({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 32,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? accent : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 64,
              color: active ? accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending requests table (78, 420, 1120 x 390): 40 px sticky header +
/// scrollable 48 px rows with 88 x 32 View buttons.
class _PendingRequestsTable extends ConsumerWidget {
  final String gradeKey;
  final Color accent;
  final ValueChanged<PendingRequestRow> onView;

  const _PendingRequestsTable({
    required this.gradeKey,
    required this.accent,
    required this.onView,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PendingRequestRow>> rowsAsync =
        ref.watch(gradePendingRequestsProvider(gradeKey));
    return Positioned(
      left: 78,
      top: 420,
      width: 1120,
      height: 390,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: rowsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) => const Center(
              child: Text(
                'Could not load requests.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            data: (List<PendingRequestRow> rows) {
              return Column(
                children: <Widget>[
                  const _TableHeader(),
                  Container(height: 1, color: const Color(0xFFE5E7EB)),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text(
                              'No pending requests.',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: rows.length,
                            separatorBuilder:
                                (BuildContext context, int index) =>
                                    Container(
                              height: 1,
                              color: const Color(0xFFF3F4F6),
                            ),
                            itemBuilder:
                                (BuildContext context, int index) {
                              return _RequestRow(
                                number: index + 1,
                                row: rows[index],
                                accent: accent,
                                onView: () => onView(rows[index]),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const List<({String label, int flex})> _columns =
    <({String label, int flex})>[
  (label: 'No.', flex: 1),
  (label: 'Student Name', flex: 4),
  (label: 'Phone Number', flex: 3),
  (label: 'Device', flex: 3),
  (label: 'Request date', flex: 2),
  (label: 'Action', flex: 2),
];

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            for (final column in _columns)
              Expanded(
                flex: column.flex,
                child: Text(
                  column.label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final int number;
  final PendingRequestRow row;
  final Color accent;
  final VoidCallback onView;

  const _RequestRow({
    required this.number,
    required this.row,
    required this.accent,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: Text(
                '${number.toString().padLeft(2, '0')}.',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                row.application.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                row.application.phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                row.deviceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                row.requestDate,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 88,
                  height: 32,
                  child: ElevatedButton(
                    onPressed: onView,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'View',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
