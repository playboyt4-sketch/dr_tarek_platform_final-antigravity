import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

/// Center controls matching `docs/video player .html`:
/// skip-back 42 | gap 70 | plain triangle/pause glyph 85 | gap 70 | skip-forward 42.
class VideoCenterControls extends StatelessWidget {
  final VideoPlaybackController controller;

  const VideoCenterControls({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    // Reference design is LTR: rewind (-10s) LEFT, play CENTER, forward
    // (+10s) RIGHT. Pinned explicitly because the app RTL locale would
    // otherwise mirror the order. Sizes are reference-exact on wide screens
    // and scale down on narrow portrait phones so the cluster hugs the play
    // button instead of dominating the frame.
    final width = MediaQuery.sizeOf(context).width;
    final s = (width / 700).clamp(0.6, 1.0);
    final gap = (width * 0.09).clamp(28.0, 70.0) * s;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSkipBtn(
              context,
              size: 42 * s,
              icon: Icons.replay_10_rounded,
              onPressed: () =>
                  controller.seekRelative(const Duration(seconds: -10)),
            ),
            SizedBox(width: gap),
            _buildPlayBtn(context, size: 85 * s),
            SizedBox(width: gap),
            _buildSkipBtn(
              context,
              size: 42 * s,
              icon: Icons.forward_10_rounded,
              onPressed: () =>
                  controller.seekRelative(const Duration(seconds: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipBtn(
    BuildContext context, {
    required double size,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      iconSize: size,
      color: Colors.white.withValues(alpha: 0.85),
      onPressed: onPressed,
      icon: Icon(icon),
      splashRadius: 30,
    );
  }

  Widget _buildPlayBtn(BuildContext context, {required double size}) {
    return IconButton(
      iconSize: size,
      color: Colors.white,
      onPressed: controller.togglePlayPause,
      icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
    );
  }
}
