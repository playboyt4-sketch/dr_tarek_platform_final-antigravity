import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../controllers/video_playback_controller.dart';

/// Edge sliders matching `docs/video player .html` (volume icon + vertical
/// track on the LEFT, brightness icon + vertical track on the RIGHT —
/// physical positions, never mirrored).
///
/// Unlike the reference demo's hardcoded 120px track, the track height here
/// is derived at runtime from the ACTUAL middle-band height (the space
/// between the top bar's bottom edge and the bottom bar's top edge): the
/// parent places each slider in a full-height slot of that middle band and
/// this widget sizes its track as a fraction of the slot via LayoutBuilder,
/// in the same layout pass — so the sliders can never overlap the top or
/// bottom bars on any viewport.
///
/// System controls are used when the platform supports them; otherwise the
/// volume slider falls back to the player engine volume so the control stays
/// visible (e.g. web builds where system plugins are unavailable).
class VideoEdgeSlider extends StatefulWidget {
  final VideoPlaybackController? controller;

  /// True for the volume slider, false for the brightness slider.
  final bool isVolume;

  const VideoEdgeSlider.volume({this.controller, super.key})
    : isVolume = true;

  const VideoEdgeSlider.brightness({this.controller, super.key})
    : isVolume = false;

  @override
  State<VideoEdgeSlider> createState() => _VideoEdgeSliderState();
}

class _VideoEdgeSliderState extends State<VideoEdgeSlider> {
  double _volume = 0.5;
  // Slider position matching the neutral 1.0 video-brightness factor
  // ((1.0 - 0.2) / 1.3) so the control reads consistently pre-touch.
  double _brightness = 0.62;
  bool _isVolumeSupported = true;
  bool _isBrightnessSupported = true;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    if (widget.isVolume) {
      _initVolume();
    } else {
      _initBrightness();
    }
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    if (widget.isVolume) {
      VolumeController.instance.removeListener();
    }
    super.dispose();
  }

  Future<void> _initVolume() async {
    try {
      final volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      setState(() => _volume = volume);
      _volumeSub = VolumeController.instance.addListener((volume) {
        if (mounted) {
          setState(() => _volume = volume);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isVolumeSupported = false);
      }
    }
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().application;
      ScreenBrightness().onApplicationScreenBrightnessChanged.listen((
        brightness,
      ) {
        if (mounted) {
          setState(() {
            _brightness = brightness;
          });
        }
      });
    } catch (_) {
      _isBrightnessSupported = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    if (_isVolumeSupported) {
      try {
        await VolumeController.instance.setVolume(clamped);
        return;
      } catch (_) {
        if (mounted) setState(() => _isVolumeSupported = false);
      }
    }
    // Fallback: engine volume (web / unsupported platforms).
    try {
      await widget.controller?.engine?.setVolume(clamped);
    } catch (_) {}
  }

  Future<void> _setBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _brightness = clamped);
    if (_isBrightnessSupported) {
      try {
        await ScreenBrightness().setApplicationScreenBrightness(clamped);
        return;
      } catch (_) {
        if (mounted) setState(() => _isBrightnessSupported = false);
      }
    }
    // Fallback: per-video brightness filter (web / unsupported platforms).
    widget.controller?.setVideoBrightness(clamped);
  }

  @override
  Widget build(BuildContext context) {
    // Volume is always shown (system control, else engine fallback).
    // Brightness is always shown too: system control where supported,
    // per-video filter fallback elsewhere (reference: right-side slider).
    final icon = widget.isVolume ? Icons.volume_up : Icons.brightness_6;
    final value = widget.isVolume ? _volume : _brightness;
    final onChanged = widget.isVolume ? _setVolume : _setBrightness;
    // Runtime-derived track height: a fraction of the ACTUAL middle-band
    // slot height (same layout pass via LayoutBuilder), bounded so the
    // icon + track + touch padding always fit inside the slot — never a
    // fixed pixel copy of the HTML demo, never overlapping the bars.
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = (constraints.maxHeight * 0.42).clamp(64.0, 150.0);
        return Center(
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              // Negative delta means sliding up (increase)
              final delta = -details.primaryDelta! / 120.0;
              onChanged(value + delta);
            },
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(height: 10),
                  Container(
                    width: 4,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          width: 4,
                          height: trackHeight * value,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
