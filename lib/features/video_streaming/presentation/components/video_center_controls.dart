import 'package:flutter/material.dart';
import '../../../../core/responsive/responsive.dart';
import '../controllers/video_playback_controller.dart';

/// Center controls matching `docs/video player .html`:
/// skip-back 42 | gap 70 | plain triangle/pause glyph 85 | gap 70 | skip-forward 42.
class VideoCenterControls extends StatelessWidget {
  final VideoPlaybackController controller;

  const VideoCenterControls({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSkipBtn(
            icon: Icons.replay_10_rounded,
            onPressed: () => controller.seekRelative(const Duration(seconds: -10)),
          ),
          SizedBox(width: context.rs(70)),
          _buildPlayBtn(context),
          SizedBox(width: context.rs(70)),
          _buildSkipBtn(
            icon: Icons.forward_10_rounded,
            onPressed: () => controller.seekRelative(const Duration(seconds: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipBtn({required IconData icon, required VoidCallback onPressed}) {
    return IconButton(
      iconSize: 42,
      color: Colors.white.withValues(alpha: 0.85),
      onPressed: onPressed,
      icon: Icon(icon),
      splashRadius: 30,
    );
  }

  Widget _buildPlayBtn(BuildContext context) {
    return IconButton(
      iconSize: context.rsFont(85),
      color: Colors.white,
      onPressed: controller.togglePlayPause,
      icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
    );
  }
}
