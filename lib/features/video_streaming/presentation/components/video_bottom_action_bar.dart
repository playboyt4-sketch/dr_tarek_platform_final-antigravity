import 'package:flutter/material.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../controllers/video_playback_controller.dart';

class VideoBottomActionBar extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onLecturesTap;
  final VoidCallback onPdfTap;
  final VoidCallback onQualityTap;
  final VoidCallback onNextTap;
  final VoidCallback? onBookmarkTap;

  /// Section-aware label for the leftmost toolbar button
  /// (Lectures / Revisions / Finals / Online), resolved by the screen from
  /// the active section. Matches the reference design order (LTR).
  final String sectionButtonLabel;

  const VideoBottomActionBar({
    required this.controller,
    required this.onLecturesTap,
    required this.onPdfTap,
    required this.onQualityTap,
    required this.onNextTap,
    this.onBookmarkTap,
    this.sectionButtonLabel = 'Lectures',
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
    // Reference design is LTR: elapsed time left, total right, toolbar
    // [section | PDF? | Quality | Next] left-to-right. Pinned explicitly
    // because the app locale (RTL) would otherwise mirror both rows.
    // DECIDED (Teacher/Platform Owner): player chrome stays LTR-ordered in
    // all locales (YouTube/Netflix convention) — no RTL mirroring.
    // Progress fill/thumb use AppColors.secondary (DECIDED by
    // Teacher/Platform Owner; the reference `#00c896` is not a design
    // token and is not used anywhere in the player). The time-label gray
    // `#DDDDDD` is the reference value, kept until a neutral token covers
    // it.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTimeline(context),
          SizedBox(height: context.rsV(15)),
          _buildToolbar(context),
        ],
      ),
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
                fontFamily: AppFontFamilies.googleSansFlex,
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
                activeTrackColor: AppColors.secondary,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                thumbColor: AppColors.secondary,
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
                fontFamily: AppFontFamilies.googleSansFlex,
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
    // Overflow-proof by construction: the reference row (fixed 35px gaps,
    // icon 18 + label 13) is ~493px wide — wider than any portrait phone.
    // FittedBox scaleDown renders it 1:1 wherever it fits (reference-exact
    // on landscape/tablet) and scales it down only on narrow screens, so
    // the four actions can never overflow or overlap each other.
    return Padding(
      padding: EdgeInsets.only(bottom: context.rsV(16)),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildToolBtn(
                context,
                icon: Icons.layers_outlined,
                label: sectionButtonLabel,
                onTap: onLecturesTap,
              ),
              if (controller.hasDocuments) ...[
                SizedBox(width: context.rs(35)),
                _buildToolBtn(
                  context,
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  onTap: onPdfTap,
                ),
              ],
              SizedBox(width: context.rs(35)),
              _buildToolBtn(
                context,
                icon: Icons.settings_outlined,
                label: 'Quality',
                onTap: onQualityTap,
              ),
              SizedBox(width: context.rs(35)),
              _buildToolBtn(
                context,
                icon: Icons.skip_next_outlined,
                label: 'Next',
                onTap: hasNext ? onNextTap : null,
                opacity: hasNext ? 0.85 : 0.3,
              ),
              SizedBox(width: context.rs(35)),
              _buildToolBtn(
                context,
                icon: controller.fullscreen
                    ? Icons.fullscreen_exit_outlined
                    : Icons.fullscreen_outlined,
                label: 'Rotate',
                onTap: () {
                  // Manual portrait <-> landscape toggle. The route starts
                  // in landscape (see VideoStreamingScreen); this lets the
                  // student rotate back without leaving the player.
                  controller.setFullscreen(!controller.fullscreen);
                },
              ),
            ],
          ),
        ),
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
                fontFamily: AppFontFamilies.googleSansFlex,
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
