import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';
import 'video_lecture_card.dart';

/// Full-screen lectures overlay matching `docs/video player .html`:
/// solid black, close chevron-down top-left, centered section title,
/// left-aligned season pill, cards row vertically centered (280x160).
class VideoLecturePanel extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onClose;

  /// Section-aware title (Lectures / Revisions / Finals / Online).
  final String panelTitle;

  /// Season pill label (e.g. section title). Empty hides the pill.
  final String seasonLabel;

  const VideoLecturePanel({
    required this.controller,
    required this.onClose,
    this.panelTitle = 'Lectures',
    this.seasonLabel = '',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Reference overlay is LTR: close glyph left, pill left-aligned, cards
    // flow left-to-right. Pinned explicitly (app locale is RTL).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            _buildHeader(),
            if (seasonLabel.isNotEmpty) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    seasonLabel,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // FINAL_DECISIONS §12 nicety: remaining window time when the
            // currently-open episode owns the student's 24-hour video window.
            if (controller.watchWindowExpiresAt != null &&
                controller.watchWindowActiveLectureId ==
                    controller.lectureId &&
                controller.watchWindowExpiresAt!.isAfter(DateTime.now()))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _windowCountdown(controller.watchWindowExpiresAt!),
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            // Cards row vertically centered (reference: align-items:center).
            Expanded(
              child: Center(
                child: SizedBox(
                  height: 176,
                  child: ListView.builder(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: controller.episodes.length,
                    itemBuilder: (context, index) {
                      final lecture = controller.episodes[index];
                      final isActive = controller.lectureId == lecture.id;
                      return VideoLectureCard(
                        lecture: lecture,
                        isActive: isActive,
                        lockedByWindow:
                            controller.watchWindowActiveLectureId != null &&
                                controller.watchWindowActiveLectureId !=
                                    lecture.id,
                        onTap: () {
                          if (!isActive) {
                            controller.switchEpisode(lecture);
                          }
                          onClose();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _windowCountdown(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return '';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) {
      return 'لسه فاضلك $hours ساعة و$minutes دقيقة من فيديوك الحالي';
    }
    return 'لسه فاضلك $minutes دقيقة من فيديوك الحالي';
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: Text(
            panelTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft, // matching absolute left:0 in CSS
          child: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: 36),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}
