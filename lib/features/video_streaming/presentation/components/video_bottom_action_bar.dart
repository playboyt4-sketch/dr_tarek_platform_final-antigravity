import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

class VideoBottomActionBar extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;

  const VideoBottomActionBar({
    required this.controller,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    super.key,
  });

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTimeline(context),
        const SizedBox(height: 15),
        _buildToolbar(context),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final position = controller.position;
    final duration = controller.duration;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              _formatDuration(position),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDDDDDD),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: const Color(0xFF00c896),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: const Color(0xFF00c896),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: duration.inMilliseconds > 0
                    ? position.inMilliseconds.toDouble()
                    : 0.0,
                min: 0.0,
                max: duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0,
                onChanged: (value) {
                  controller.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
          ),
          const SizedBox(width: 15),
          SizedBox(
            width: 45,
            child: Text(
              _formatDuration(duration),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDDDDDD),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final hasNext = controller.hasNextEpisode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildToolBtn(
            icon: Icons.layers_outlined,
            label: 'الحلقات',
            onTap: onLecturesTap,
          ),
          const SizedBox(width: 35),
          _buildToolBtn(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF',
            onTap: onPdfTap,
          ),
          const SizedBox(width: 35),
          _buildToolBtn(
            icon: Icons.settings_outlined,
            label: 'الجودة',
            onTap: onQualityTap,
          ),
          const SizedBox(width: 35),
          _buildToolBtn(
            icon: Icons.skip_next_outlined,
            label: 'التالي',
            onTap: hasNext ? onNextTap : null,
            opacity: hasNext ? 0.85 : 0.3,
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    double opacity = 0.85,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
