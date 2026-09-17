import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Figma overlay shells for the Subject Details page.
///
/// - Add Lecture → centered overlay, black 25% backdrop, Dissolve
///   (fade) 150 ms Ease Out, closes on outside tap.
/// - Edit Lecture → centered overlay, black 25% backdrop, Move In from
///   the right 150 ms Ease Out, closes on outside tap.
///
/// This task preserves the opening/navigation behavior only — the
/// internal Add/Edit Lecture form designs land in a follow-up task, so
/// both shells render a placeholder body under the approved chrome.

/// Width of the trailing close-control slot in [_showDetailsOverlay].
///
/// The header title must stay mathematically centered as one group, so the
/// leading side mirrors this trailing 48px Material slot instead of nudging
/// the title with padding/offsets (same convention as the subject header
/// card's full-bleed centered title). Pure symmetric flex — no hardcoded
/// visual offsets, fully constraint-based on every viewport.
const double _kCloseSlotWidth = 48;

Future<T?> _showDetailsOverlay<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required RouteTransitionsBuilder transition,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          // Transition is applied by [transitionBuilder]; the page itself
          // is a static centered card.
          return Center(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 520,
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 30,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Leading slot mirrors the trailing close control so the
                        // title stays centered as one group (see [_kCloseSlotWidth]).
                        const SizedBox(width: _kCloseSlotWidth),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.actionDesc(fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.pillFill,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
    transitionBuilder: transition,
  );
}

/// Add Lecture overlay — Dissolve (fade) 150 ms Ease Out.
Future<void> showAddLectureOverlay(
  BuildContext context, {
  required String subjectTitle,
}) {
  return _showDetailsOverlay<void>(
    context: context,
    title: 'Add Lecture',
    subtitle: '$subjectTitle — the lecture form lands in the next step.',
    transition:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );
          return FadeTransition(opacity: curved, child: child);
        },
  ).then((_) {});
}

/// Edit Lecture overlay — Move In from the right 150 ms Ease Out.
Future<void> showEditLectureOverlay(
  BuildContext context, {
  required String lectureTitle,
}) {
  return _showDetailsOverlay<void>(
    context: context,
    title: 'Edit Lecture',
    subtitle: '$lectureTitle — the edit form lands in the next step.',
    transition:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
  ).then((_) {});
}
