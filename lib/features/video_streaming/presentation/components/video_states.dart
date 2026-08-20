import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

class VideoLoadingState extends StatelessWidget {
  const VideoLoadingState({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF00c896)),
      ),
    );
  }
}

class VideoBufferingState extends StatelessWidget {
  const VideoBufferingState({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white70),
    );
  }
}

class VideoErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const VideoErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00c896),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoResumePrompt extends StatelessWidget {
  final VideoPlaybackController controller;

  const VideoResumePrompt({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120, // above bottom bar
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'استئناف من حيث توقفت؟',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () {
                controller.startOver();
              },
              child: const Text('من البداية', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00c896),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                controller.continueWatching();
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }
}
