import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

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
          const SizedBox(width: 70),
          _buildPlayBtn(),
          const SizedBox(width: 70),
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

  Widget _buildPlayBtn() {
    return IconButton(
      iconSize: 85,
      color: Colors.white,
      onPressed: controller.togglePlayPause,
      icon: Icon(controller.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
    );
  }
}
