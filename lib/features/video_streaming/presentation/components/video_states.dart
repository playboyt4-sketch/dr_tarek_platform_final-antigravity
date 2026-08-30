import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

class VideoLoadingState extends StatelessWidget {
  const VideoLoadingState({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF00c896)),
      ),
    );
  }
}

class VideoBufferingState extends StatelessWidget {
  const VideoBufferingState({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white70),
    );
  }
}

class VideoErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const VideoErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00c896),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoResumePrompt extends StatelessWidget {
  final VideoPlaybackController controller;

  const VideoResumePrompt({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120, // above bottom bar
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'استئناف من حيث توقفت؟',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () {
                controller.startOver();
              },
              child: const Text('من البداية', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00c896),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                controller.continueWatching();
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// FINAL_DECISIONS §11/§12: full-screen upgrade wall. Shown either when
/// the Public Free per-lecture minute cap is reached (§11) or when a Center
/// Free student tries to start a DIFFERENT video inside their rolling
/// 24-hour window (§12 — [controller.dailyWindowBlocked]). Purely
/// presentational; both gates are computed/enforced server-side.
class VideoUpgradePrompt extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onUpgrade;

  const VideoUpgradePrompt({
    required this.controller,
    required this.onUpgrade,
    super.key,
  });

  String? _remainingWindowText() {
    final expiresAt = controller.dailyWindowExpiresAt;
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return null;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) {
      return 'لسه فاضلك $hours ساعة و$minutes دقيقة على فيديوك الحالي.';
    }
    return 'لسه فاضلك $minutes دقيقة على فيديوك الحالي.';
  }

  @override
  Widget build(BuildContext context) {
    final windowLine =
        controller.dailyWindowBlocked ? _remainingWindowText() : null;
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              controller.dailyWindowBlocked
                  ? 'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة.'
                  : controller.resource?.isPublicFreePreview == true
                      ? 'انتهت الدقائق المجانية المسموح بها لهذه المحاضرة.'
                      : 'هذا المحتوى متاح لمشتركي الباقة المدفوعة.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            // §12 nicety: remaining time on the currently-open video.
            if (windowLine != null) ...[
              const SizedBox(height: 8),
              Text(
                windowLine,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00c896),
                foregroundColor: Colors.white,
              ),
              onPressed: onUpgrade,
              child: const Text('الترقية إلى Pro'),
            ),
          ],
        ),
      ),
    );
  }
}
