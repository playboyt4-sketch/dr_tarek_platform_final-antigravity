import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/video_playback_controller.dart';

class VideoSurface extends StatelessWidget {
  final VideoPlaybackController controller;
  const VideoSurface({required this.controller, super.key});

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
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            );
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: engine.value.size.width,
        height: engine.value.size.height,
        child: VideoPlayer(engine),
      ),
    );
  }
}
