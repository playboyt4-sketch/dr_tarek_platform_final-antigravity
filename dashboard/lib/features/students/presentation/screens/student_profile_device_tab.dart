import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart' show GradeStudent;
import '../providers/student_profile_devices_provider.dart';
import '../screens/grade_students_screen.dart' show gradeAccent;
import '../widgets/grade_theme.dart';

/// Student Profile → Device tab content.
///
/// Renders inside the existing Student Profile shell: the shell owns the
/// brand header, the grade navigation, and the sub-nav — this widget is
/// the main content column (830 wide) shown when the Device pill is
/// active.
///
/// - The table lists one row per registered Subject (the same registrations
///   as the Subjects tab) with the Subject-scoped plan and the
///   Subject-scoped device usage (`active/allowance` — each Subject keeps
///   its own allowance; plans never leak across Subjects).
/// - `Device Details` opens the centered overlay for THAT Subject only.
/// - `Reset All Authorizations` revokes every active Subject-device
///   authorization of the student (account, subscriptions, and plans are
///   untouched).
///
/// Reads flow through [studentProfileDevicesProvider]; writes go through
/// the audited [StudentDeviceController] callables. Widgets hold no
/// permission logic — [canManageStudentDevicesProvider] drives the
/// manage-action availability.
class StudentProfileDeviceTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfileDeviceTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfileDeviceTab> createState() =>
      _StudentProfileDeviceTabState();
}

class _StudentProfileDeviceTabState
    extends ConsumerState<StudentProfileDeviceTab> {
  String get _gradeKey => GradeTheme.fromKey(widget.gradeKey).gradeId;
  Color get _accent => gradeAccent(_gradeKey);

  bool _canManage(AsyncValue<bool> permission) {
    return permission.maybeWhen(data: (can) => can, orElse: () => false);
  }

  Future<void> _openDetails(StudentSubjectDeviceRow row, bool canManage) async {
    await showStudentDeviceDetailsOverlay(
      context,
      accent: _accent,
      studentId: widget.student.id,
      subjectId: row.subjectId,
      canManage: canManage,
      onUnbind: (device) => _unbind(row, device),
    );
  }

  Future<void> _unbind(
    StudentSubjectDeviceRow row,
    SubjectAuthorizedDevice device,
  ) async {
    if (device.deviceId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device identity is missing; cannot unbind.'),
        ),
      );
      return;
    }
    try {
      await ref.read(studentDeviceControllerProvider).unbindSubjectDevice(
            studentId: widget.student.id,
            subjectId: row.subjectId,
            deviceId: device.deviceId,
          );
      ref.invalidate(studentDeviceAuthorizationsProvider(widget.student.id));
      ref.invalidate(studentDeviceRecordsProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Device unbound from "${row.title}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
      rethrow;
    }
  }

  Future<void> _confirmResetAll() async {
    final bool? confirmed = await showResetAuthorizationsDialog(
      context,
      accent: _accent,
      studentName: widget.student.name,
    );
    if (confirmed != true || !mounted) return;
    try {
      final int revoked = await ref
          .read(studentDeviceControllerProvider)
          .resetStudentDevices(studentId: widget.student.id);
      ref.invalidate(studentDeviceAuthorizationsProvider(widget.student.id));
      ref.invalidate(studentDeviceRecordsProvider(widget.student.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Authorizations reset ($revoked devices).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StudentSubjectDeviceRow>> rowsAsync =
        ref.watch(studentProfileDevicesProvider(widget.student.id));
    final AsyncValue<bool> permissionAsync =
        ref.watch(canManageStudentDevicesProvider);
    final bool canManage = _canManage(permissionAsync);

    return SizedBox(
      width: 830,
      child: rowsAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Could not load student devices.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(
                    studentProfileDevicesProvider(widget.student.id),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) => _DeviceTableBlock(
          state: this,
          rows: rows,
          canManage: canManage,
        ),
      ),
    );
  }

  static String _failureMessage(Object error) {
    final String text = error.toString();
    const String prefix = 'DeviceFailure: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
    return 'Could not complete the device action. Try again.';
  }
}

/// Table + reset block: the table leaves room below it for the global
/// reset action, mirroring the Subjects tab rhythm.
class _DeviceTableBlock extends StatelessWidget {
  final _StudentProfileDeviceTabState state;
  final List<StudentSubjectDeviceRow> rows;
  final bool canManage;

  const _DeviceTableBlock({
    required this.state,
    required this.rows,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 830,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _DeviceTable(state: state, rows: rows, canManage: canManage),
          const SizedBox(height: 24),
          _ResetAuthorizationsButton(
            accent: state._accent,
            enabled: canManage,
            onTap: state._confirmResetAll,
          ),
          if (!canManage) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'You do not have permission to manage devices.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontVariations: <FontVariation>[FontVariation('wght', 400)],
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Device table (Figma Dev Mode: 830 wide, 1 px #E5E7EB border, radius
/// 16): header 830 with 8 px padding — No. 56 | Subjects 216 | Grade 146
/// | Plan 116 | Device 116 | Action 156 (= 806, inside the 808 content
/// width) — 1 px divider, then dynamic data rows with 10 px padding.
/// The Grade column shows each subject's OWN catalog grade (which may
/// differ from the student's current grade). Row numbers are
/// presentation-only.
class _DeviceTable extends StatelessWidget {
  final _StudentProfileDeviceTabState state;
  final List<StudentSubjectDeviceRow> rows;
  final bool canManage;

  const _DeviceTable({
    required this.state,
    required this.rows,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 830,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x3F000000),
            blurRadius: 4,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          const _DeviceHeaderRow(),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No subjects registered for this student yet.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++)
              _DeviceDataRow(
                state: state,
                index: i,
                row: rows[i],
                canManage: canManage,
              ),
        ],
      ),
    );
  }
}

class _DeviceHeaderRow extends StatelessWidget {
  const _DeviceHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: _HeaderLabel('No.'),
          ),
          SizedBox(width: 216, child: _HeaderLabel('Subjects')),
          SizedBox(width: 146, child: _HeaderLabel('Grade')),
          SizedBox(width: 116, child: _HeaderLabel('Plan')),
          SizedBox(width: 116, child: _HeaderLabel('Device')),
          SizedBox(width: 156, child: _HeaderLabel('Action')),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;

  const _HeaderLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
        color: Color(0xFF6B7280),
      ),
    );
  }
}

class _DeviceDataRow extends StatelessWidget {
  final _StudentProfileDeviceTabState state;
  final int index;
  final StudentSubjectDeviceRow row;
  final bool canManage;

  const _DeviceDataRow({
    required this.state,
    required this.index,
    required this.row,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    final String number = (index + 1).toString().padLeft(2, '0');
    const TextStyle cellStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w400,
      fontVariations: <FontVariation>[FontVariation('wght', 400)],
      color: Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              '$number.',
              textAlign: TextAlign.center,
              style: cellStyle,
            ),
          ),
          SizedBox(
            width: 216,
            child: Text(
              row.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cellStyle,
            ),
          ),
          SizedBox(
            width: 146,
            child: Text(
              GradeTheme.subjectGradeLabel(row.gradeKey),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cellStyle,
            ),
          ),
          SizedBox(
            width: 116,
            child: Text(
              row.planLabel.isEmpty ? '—' : row.planLabel,
              textAlign: TextAlign.center,
              style: cellStyle,
            ),
          ),
          SizedBox(
            width: 116,
            child: Text(
              row.usageLabel,
              textAlign: TextAlign.center,
              style: cellStyle,
            ),
          ),
          SizedBox(
            width: 156,
            child: Center(
              child: SizedBox(
                width: 96,
                height: 28,
                child: ElevatedButton(
                  onPressed: () => state._openDetails(row, canManage),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state._accent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Device Details',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Global reset action below the table (Figma: ~160 x 28, amber pill,
/// white 12 px label). Width flexes past 160 so the full
/// `Reset All Authorizations` label never clips; the exact label is
/// contractual — never rename it.
class _ResetAuthorizationsButton extends StatelessWidget {
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _ResetAuthorizationsButton({
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, minHeight: 28),
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD1D5DB),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          elevation: 0,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Reset All Authorizations',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// Device Details overlay (Figma: 600 wide, white, radius 24, centered,
/// outside tap dismisses, black 25% barrier, 150 ms ease-out dissolve).
/// Renders the selected Subject ONLY, resolved live from
/// [studentProfileDevicesProvider] by [subjectId] so unbinds refresh
/// in place. One overlay at a time — never stacked.
Future<void> showStudentDeviceDetailsOverlay(
  BuildContext context, {
  required Color accent,
  required String studentId,
  required String subjectId,
  required bool canManage,
  required Future<void> Function(SubjectAuthorizedDevice device) onUnbind,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierColor: const Color(0x40000000),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: Container(
              width: 600,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                child: _DeviceDetailsBody(
                  accent: accent,
                  studentId: studentId,
                  subjectId: subjectId,
                  canManage: canManage,
                  onUnbind: onUnbind,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Live body of the Device Details overlay for one Subject.
class _DeviceDetailsBody extends ConsumerStatefulWidget {
  final Color accent;
  final String studentId;
  final String subjectId;
  final bool canManage;
  final Future<void> Function(SubjectAuthorizedDevice device) onUnbind;

  const _DeviceDetailsBody({
    required this.accent,
    required this.studentId,
    required this.subjectId,
    required this.canManage,
    required this.onUnbind,
  });

  @override
  ConsumerState<_DeviceDetailsBody> createState() =>
      _DeviceDetailsBodyState();
}

class _DeviceDetailsBodyState extends ConsumerState<_DeviceDetailsBody> {
  final Set<String> _unbinding = <String>{};

  Future<void> _unbind(SubjectAuthorizedDevice device) async {
    if (_unbinding.contains(device.authorizationId)) return;
    setState(() => _unbinding.add(device.authorizationId));
    try {
      await widget.onUnbind(device);
    } catch (_) {
      // Failure messaging is owned by the caller (SnackBar); the busy
      // flag is still cleared below.
    } finally {
      if (mounted) {
        setState(() => _unbinding.remove(device.authorizationId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<StudentSubjectDeviceRow>> rowsAsync =
        ref.watch(studentProfileDevicesProvider(widget.studentId));
    final List<StudentSubjectDeviceRow> rows =
        rowsAsync.maybeWhen(data: (rows) => rows, orElse: () => const <StudentSubjectDeviceRow>[]);
    final int index =
        rows.indexWhere((row) => row.subjectId == widget.subjectId);
    final StudentSubjectDeviceRow? row = index == -1 ? null : rows[index];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Device Details',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 32,
                  fontWeight: FontWeight.w400,
                  fontVariations: <FontVariation>[FontVariation('wght', 400)],
                  color: Colors.black,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                icon: const Icon(Icons.close, size: 20),
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (row == null)
          const Text(
            'Subject is no longer available.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          )
        else ...<Widget>[
          const Row(
            children: <Widget>[
              SizedBox(width: 240, child: _OverlayHeaderLabel('Subject')),
              SizedBox(width: 140, child: _OverlayHeaderLabel('Plan')),
              SizedBox(width: 144, child: _OverlayHeaderLabel('Devices')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox(
                width: 240,
                child: Text(
                  row.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400)
                    ],
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  row.planLabel.isEmpty ? '—' : row.planLabel,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400)
                    ],
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(
                width: 144,
                child: Text(
                  row.usageLabel,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 400)
                    ],
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (row.devices.isEmpty)
            const Text(
              'No authorized devices for this subject yet.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            )
          else
            for (int i = 0; i < row.devices.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 20),
              _AuthorizedDeviceBlock(
                index: i,
                device: row.devices[i],
                accent: widget.accent,
                canManage: widget.canManage,
                busy: _unbinding.contains(row.devices[i].authorizationId),
                onUnbind: () => _unbind(row.devices[i]),
              ),
            ],
        ],
      ],
    );
  }
}

class _OverlayHeaderLabel extends StatelessWidget {
  final String text;

  const _OverlayHeaderLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w400,
        fontVariations: <FontVariation>[FontVariation('wght', 400)],
        color: Colors.black,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One authorized device entry: title, name, OS / app line, last access,
/// status, and the Subject-scoped Unbind action.
class _AuthorizedDeviceBlock extends StatelessWidget {
  final int index;
  final SubjectAuthorizedDevice device;
  final Color accent;
  final bool canManage;
  final bool busy;
  final VoidCallback onUnbind;

  const _AuthorizedDeviceBlock({
    required this.index,
    required this.device,
    required this.accent,
    required this.canManage,
    required this.busy,
    required this.onUnbind,
  });

  @override
  Widget build(BuildContext context) {
    final String number = (index + 1).toString().padLeft(2, '0');
    const TextStyle metaStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      fontVariations: <FontVariation>[FontVariation('wght', 400)],
      color: Colors.black,
    );
    final bool enabled = canManage && !busy && device.deviceId.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Device $number',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(device.deviceName, style: metaStyle),
        const SizedBox(height: 4),
        Text(formatDeviceOsLine(device), style: metaStyle),
        const SizedBox(height: 4),
        Text('Last access: ${formatDeviceDateTime(device.lastAccess)}',
            style: metaStyle),
        const SizedBox(height: 4),
        Text('Status: ${device.statusLabel}', style: metaStyle),
        const SizedBox(height: 12),
        SizedBox(
          width: 160,
          height: 32,
          child: ElevatedButton(
            onPressed: enabled ? onUnbind : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
              elevation: 0,
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Unbind',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      fontVariations: <FontVariation>[
                        FontVariation('wght', 400),
                      ],
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Reset confirmation: revokes EVERY active Subject-device authorization
/// of this student (all Subjects). The account, subscriptions, and plans
/// stay unchanged; the student reconnects on next Subject access without
/// signing in again. Figma prototype behavior: centered, outside tap
/// dismisses, black 25% barrier, 150 ms ease-out dissolve.
Future<bool?> showResetAuthorizationsDialog(
  BuildContext context, {
  required Color accent,
  required String studentName,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierColor: const Color(0x40000000),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
    ) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Reset All Authorizations',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Revoke all device authorizations for "$studentName" '
                  'across every subject? The account, subscriptions, and '
                  'plans stay unchanged.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: accent, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pop(true),
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
                          'Reset All',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
