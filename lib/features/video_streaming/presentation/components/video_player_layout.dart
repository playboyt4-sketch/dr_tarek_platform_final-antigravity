import 'dart:async';

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
  final VoidCallback? onDownloadTap;
  final bool isDownloading;
  final bool isDownloaded;
  final double downloadProgress;

  /// Watermark text to display (defaults to controller.userId if omitted).
  final String? watermarkText;

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
    this.onDownloadTap,
    this.isDownloading = false,
    this.isDownloaded = false,
    this.downloadProgress = 0.0,
    this.watermarkText,
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

          // Watermark: phone number or stable identity handle, moving
          // between 4 screen corners every 18 seconds.
          _MovingWatermark(
            text: (watermarkText != null && watermarkText!.trim().isNotEmpty)
                ? watermarkText!.trim()
                : controller.userId,
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
            onDownloadTap: onDownloadTap,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress,
            sectionButtonLabel: sectionButtonLabel,
          ),
        ],
      ),
    );
  }
}

class _MovingWatermark extends StatefulWidget {
  final String text;

  const _MovingWatermark({required this.text});

  @override
  State<_MovingWatermark> createState() => _MovingWatermarkState();
}

class _MovingWatermarkState extends State<_MovingWatermark> {
  Timer? _timer;
  int _positionIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 18), (_) {
      if (mounted) {
        setState(() {
          _positionIndex = (_positionIndex + 1) % 4;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 4 corners:
    // 0: bottom-right (bottom: 42, right: 16)
    // 1: top-left (top: 64, left: 16)
    // 2: bottom-left (bottom: 42, left: 16)
    // 3: top-right (top: 64, right: 16)
    double? top;
    double? bottom;
    double? left;
    double? right;

    switch (_positionIndex) {
      case 0:
        bottom = 42;
        right = 16;
        break;
      case 1:
        top = 64;
        left = 16;
        break;
      case 2:
        bottom = 42;
        left = 16;
        break;
      case 3:
        top = 64;
        right = 16;
        break;
    }

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.30,
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
                widget.text,
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
    );
  }
}
