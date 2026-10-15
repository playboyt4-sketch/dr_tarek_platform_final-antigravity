import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/video_playback_controller.dart';

class VideoSurface extends StatelessWidget {
  final VideoPlaybackController controller;
  const VideoSurface({required this.controller, super.key});

  /// Fallback display aspect when the engine initialized with metadata but
  /// without video dimensions ([Size.zero]): hls.js/MSE can report duration
  /// before the first video frame dimensions arrive, and neither the web
  /// plugin (single initialized snapshot, no resize event) nor video_player
  /// (one initialized event per instance) ever revises the size afterwards.
  /// A zero box would hide decoded frames permanently while audio keeps
  /// playing — so render a 16:9 box instead. The valid-size path below is
  /// untouched.
  static const double kFallbackDisplayAspectRatio = 16 / 9;

  /// True when [size] carries real video dimensions.
  static bool hasRenderableSize(Size size) =>
      size.width > 0 && size.height > 0;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    if (engine == null || !engine.value.isInitialized) {
      final image = controller.episodeThumbnailUrl;
      return image == null
          ? const ColoredBox(
              color: Colors.black,
            )
          : Image.network(
              image,
              fit: BoxFit.cover,
              color: Colors.black45,
              colorBlendMode: BlendMode.darken,
              // P2: low-opacity block ONLY while the bytes are in flight.
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : ColoredBox(
                      color: Colors.grey.shade900.withValues(alpha: 0.6),
                    ),
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            );
    }
    final factor = controller.videoBrightness;
    final player = VideoPlayer(engine);
    final Widget child = (factor - 1.0).abs() < 0.001
        ? player
        : ColorFiltered(
            // Per-video brightness (right-side slider fallback on platforms
            // without system control). Neutral 1.0 renders unfiltered.
            colorFilter: ColorFilter.matrix(_brightnessMatrix(factor)),
            child: player,
          );
    final reportedSize = engine.value.size;
    if (!hasRenderableSize(reportedSize)) {
      // Zero-size fallback: keeps decoded frames visible when dimensions
      // were unavailable at initialization (read-only diagnostic below).
      debugPrint(
        '[VIDEO-DIAG] surface zero-size fallback '
        'duration=${engine.value.duration}',
      );
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: kFallbackDisplayAspectRatio,
            child: child,
          ),
        ),
      );
    }
    // Landscape-first route: a 16:9 source fills edge-to-edge (cover).
    // A portrait (vertical) source would lose its top/bottom under cover
    // in a landscape route, so it letterboxes (contain) instead — full
    // content stays visible, no heads cut.
    final isPortraitSource = reportedSize.height > reportedSize.width;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: isPortraitSource ? BoxFit.contain : BoxFit.cover,
          child: SizedBox(
            width: reportedSize.width,
            height: reportedSize.height,
            child: child,
          ),
        ),
      ),
    );
  }

  /// 4x5 brightness matrix: RGB shifted by (factor - 1) * 255, alpha kept.
  static List<double> _brightnessMatrix(double factor) {
    final offset = (factor - 1.0) * 255.0;
    return <double>[
      1, 0, 0, 0, offset,
      0, 1, 0, 0, offset,
      0, 0, 1, 0, offset,
      0, 0, 0, 1, 0,
    ];
  }
}
