import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../data/repositories/playback_repository.dart';
import '../controllers/video_playback_controller.dart';
import '../providers/video_streaming_providers.dart';
import '../components/video_player_layout.dart';
import '../components/video_lecture_panel.dart';
import '../components/video_quality_sheet.dart';

class VideoStreamingScreen extends ConsumerStatefulWidget {
  final String subjectId;
  final String? studentId;
  final LectureSummary initialEpisode;
  final List<LectureSummary> episodes;
  final List<LearningSection> seasons;
  final Future<List<LectureSummary>> Function(String sectionId)? loadEpisodes;
  final PlaybackRepository? playbackRepositoryOverride;

  const VideoStreamingScreen({
    required this.subjectId,
    required this.initialEpisode,
    required this.episodes,
    this.seasons = const [],
    this.loadEpisodes,
    this.playbackRepositoryOverride,
    this.studentId,
    super.key,
  });

  @override
  ConsumerState<VideoStreamingScreen> createState() =>
      _VideoStreamingScreenState();
}

class _VideoStreamingScreenState extends ConsumerState<VideoStreamingScreen>
    with WidgetsBindingObserver {
  VideoPlaybackController? _controller;
  Timer? _hideControlsTimer;
  bool _initializingController = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller?.handleLifecycle(state));
  }

  void _ensureController() {
    if (_controller != null || _initializingController) return;
    final prefsAsync = ref.read(sharedPreferencesProvider);
    prefsAsync.whenData((preferences) {
      if (!mounted || _controller != null) return;
      _initializingController = true;
      final userId = widget.studentId ?? FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        _initializingController = false;
        return;
      }
      final controller = VideoPlaybackController(
        userId: userId,
        subjectId: widget.subjectId,
        sourceResolver: ref.read(videoSourceResolverProvider),
        entitlementService: ref.read(videoEntitlementServiceProvider),
        playbackRepository:
            widget.playbackRepositoryOverride ??
            playbackRepositoryFor(userId: userId, preferences: preferences),
        episodes: widget.episodes,
        episode: widget.initialEpisode,
      );
      controller.addListener(_onControllerChanged);
      _controller = controller;
      _initializingController = false;
      unawaited(controller.initialize());
      _scheduleHideControls();
      setState(() {});
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller?.isPlaying == true) _scheduleHideControls();
    setState(() {});
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_controller?.locked == true || _controller?.isPlaying != true) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller != null && !_controller!.locked) {
        setState(() => _controller!.controlsVisible = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureController();
    final preferences = ref.watch(sharedPreferencesProvider);
    if (preferences.isLoading || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (preferences.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('الفيديو')),
        body: Center(
          child: Text('تعذر تهيئة التخزين المحلي: ${preferences.error}'),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) => PopScope(
        canPop: !_controller!.fullscreen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _controller!.fullscreen) {
            unawaited(_controller!.setFullscreen(false));
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: _controller!.fullscreen
              ? null
              : AppBar(title: Text(_controller!.episodeTitle)),
          body: VideoPlayerLayout(
            controller: _controller!,
            onBack: () => Navigator.of(context).maybePop(),
            onLecturesTap: _showEpisodesPanel,
            onPdfTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم توفير ملفات PDF قريباً.')),
              );
            },
            onQualityTap: _showQualitySheet,
            onNextTap: () {
              if (_controller!.hasNextEpisode) {
                _controller!.nextEpisode();
              }
            },
            onToggleControls: () {
              _controller!.toggleControls();
              _scheduleHideControls();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showQualitySheet() async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quality',
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondaryAnimation) => VideoQualitySheet(
        controller: _controller!,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _showEpisodesPanel() async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Lectures',
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondaryAnimation) => VideoLecturePanel(
        controller: _controller!,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }
}
