import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';
import '../../domain/entities/playback_entities.dart';
import 'video_bottom_action_bar.dart';
import 'video_center_controls.dart';
import 'video_header.dart';
import 'video_side_sliders.dart';
import 'video_states.dart';

class VideoOverlayControls extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;
  final VoidCallback onToggleControls;

  /// Saves a bookmark at the current position (null disables the button).
  final VoidCallback? onBookmarkTap;

  /// FINAL_DECISIONS §11: opens the membership/plans flow when the Public
  /// Free preview wall is shown.
  final VoidCallback? onUpgradeTap;

  /// Section-aware toolbar label (Lectures / Revisions / Finals / Online).
  final String sectionButtonLabel;

  const VideoOverlayControls({
    required this.controller,
    required this.onBack,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    required this.onToggleControls,
    this.onBookmarkTap,
    this.onUpgradeTap,
    this.sectionButtonLabel = 'Lectures',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Gesture detector for showing/hiding controls
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (!controller.locked) {
              onToggleControls();
            }
          },
          child: AnimatedOpacity(
            opacity: controller.controlsVisible && !controller.locked ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: _buildGradient(),
          ),
        ),

        // Actual Controls: a single Column in one layout pass — top bar,
        // middle band (sliders + center controls), bottom bar. The middle
        // band takes whatever vertical space REMAINS between the bars, so
        // side sliders and center buttons can never overlap the top or
        // bottom bars on any viewport (no fixed pixel heights).
        if (controller.controlsVisible && !controller.locked)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header (top bar)
              VideoHeader(controller: controller, onBack: onBack),

              // Middle band: volume slider | center controls | brightness.
              // Physical LTR order pinned (volume LEFT, brightness RIGHT)
              // because the app RTL locale would otherwise mirror the Row.
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 64,
                        child: VideoEdgeSlider.volume(
                          controller: controller,
                        ),
                      ),
                      Expanded(
                        child: VideoCenterControls(controller: controller),
                      ),
                      SizedBox(
                        width: 64,
                        child: VideoEdgeSlider.brightness(
                          controller: controller,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Action Bar
              VideoBottomActionBar(
                controller: controller,
                onLecturesTap: onLecturesTap,
                onPdfTap: onPdfTap,
                onQualityTap: onQualityTap,
                onNextTap: onNextTap,
                onBookmarkTap: onBookmarkTap,
                sectionButtonLabel: sectionButtonLabel,
              ),
            ],
          ),

        // Lock control removed per design (reference player has no lock).
        // States (Loading, Error, Resume)
        if (controller.playbackStatus == PlayerPlaybackStatus.loading)
          const Positioned.fill(child: VideoLoadingState()),
        if (controller.playbackStatus == PlayerPlaybackStatus.buffering)
          const Positioned.fill(child: VideoBufferingState()),
        if (controller.playbackStatus == PlayerPlaybackStatus.error)
          Positioned.fill(
            child: VideoErrorState(
              message: controller.errorMessage ?? 'Video playback failed.',
              onRetry: controller.retry,
              onBack: onBack,
            ),
          ),
        if (controller.showResumePrompt && controller.resumeRecord != null)
          VideoResumePrompt(controller: controller),
        if (controller.showUpgradePrompt)
          VideoUpgradePrompt(
            controller: controller,
            onUpgrade: onUpgradeTap ?? () {},
            onBack: onBack,
          ),
      ],
    );
  }

  /// Scrim matching `docs/video player .html`:
  /// `linear-gradient(180deg, rgba(0,0,0,0.6) 0%, transparent 40%, rgba(0,0,0,0.8) 100%)`.
  Widget _buildGradient() {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4, 1.0],
            colors: [
              Color.fromRGBO(0, 0, 0, 0.6),
              Colors.transparent,
              Color.fromRGBO(0, 0, 0, 0.8),
            ],
          ),
        ),
      ),
    );
  }
}
