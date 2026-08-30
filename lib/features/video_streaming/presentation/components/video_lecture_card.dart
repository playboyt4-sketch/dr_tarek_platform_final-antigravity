import 'package:flutter/material.dart';
import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';

class VideoLectureCard extends StatelessWidget {
  final LectureSummary lecture;
  final bool isActive;
  final VoidCallback onTap;

  /// FINAL_DECISIONS §12 nicety: another lecture currently owns the
  /// student's rolling 24-hour window — purely informational badge; the
  /// hard enforcement stays server-side.
  final bool lockedByWindow;

  const VideoLectureCard({
    required this.lecture,
    required this.isActive,
    required this.onTap,
    this.lockedByWindow = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        height: 160,
        margin: const EdgeInsets.only(left: 15), // RTL/LTR? The design was horizontal flex with gap 15
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.white : Colors.transparent,
            width: 2,
          ),
          color: Colors.grey[900], // fallback
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (lecture.thumbnailUrl != null)
              Image.network(
                lecture.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
              )
            else
              const ColoredBox(color: Colors.black),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: const Alignment(0.0, 0.2), // matches rgba(0,0,0,0.95) to rgba(0,0,0,0) 60%
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            if (lecture.duration != null)
              Positioned(
                left: 12,
                bottom: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(lecture.duration!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                lecture.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (lockedByWindow)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_clock, color: Colors.white70, size: 12),
                      SizedBox(width: 4),
                      Text(
                        '٢٤ ساعة',
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}
