import 'package:flutter/material.dart';
import '../../../../core/responsive/responsive.dart';
import '../controllers/video_playback_controller.dart';

class VideoBottomActionBar extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;
  final VoidCallback? onBookmarkTap;

  const VideoBottomActionBar({
    required this.controller,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    this.onBookmarkTap,
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
        SizedBox(height: context.rsV(15)),
        _buildToolbar(context),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context) {
    final position = controller.position;
    final duration = controller.duration;
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rs(16)),
      child: Row(
        children: [
          SizedBox(
            width: context.rs(40),
            child: Text(
              _formatDuration(position),
              style: TextStyle(
                fontSize: context.rsFont(12),
                fontWeight: FontWeight.w600,
                color: const Color(0xFFDDDDDD),
              ),
            ),
          ),
          SizedBox(width: context.rs(15)),
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
          SizedBox(width: context.rs(15)),
          SizedBox(
            width: context.rs(40),
            child: Text(
              _formatDuration(duration),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: context.rsFont(12),
                fontWeight: FontWeight.w600,
                color: const Color(0xFFDDDDDD),
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
      padding: EdgeInsets.only(bottom: context.rsV(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildToolBtn(
            context,
            icon: Icons.layers_outlined,
            label: 'الحلقات',
            onTap: onLecturesTap,
          ),
          SizedBox(width: context.rs(35)),
          _buildToolBtn(
            context,
            // Documents entry opens both the lecture PDF and attachments
            // (storage-delivery Fix 1); label generalized accordingly.
            icon: Icons.folder_open_outlined,
            label: 'الملفات',
            onTap: onPdfTap,
          ),
          SizedBox(width: context.rs(35)),
          _buildToolBtn(
            context,
            icon: Icons.settings_outlined,
            label: 'الجودة',
            onTap: onQualityTap,
          ),
          SizedBox(width: context.rs(35)),
          _buildToolBtn(
            context,
            icon: Icons.bookmark_border_rounded,
            label: 'حفظ',
            onTap: onBookmarkTap,
            opacity: onBookmarkTap == null ? 0.3 : 0.85,
          ),
          SizedBox(width: context.rs(35)),
          _buildToolBtn(
            context,
            icon: Icons.skip_next_outlined,
            label: 'التالي',
            onTap: hasNext ? onNextTap : null,
            opacity: hasNext ? 0.85 : 0.3,
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(
    BuildContext context, {
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
            Icon(icon, color: Colors.white, size: context.rsFont(18)),
            SizedBox(width: context.rs(6)),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: context.rsFont(13),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
