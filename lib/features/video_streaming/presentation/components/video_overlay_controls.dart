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

  const VideoOverlayControls({
    required this.controller,
    required this.onBack,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    required this.onToggleControls,
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
        
        // Actual Controls
        if (controller.controlsVisible && !controller.locked) ...[
          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: VideoHeader(
              controller: controller,
              onBack: onBack,
            ),
          ),
          
          // Side Sliders (Volume / Brightness)
          const Positioned.fill(
            child: VideoSideSliders(),
          ),
          
          // Center Big Controls
          Positioned.fill(
            child: VideoCenterControls(controller: controller),
          ),
          
          // Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoBottomActionBar(
              controller: controller,
              onLecturesTap: onLecturesTap,
              onPdfTap: onPdfTap,
              onQualityTap: onQualityTap,
              onNextTap: onNextTap,
            ),
          ),
        ],

        // Lock Toggle Button (always visible if locked, or if controls visible)
        if (controller.locked || controller.controlsVisible)
          Positioned(
            top: 16,
            left: 16, // RTL adjusted if needed, usually lock is on corner
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: controller.toggleLock,
              icon: Icon(
                controller.locked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
              ),
            ),
          ),
          
        // States (Loading, Error, Resume)
        if (controller.playbackStatus == PlayerPlaybackStatus.loading)
          const Positioned.fill(child: VideoLoadingState()),
        if (controller.playbackStatus == PlayerPlaybackStatus.buffering)
          const Positioned.fill(child: VideoBufferingState()),
        if (controller.playbackStatus == PlayerPlaybackStatus.error)
          Positioned.fill(
            child: VideoErrorState(
              message: controller.errorMessage ?? 'تعذر تشغيل الفيديو.',
              onRetry: controller.retry,
            ),
          ),
        if (controller.showResumePrompt && controller.resumeRecord != null)
          VideoResumePrompt(controller: controller),
      ],
    );
  }

  Widget _buildGradient() {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.4, 1.0],
            colors: [
              Colors.black87,
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
      ),
    );
  }
}
