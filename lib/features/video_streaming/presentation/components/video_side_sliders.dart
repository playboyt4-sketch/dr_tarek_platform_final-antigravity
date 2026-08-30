import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

class VideoSideSliders extends StatefulWidget {
  const VideoSideSliders({super.key});

  @override
  State<VideoSideSliders> createState() => _VideoSideSlidersState();
}

class _VideoSideSlidersState extends State<VideoSideSliders> {
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _isVolumeSupported = true;
  bool _isBrightnessSupported = true;
  StreamSubscription<double>? _volumeSub;

  @override
  void initState() {
    super.initState();
    _initVolume();
    _initBrightness();
  }

  @override
  void dispose() {
    _volumeSub?.cancel();
    VolumeController.instance.removeListener();
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
      ScreenBrightness().onApplicationScreenBrightnessChanged.listen((brightness) {
        if (mounted) {
          setState(() {
            _brightness = brightness;
          });
        }
      });
    } catch (e) {
      _isBrightnessSupported = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _setVolume(double value) async {
    if (!_isVolumeSupported) return;
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    await VolumeController.instance.setVolume(clamped);
  }

  Future<void> _setBrightness(double value) async {
    if (!_isBrightnessSupported) return;
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _brightness = clamped);
    await ScreenBrightness().setApplicationScreenBrightness(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_isVolumeSupported)
          Positioned(
            left: 20,
            top: 0,
            bottom: 0,
            child: _buildSliderControl(
              icon: Icons.volume_up,
              value: _volume,
              onChanged: _setVolume,
            ),
          ),
        if (_isBrightnessSupported)
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: _buildSliderControl(
              icon: Icons.brightness_6,
              value: _brightness,
              onChanged: _setBrightness,
            ),
          ),
      ],
    );
  }

  Widget _buildSliderControl({
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
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
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 4,
                      height: 120 * value,
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
  }
}
