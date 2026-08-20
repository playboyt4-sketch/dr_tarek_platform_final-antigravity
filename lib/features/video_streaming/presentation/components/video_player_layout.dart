import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';
import 'video_overlay_controls.dart';
import 'video_surface.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VideoPlayerLayout extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onBack;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;
  final VoidCallback onToggleControls;

  const VideoPlayerLayout({
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
    final media = MediaQuery.of(context);
    final isWide = media.orientation == Orientation.landscape || controller.fullscreen;

    return SafeArea(
      top: !controller.fullscreen,
      bottom: !controller.fullscreen,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 1600 : double.infinity,
            ),
            child: AspectRatio(
              aspectRatio: isWide
                  ? (media.size.width / media.size.height).clamp(1.25, 2.4)
                  : 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoSurface(controller: controller),
                  
                  // Watermark
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              FirebaseAuth.instance.currentUser?.displayName ??
                              FirebaseAuth.instance.currentUser?.email ??
                              'Dr. Tarek Platform',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
