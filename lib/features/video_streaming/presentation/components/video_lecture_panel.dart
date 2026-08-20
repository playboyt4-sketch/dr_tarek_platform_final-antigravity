import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';
import 'video_lecture_card.dart';

class VideoLecturePanel extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onClose;

  const VideoLecturePanel({
    required this.controller,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.95),
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft, // assuming RTL handled by Directionality if needed
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                // Just use the course title or season name here if available
                controller.episodeTitle,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: controller.episodes.length,
              itemBuilder: (context, index) {
                final lecture = controller.episodes[index];
                final isActive = controller.lectureId == lecture.id;
                return VideoLectureCard(
                  lecture: lecture,
                  isActive: isActive,
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
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      children: [
        const Align(
          alignment: Alignment.center,
          child: Text(
            'الحلقات',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft, // matching absolute left:0 in CSS
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}
