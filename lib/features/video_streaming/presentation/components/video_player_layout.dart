import 'package:flutter/material.dart';

import '../controllers/video_playback_controller.dart';
import 'video_overlay_controls.dart';
import 'video_surface.dart';

class VideoPlayerLayout extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;
  final VoidCallback onToggleControls;

  /// FINAL_DECISIONS §11: opens the upgrade flow from the preview wall.
  final VoidCallback? onUpgradeTap;

  /// Saves a bookmark at the current playback position (null hides the action).
  final VoidCallback? onBookmarkTap;

  /// Section-aware toolbar label (Lectures / Revisions / Finals / Online).
  final String sectionButtonLabel;

  const VideoPlayerLayout({
    required this.controller,
    required this.onBack,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    required this.onToggleControls,
    this.onUpgradeTap,
    this.onBookmarkTap,
    this.sectionButtonLabel = 'Lectures',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Reference `docs/video player .html`: `.ui-layer { position: absolute;
    // inset: 0 }` over a full-bleed video. The body fills 100% of the route
    // in every orientation: no 16:9 letterbox stage, no max-width box, no
    // orientation nudge. Notch/system-bar protection lives in the overlay
    // bars themselves (header/bottom padding), never by shrinking the video.
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoSurface(controller: controller),

          // Watermark: stable identity handle from the Subject-scoped
          // controller (never read from FirebaseAuth here — Presentation
          // must not touch the Auth SDK directly, and the layout has to
          // build with no Firebase app, e.g. in widget tests).
          Positioned(
            right: 16,
            bottom: 42,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      controller.userId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Skip Intro
          if (controller.canSkipIntro && !controller.locked)
            Positioned(
              right: 16,
              bottom: 72,
              child: FilledButton.tonalIcon(
                onPressed: controller.skipIntro,
                icon: const Icon(Icons.fast_forward, size: 18),
                label: const Text('تخطي المقدمة'),
              ),
            ),

          VideoOverlayControls(
            controller: controller,
            onBack: onBack,
            onLecturesTap: onLecturesTap,
            onPdfTap: onPdfTap,
            onQualityTap: onQualityTap,
            onNextTap: onNextTap,
            onToggleControls: onToggleControls,
            onUpgradeTap: onUpgradeTap,
            onBookmarkTap: onBookmarkTap,
            sectionButtonLabel: sectionButtonLabel,
          ),
        ],
      ),
    );
  }
}
