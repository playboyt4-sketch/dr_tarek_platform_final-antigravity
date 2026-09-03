import 'package:flutter/material.dart';
import '../../../../core/responsive/responsive.dart';
import '../controllers/video_playback_controller.dart';
import '../../domain/entities/playback_entities.dart';

/// Top bar matching `docs/video player .html`:
/// back chevron (32) | centered course title (18/w800) + subtitle (13/#ccc)
/// | quality pill badge (12/w700, frosted white 20%).
class VideoHeader extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onBack;

  const VideoHeader({
    required this.controller,
    required this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final qualityLabel = controller.selectedQuality == VideoQuality.auto ||
            controller.selectedQuality.backendValue == null
        ? 'Auto'
        : controller.selectedQuality.backendValue!;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(30),
        vertical: context.rsV(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.chevron_left,
              size: context.rsFont(32),
              color: Colors.white,
            ),
            onPressed: onBack,
          ),
          SizedBox(width: context.rs(15)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.episodeTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsFont(18),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: context.rsV(2)),
                Text(
                  'حلقة ${controller.currentEpisodeIndex + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsFont(13),
                    color: const Color(0xFFCCCCCC),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: context.rs(15)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rs(12),
              vertical: context.rsV(4),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(context.rs(20)),
            ),
            child: Text(
              qualityLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: context.rsFont(12),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
