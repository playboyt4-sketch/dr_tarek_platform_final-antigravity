import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

/// Quality selector matching the `docs/video player .html` reference modal:
/// full-screen dark overlay (rgba 0,0,0,0.8), centered 300px quality box
/// (#111, radius 16, #333 border), "Quality" title, ascending quality
/// options with no dividers, active row in reference green (#00c896,
/// bold) with a check icon. Tapping outside the box or picking an option
/// closes the modal.
///
/// Presentation only: the options are exactly
/// `controller.entitlement?.allowedQualities` — already filtered by the
/// domain entitlement (`video.quality.max` cap applied in
/// [VideoEntitlementService]) — sorted ascending by rank. Disallowed
/// qualities are never rendered (no locks, no disabled rows). Selection
/// runs the existing [VideoPlaybackController.changeQuality] flow, which
/// re-resolves through the `generateBunnySignedUrl` backend (the real
/// enforcement boundary).
class VideoQualitySheet extends StatelessWidget {
  final VideoPlaybackController controller;
  final VoidCallback onClose;

  const VideoQualitySheet({
    required this.controller,
    required this.onClose,
    super.key,
  });

  /// Reference-design tokens (pinned to the HTML mock, not the app theme).
  static const _overlayColor = Color(0xCC000000); // rgba(0,0,0,0.8)
  static const _boxColor = Color(0xFF111111);
  static const _boxBorderColor = Color(0xFF333333);
  static const _activeColor = Color(0xFF00C896);

  @override
  Widget build(BuildContext context) {
    // Responsive-safe box width: reference 300px, shrinks on narrow
    // viewports instead of overflowing (portrait phones, split-screen).
    final boxWidth = math.min(
      300.0,
      MediaQuery.sizeOf(context).width * 0.84,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: Container(
        color: _overlayColor,
        alignment: Alignment.center,
        child: GestureDetector(
          // Absorb taps inside the box so they don't bubble to the
          // overlay close handler (mirrors `event.stopPropagation()`).
          onTap: () {},
          child: Directionality(
            // Reference mock is LTR: label left, check right, in all locales
            // (same pinned-direction convention as the player top bar).
            textDirection: TextDirection.ltr,
            child: Container(
              width: boxWidth,
              decoration: BoxDecoration(
                color: _boxColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _boxBorderColor),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 15),
                  ..._buildQualityOptions(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildQualityOptions(BuildContext context) {
    // Allowed-only, ascending (144p first) — mirrors the reference order.
    // `auto` is excluded: it is not a rendition and never appears in the
    // reference list. When the entitlement is still unresolved the list is
    // empty and only the title renders (same as before).
    final options =
        (controller.entitlement?.allowedQualities
                .where((quality) => quality.backendValue != null)
                .toList() ??
            [])
          ..sort((left, right) => left.rank.compareTo(right.rank));

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
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                quality.backendValue!,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? _activeColor : Colors.white,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                  decoration: TextDecoration.none,
                ),
              ),
              if (isActive)
                const Icon(Icons.check, size: 18, color: _activeColor),
            ],
          ),
        ),
      );
    }).toList();
  }
}
