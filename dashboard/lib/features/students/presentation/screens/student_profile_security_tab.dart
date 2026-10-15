import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/grade_students_provider.dart' show GradeStudent;
import '../providers/student_profile_security_provider.dart';
import '../screens/grade_students_screen.dart' show gradeAccent;
import '../widgets/grade_theme.dart';

/// Student Profile → Security tab content.
///
/// Renders inside the existing Student Profile shell: the shell owns the
/// brand header, the grade navigation, the hero and the sub-nav — this
/// widget is the dynamic body (830 wide) shown when the Security pill is
/// active.
///
/// - Security Status card: security score (only when a backend-supplied
///   value exists — V1 has none, so an honest empty state renders),
///   account status (from the `users` document), last security event
///   (from `security_events`). No device binding / counts / IDs here —
///   those belong to the Device tab.
/// - Password card: `password_last_changed_at` + Change Password overlay.
///   The Teacher-entered password is TEMPORARY; the backend sets
///   `force_password_change = true` so the student replaces it on next
///   login (existing flow, unchanged).
/// - Security Event Log opens as an overlay (never a new page). Event
///   cards render all information directly — there is NO View button.
///
/// Reads flow through [studentSecurityEventsProvider] /
/// [studentSecuritySummaryProvider]; writes go through the audited
/// [StudentSecurityController] callable. Widgets hold no permission logic
/// — [canResetStudentPasswordProvider] drives the password-action
/// availability (Doctor always; Admin only with delegated `password.reset`).
class StudentProfileSecurityTab extends ConsumerStatefulWidget {
  final GradeStudent student;
  final String gradeKey;

  const StudentProfileSecurityTab({
    super.key,
    required this.student,
    required this.gradeKey,
  });

  @override
  ConsumerState<StudentProfileSecurityTab> createState() =>
      _StudentProfileSecurityTabState();
}

class _StudentProfileSecurityTabState
    extends ConsumerState<StudentProfileSecurityTab> {
  String get _gradeKey => GradeTheme.fromKey(widget.gradeKey).gradeId;
  Color get _accent => gradeAccent(_gradeKey);

  bool _canReset(AsyncValue<bool> permission) {
    return permission.maybeWhen(data: (can) => can, orElse: () => false);
  }

  Future<void> _openEventLog() async {
    await showSecurityEventLogOverlay(
      context,
      accent: _accent,
      studentId: widget.student.id,
    );
  }

  Future<void> _openChangePassword() async {
    final bool canReset =
        _canReset(ref.read(canResetStudentPasswordProvider));
    await showChangeTemporaryPasswordOverlay(
      context,
      accent: _accent,
      student: widget.student,
      gradeLabel: GradeTheme.fromKey(_gradeKey).title,
      canReset: canReset,
    );
    if (!mounted) return;
    ref.invalidate(pendingStudentPasswordResetRequestProvider(
      widget.student.id,
    ));
    ref.invalidate(studentSecuritySummaryProvider(widget.student.id));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SecurityEvent>> eventsAsync =
        ref.watch(studentSecurityEventsProvider(widget.student.id));
    final AsyncValue<StudentSecuritySummary> summaryAsync =
        ref.watch(studentSecuritySummaryProvider(widget.student.id));
    final AsyncValue<bool> permissionAsync =
        ref.watch(canResetStudentPasswordProvider);
    final bool canReset = _canReset(permissionAsync);

    return SizedBox(
      width: 830,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Text(
            'Student account security & access control',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontVariations: <FontVariation>[FontVariation('wght', 400)],
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 18),
          summaryAsync.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => _SecurityErrorBlock(
              accent: _accent,
              message: 'Could not load security status.',
              onRetry: () {
                ref.invalidate(
                  studentSecuritySummaryProvider(widget.student.id),
                );
                ref.invalidate(
                  studentSecurityEventsProvider(widget.student.id),
                );
              },
            ),
            data: (summary) => eventsAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => _SecurityErrorBlock(
                accent: _accent,
                message: 'Could not load security events.',
                onRetry: () => ref.invalidate(
                  studentSecurityEventsProvider(widget.student.id),
                ),
              ),
              data: (events) => _SecurityBody(
                accent: _accent,
                summary: summary,
                events: events,
                canReset: canReset,
                permissionLoading: permissionAsync is AsyncLoading,
                onOpenEventLog: _openEventLog,
                onChangePassword: _openChangePassword,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityErrorBlock extends StatelessWidget {
  final Color accent;
  final String message;
  final VoidCallback onRetry;

  const _SecurityErrorBlock({
    required this.accent,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-card body: Security Status + Password (Figma node 58136:841).
class _SecurityBody extends StatelessWidget {
  final Color accent;
  final StudentSecuritySummary summary;
  final List<SecurityEvent> events;
  final bool canReset;
  final bool permissionLoading;
  final VoidCallback onOpenEventLog;
  final VoidCallback onChangePassword;

  const _SecurityBody({
    required this.accent,
    required this.summary,
    required this.events,
    required this.canReset,
    required this.permissionLoading,
    required this.onOpenEventLog,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    final SecurityEvent? last = events.isEmpty ? null : events.first;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 700;
        final Widget status = _SecurityStatusCard(
          accent: accent,
          summary: summary,
          lastEvent: last,
          onOpenEventLog: onOpenEventLog,
        );
        final Widget password = _PasswordCard(
          accent: accent,
          summary: summary,
          canReset: canReset,
          permissionLoading: permissionLoading,
          onChangePassword: onChangePassword,
        );
        if (narrow) {
          return Column(
            children: <Widget>[
              status,
              const SizedBox(height: 16),
              password,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: status),
            const SizedBox(width: 16),
            Expanded(child: password),
          ],
        );
      },
    );
  }
}

class _SecurityCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SecurityCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              fontVariations: <FontVariation>[FontVariation('wght', 600)],
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontVariations: <FontVariation>[FontVariation('wght', 400)],
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontVariations: const <FontVariation>[
                FontVariation('wght', 500)
              ],
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// Security Status card: score, account status, last event + log button.
///
/// Device binding / counts / IDs are intentionally absent — they belong
/// to the Device tab.
class _SecurityStatusCard extends StatelessWidget {
  final Color accent;
  final StudentSecuritySummary summary;
  final SecurityEvent? lastEvent;
  final VoidCallback onOpenEventLog;

  const _SecurityStatusCard({
    required this.accent,
    required this.summary,
    required this.lastEvent,
    required this.onOpenEventLog,
  });

  @override
  Widget build(BuildContext context) {
    final SecurityEvent? event = lastEvent;
    return _SecurityCard(
      title: 'Security Status',
      children: <Widget>[
        // No backend security score exists in V1 — render honestly.
        const _StatusRow(
          label: 'Security Score',
          value: 'Not available',
          valueColor: Color(0xFF6B7280),
        ),
        _StatusRow(
          label: 'Account Status',
          value: summary.accountStatus,
        ),
        if (event == null)
          const _StatusRow(
            label: 'Last Security Event',
            value: 'No security events recorded.',
            valueColor: Color(0xFF6B7280),
          )
        else
          _StatusRow(
            label: 'Last Security Event',
            value:
                '${event.eventType}\n${formatSecurityDateTime(event.createdAt)}',
          ),
        const SizedBox(height: 4),
        _AccentPillButton(
          accent: accent,
          label: 'Security Event Log',
          onPressed: onOpenEventLog,
        ),
      ],
    );
  }
}

class _PasswordCard extends StatelessWidget {
  final Color accent;
  final StudentSecuritySummary summary;
  final bool canReset;
  final bool permissionLoading;
  final VoidCallback onChangePassword;

  const _PasswordCard({
    required this.accent,
    required this.summary,
    required this.canReset,
    required this.permissionLoading,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = canReset && !permissionLoading;
    return _SecurityCard(
      title: 'Password',
      children: <Widget>[
        const Text(
          'Last changed',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            fontVariations: <FontVariation>[FontVariation('wght', 400)],
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatSecurityDateTime(summary.passwordLastChangedAt),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontVariations: <FontVariation>[FontVariation('wght', 500)],
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        _AccentPillButton(
          accent: accent,
          label: 'Change Password',
          onPressed: enabled ? onChangePassword : null,
        ),
        // Admin without the delegated `password.reset` grant sees the
        // restricted state; Doctor + granted Admin may reset directly
        // (phone/in-person request — no app-side request needed).
        if (!canReset && !permissionLoading) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'Password reset is available to the Teacher (Platform Owner) and to Admins granted password-reset permission.',
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
    );
  }
}

class _AccentPillButton extends StatelessWidget {
  final Color accent;
  final String label;
  final VoidCallback? onPressed;

  const _AccentPillButton({
    required this.accent,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, minHeight: 28),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD1D5DB),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          elevation: 0,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: const TextStyle(
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

// ---------------------------------------------------------------------------
// Security Event Log overlay
// ---------------------------------------------------------------------------

/// Security Event Log overlay (Figma: centered, white, radius 24, black
/// 25% barrier, 150 ms ease-out dissolve). Filters operate against the
/// live `security_events` query; event cards render all information
/// directly with NO View button.
Future<void> showSecurityEventLogOverlay(
  BuildContext context, {
  required Color accent,
  required String studentId,
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
              maxWidth: MediaQuery.sizeOf(context).width * 0.92,
            ),
            child: Container(
              width: 600,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: _EventLogBody(accent: accent, studentId: studentId),
            ),
          ),
        ),
      );
    },
  );
}

class _EventLogBody extends ConsumerStatefulWidget {
  final Color accent;
  final String studentId;

  const _EventLogBody({required this.accent, required this.studentId});

  @override
  ConsumerState<_EventLogBody> createState() => _EventLogBodyState();
}

class _EventLogBodyState extends ConsumerState<_EventLogBody> {
  String _eventType = 'All Events';
  SecuritySeverity? _severity;
  SecurityTimeFilter _time = SecurityTimeFilter.allTime;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SecurityEvent>> eventsAsync =
        ref.watch(studentSecurityEventsProvider(widget.studentId));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Security Event Log',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        fontVariations: <FontVariation>[
                          FontVariation('wght', 600)
                        ],
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Security events recorded for this student',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontVariations: <FontVariation>[
                          FontVariation('wght', 400)
                        ],
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
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
          const SizedBox(height: 20),
          eventsAsync.when(
            loading: () => const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'Could not load security events.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
            data: (events) {
              final List<String> types =
                  distinctSecurityEventTypes(events);
              final List<SecurityEvent> filtered = filterSecurityEvents(
                events: events,
                eventType: _eventType,
                severity: _severity,
                time: _time,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _EventLogFilters(
                    accent: widget.accent,
                    eventTypes: types,
                    eventType: _eventType,
                    severity: _severity,
                    time: _time,
                    onEventType: (v) => setState(() => _eventType = v),
                    onSeverity: (v) => setState(() => _severity = v),
                    onTime: (v) => setState(() => _time = v),
                  ),
                  const SizedBox(height: 20),
                  if (filtered.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No security events match these filters.',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < filtered.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 12),
                      _SecurityEventCard(event: filtered[i]),
                    ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _severityLabel(SecuritySeverity? severity) {
  switch (severity) {
    case SecuritySeverity.low:
      return 'Low';
    case SecuritySeverity.medium:
      return 'Medium';
    case SecuritySeverity.high:
      return 'High';
    case SecuritySeverity.critical:
      return 'Critical';
    case SecuritySeverity.unknown:
      return 'Unknown';
    case null:
      return 'All Severity';
  }
}

String _timeLabel(SecurityTimeFilter time) {
  switch (time) {
    case SecurityTimeFilter.allTime:
      return 'All Time';
    case SecurityTimeFilter.last24Hours:
      return 'Last 24 hours';
    case SecurityTimeFilter.last7Days:
      return 'Last 7 days';
    case SecurityTimeFilter.last30Days:
      return 'Last 30 days';
  }
}

class _EventLogFilters extends StatelessWidget {
  final Color accent;
  final List<String> eventTypes;
  final String eventType;
  final SecuritySeverity? severity;
  final SecurityTimeFilter time;
  final ValueChanged<String> onEventType;
  final ValueChanged<SecuritySeverity?> onSeverity;
  final ValueChanged<SecurityTimeFilter> onTime;

  const _EventLogFilters({
    required this.accent,
    required this.eventTypes,
    required this.eventType,
    required this.severity,
    required this.time,
    required this.onEventType,
    required this.onSeverity,
    required this.onTime,
  });

  @override
  Widget build(BuildContext context) {
    const List<SecuritySeverity?> severities = <SecuritySeverity?>[
      null,
      SecuritySeverity.low,
      SecuritySeverity.medium,
      SecuritySeverity.high,
      SecuritySeverity.critical,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _FilterDropdown<String>(
          label: 'Event Type',
          value: eventType,
          items: <String>['All Events', ...eventTypes],
          itemLabel: (v) => v,
          onChanged: onEventType,
        ),
        _FilterDropdown<SecuritySeverity?>(
          label: 'Severity',
          value: severity,
          items: severities,
          itemLabel: _severityLabel,
          onChanged: onSeverity,
        ),
        _FilterDropdown<SecurityTimeFilter>(
          label: 'Time',
          value: time,
          items: SecurityTimeFilter.values,
          itemLabel: _timeLabel,
          onChanged: onTime,
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<T>>[
              for (final T item in items)
                DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
            onChanged: (T? next) {
              // `null` is a valid value ("All Severity") when the type
              // argument itself is nullable (`SecuritySeverity?`): only
              // reject null when `T` cannot hold it.
              if (next == null && null is! T) return;
              onChanged(next as T);
            },
          ),
        ),
      ],
    );
  }
}

/// One self-contained security event card: type, severity, date/time,
/// context, event-scoped device info, and action taken. No View button.
class _SecurityEventCard extends StatelessWidget {
  final SecurityEvent event;

  const _SecurityEventCard({required this.event});

  /// Presentation-only severity styling. Severity color mapping is NOT a
  /// domain business rule — these are overlay-local visual tokens.
  static Color severityColor(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.critical:
      case SecuritySeverity.high:
        return const Color(0xFFDC2626);
      case SecuritySeverity.medium:
        return const Color(0xFFD97706);
      case SecuritySeverity.low:
        return const Color(0xFF2563EB);
      case SecuritySeverity.unknown:
        return const Color(0xFF6B7280);
    }
  }

  static Color severityBackground(SecuritySeverity severity) {
    switch (severity) {
      case SecuritySeverity.critical:
      case SecuritySeverity.high:
        return const Color(0xFFFEE2E2);
      case SecuritySeverity.medium:
        return const Color(0xFFFEF3C7);
      case SecuritySeverity.low:
        return const Color(0xFFDBEAFE);
      case SecuritySeverity.unknown:
        return const Color(0xFFF3F4F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = severityColor(event.severity);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  event.eventType,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontVariations: <FontVariation>[
                      FontVariation('wght', 600)
                    ],
                    color: Colors.black,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: severityBackground(event.severity),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  event.severityLabel.toUpperCase(),
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontVariations: const <FontVariation>[
                      FontVariation('wght', 700)
                    ],
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatSecurityDateTime(event.createdAt),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            event.contextSummary,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Device',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            event.deviceSummary,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Action Taken',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            event.actionTaken,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Change Password overlay (temporary password, Doctor + delegated Admin)
// ---------------------------------------------------------------------------

/// Change Password overlay (centered, white, radius 24, black 25%
/// barrier, 150 ms ease-out dissolve).
///
/// The authorized actor enters a TEMPORARY password twice; the existing
/// backend flow forces the student to replace it on next login
/// (`force_password_change = true`). Doctor always; Admin only with the
/// delegated `password.reset` grant — others see the restricted state.
/// No app-side "Forgot Password" request is needed: the overlay creates a
/// staff-side pending request when none exists, then approves it.
Future<void> showChangeTemporaryPasswordOverlay(
  BuildContext context, {
  required Color accent,
  required GradeStudent student,
  required String gradeLabel,
  required bool canReset,
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
              maxWidth: MediaQuery.sizeOf(context).width * 0.92,
            ),
            child: Container(
              width: 480,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                child: _ChangePasswordBody(
                  accent: accent,
                  student: student,
                  gradeLabel: gradeLabel,
                  canReset: canReset,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ChangePasswordBody extends ConsumerStatefulWidget {
  final Color accent;
  final GradeStudent student;
  final String gradeLabel;
  final bool canReset;

  const _ChangePasswordBody({
    required this.accent,
    required this.student,
    required this.gradeLabel,
    required this.canReset,
  });

  @override
  ConsumerState<_ChangePasswordBody> createState() =>
      _ChangePasswordBodyState();
}

class _ChangePasswordBodyState extends ConsumerState<_ChangePasswordBody> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  bool _obscureFirst = true;
  bool _obscureSecond = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String first = _first.text;
    final String second = _second.text;
    // UI-side checks only: empty + confirmation mismatch. Strength and
    // policy validation remain authoritative in the backend.
    if (first.isEmpty || second.isEmpty) {
      setState(() => _error = 'Please fill in both password fields.');
      return;
    }
    if (first != second) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Direct staff-initiated reset: reuse a pending request when one
      // exists, otherwise create a staff-side pending request first
      // (Doctor / delegated Admin may create per firestore.rules). The
      // student never needs to submit "Forgot Password" from the app.
      late final String requestId;
      try {
        requestId = await ensurePendingPasswordResetRequestId(
          ref.read(firebaseFirestoreProvider),
          studentId: widget.student.id,
          phoneNumber: widget.student.phone,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = 'Could not prepare the password reset request. Try again.';
        });
        return;
      }
      if (!mounted) return;
      await ref
          .read(studentSecurityControllerProvider)
          .approveTemporaryPassword(
            requestId: requestId,
            temporaryPassword: first,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Temporary password saved. The student will be '
              'required to change it on the next login.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final String text = e.toString();
      const String prefix = 'SecurityFailure: ';
      setState(() {
        _saving = false;
        _error = text.startsWith(prefix)
            ? text.substring(prefix.length)
            : 'Could not update the password. Try again.';
      });
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Change Password',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontVariations: <FontVariation>[
                    FontVariation('wght', 600)
                  ],
                  color: Colors.black,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
        const SizedBox(height: 16),
        _StudentIdentitySummary(
          student: widget.student,
          gradeLabel: widget.gradeLabel,
        ),
        const SizedBox(height: 20),
        if (!widget.canReset) ...<Widget>[
          const Text(
            'Password reset is available to the Teacher (Platform Owner) '
            'and to Admins granted password-reset permission.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
          ),
        ] else ...<Widget>[
          _TemporaryPasswordField(
            controller: _first,
            label: 'Enter Temporary Password',
            obscure: _obscureFirst,
            enabled: !_saving,
            onToggle: () =>
                setState(() => _obscureFirst = !_obscureFirst),
          ),
          const SizedBox(height: 12),
          _TemporaryPasswordField(
            controller: _second,
            label: 'Re-Enter Temporary Password',
            obscure: _obscureSecond,
            enabled: !_saving,
            onToggle: () =>
                setState(() => _obscureSecond = !_obscureSecond),
          ),
          const SizedBox(height: 12),
          const Text(
            'The student will be required to change this password on the next login (minimum 6 characters)',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        fontVariations: <FontVariation>[
                          FontVariation('wght', 500)
                        ],
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Student identity summary reusing the passed profile student (name,
/// phone, grade). No header duplication — the shell owns the hero.
class _StudentIdentitySummary extends StatelessWidget {
  final GradeStudent student;
  final String gradeLabel;

  const _StudentIdentitySummary({
    required this.student,
    required this.gradeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            student.name,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontVariations: <FontVariation>[FontVariation('wght', 600)],
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${student.phone ?? '—'} • $gradeLabel • ${student.typeLabel}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemporaryPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool enabled;
  final VoidCallback onToggle;

  const _TemporaryPasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}
