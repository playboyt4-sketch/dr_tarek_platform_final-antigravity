import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../lecture/presentation/screens/pdf_viewer_screen.dart';
import '../../../membership/presentation/widgets/center_phone_actions.dart';
import '../../../video_streaming/data/services/video_download_service.dart';
import '../../../video_streaming/presentation/components/video_states.dart';
import '../../domain/entities/subject_learning_entities.dart';

/// Displays an upgrade sheet for Free / ineligible plans when the student taps
/// the download button on a lecture card or inside the video player.
Future<void> showDownloadUpgradeSheet(
  BuildContext context, {
  required String title,
  String? currentPlanLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'تحميل المحاضرات متاح لـ Pro و Max',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'باقتك الحالية (${currentPlanLabel ?? 'FREE'}) لا تشمل تحميل الفيديو أوفلاين. للترقية إلى Pro أو Max وتفعيل التحميل فوراً تواصل معنا:',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                const CenterPhoneActions(phoneNumber: kGuestWallContact),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Backwards-compatible wrapper over [VideoDownloadController] helpers.
class LectureDownloadService {
  static Future<bool> isLectureDownloaded(String lectureId) async => false;

  static Future<String?> getDownloadedResourceId(String lectureId) async => null;

  static Future<void> markLectureDownloaded(
    String lectureId,
    String resourceId,
  ) async {}

  static Future<void> removeLectureDownloaded(String lectureId) async {}
}

/// Interactive download button for lecture card on subject navigation page.
/// Synchronized in real time with the in-player download button via
/// [videoDownloadControllerProvider].
class LectureDownloadButton extends ConsumerStatefulWidget {
  final LectureSummary lecture;
  final String subjectId;
  final VoidCallback? onPlayOffline;

  const LectureDownloadButton({
    super.key,
    required this.lecture,
    required this.subjectId,
    this.onPlayOffline,
  });

  @override
  ConsumerState<LectureDownloadButton> createState() =>
      _LectureDownloadButtonState();
}

class _LectureDownloadButtonState extends ConsumerState<LectureDownloadButton> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(videoDownloadControllerProvider.notifier).syncLectureStatus(
              subjectId: widget.subjectId,
              lectureId: widget.lecture.id,
            ),
      );
    });
  }

  bool _isChecking = false;

  Future<void> _startDownload() async {
    if (_isChecking) return;
    var userId = ref.read(authProvider).asData?.value?.id;
    if (userId == null || userId.isEmpty) {
      try {
        userId = (await ref.read(authProvider.future))?.id;
      } catch (_) {}
    }
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل الدخول أولاً.')),
      );
      return;
    }

    _isChecking = true;
    try {
      final messenger = ScaffoldMessenger.of(context);
      final outcome = await ref
          .read(videoDownloadControllerProvider.notifier)
          .downloadLecture(
            userId: userId,
            subjectId: widget.subjectId,
            lecture: widget.lecture,
          );
      if (!mounted) return;
      if (outcome.requiresUpgrade) {
        await showDownloadUpgradeSheet(
          context,
          title: widget.lecture.title,
          currentPlanLabel: outcome.currentPlanLabel,
        );
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(outcome.message)));
    } finally {
      _isChecking = false;
    }
  }

  void _showDownloadedOptions(LectureDownloadState downloadState) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF10B981),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.lecture.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'المحاضرة محملة ومحفوظة بأمان داخل التطبيق للمشاهدة بدون إنترنت.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: Icon(
                    downloadState.isVideo
                        ? Icons.play_circle_fill_rounded
                        : Icons.menu_book,
                  ),
                  label: Text(
                    downloadState.isVideo
                        ? 'تشغيل الفيديو بدون إنترنت'
                        : 'فتح المحاضرة بدون إنترنت',
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (downloadState.isVideo) {
                      widget.onPlayOffline?.call();
                    } else if (downloadState.resourceId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            resourceId: downloadState.resourceId!,
                            title: widget.lecture.title,
                            subjectId: widget.subjectId,
                            lectureId: widget.lecture.id,
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف من التنزيلات'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref
                        .read(videoDownloadControllerProvider.notifier)
                        .deleteDownloadedLecture(
                          subjectId: widget.subjectId,
                          lectureId: widget.lecture.id,
                        );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حذف المحاضرة من التنزيلات.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(
          videoDownloadControllerProvider.select((map) => map[widget.lecture.id]),
        ) ??
        const LectureDownloadState();

    if (downloadState.isDownloading) {
      final clamped = downloadState.progress.clamp(0.01, 1.0);
      final percentage = (clamped * 100).round().clamp(1, 100);
      return Tooltip(
        message: 'جارٍ التحميل $percentage%',
        child: SizedBox(
          width: context.rs(32),
          height: context.rs(32),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: clamped,
                strokeWidth: 2.6,
                backgroundColor: Colors.black.withValues(alpha: 0.12),
                color: const Color(0xFF1D4ED8),
              ),
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: context.rsFont(8.5),
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (downloadState.isDownloaded) {
      return IconButton(
        icon: Icon(
          Icons.check_circle,
          size: context.rs(23),
          color: const Color(0xFF10B981),
        ),
        tooltip: 'تم التحميل (اضغط للخيارات)',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () => _showDownloadedOptions(downloadState),
      );
    }

    return IconButton(
      icon: Icon(
        Icons.file_download_outlined,
        size: context.rs(23),
        color: Colors.black,
      ),
      tooltip: 'تحميل للمذاكرة بدون إنترنت',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: _startDownload,
    );
  }
}
