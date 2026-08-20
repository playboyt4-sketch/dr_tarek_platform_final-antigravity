import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';
import '../../domain/entities/playback_entities.dart';

class VideoQualitySheet extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onClose;

  const VideoQualitySheet({
    required this.controller,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      alignment: Alignment.center,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اختر الجودة',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 15),
            ..._buildQualityOptions(context),
            const SizedBox(height: 15),
            TextButton(
              onPressed: onClose,
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildQualityOptions(BuildContext context) {
    final options = <VideoQuality>[
      VideoQuality.auto,
      ...?controller.entitlement?.allowedQualities,
    ];

    return options.map((quality) {
      final isActive = controller.selectedQuality == quality;
      return GestureDetector(
        onTap: () async {
          final changed = await controller.changeQuality(quality);
          if (!changed && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تعذر تغيير الجودة الآن.')),
            );
          }
          onClose();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF222222))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                quality.label,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? const Color(0xFF00c896) : Colors.white,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              if (quality.backendValue != null)
                Text(
                  quality.backendValue!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
