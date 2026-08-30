import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../bookmarks/presentation/providers/bookmarks_providers.dart';
import '../../data/repositories/playback_repository.dart';
import '../controllers/video_playback_controller.dart';
import '../providers/video_streaming_providers.dart';
import '../components/video_documents_sheet.dart';
import '../components/video_player_layout.dart';
import '../components/video_lecture_panel.dart';
import '../components/video_quality_sheet.dart';
import '../../../lecture/presentation/screens/pdf_viewer_screen.dart';
import '../../../membership/presentation/screens/membership_plans_screen.dart';

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
        watchWindowGateway: ref.watch(watchWindowGatewayProvider),
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
            onUpgradeTap: () {
              final navigator = Navigator.of(context);
              final user = ref.read(authProvider).value;
              if (user == null) return;
              unawaited(navigator.push(MaterialPageRoute(
                builder: (_) => MembershipPlansScreen(user: user),
              )));
            },
            onPdfTap: () async {
              if (_controller == null) return;
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );

                final resources = await _controller!.sourceResolver.loadResources(_controller!.lectureId);

                if (mounted) {
                  navigator.pop();
                }

                // Storage-delivery Fix 1: attachments join PDFs as openable
                // documents. Provider dispatch stays in the Data layer —
                // the sheet only forwards the opaque storageProvider string.
                final documents = LectureDocuments.fromResources(resources);
                if (documents.isEmpty) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('لا توجد ملفات متاحة لهذه المحاضرة.')),
                    );
                  }
                  return;
                }

                // Legacy UX preserved: a lecture with exactly one document
                // and it is the PDF -> open it directly (no sheet).
                if (documents.length == 1 && documents.single.isPdf) {
                  final pdf = documents.single;
                  if (mounted) {
                    unawaited(navigator.push(
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen(
                          resourceId: pdf.resourceId,
                          title: pdf.title,
                          subjectId: _controller!.subjectId,
                          lectureId: _controller!.lectureId,
                          storageProvider: pdf.storageProvider,
                          videoController: _controller,
                        ),
                      ),
                    ));
                  }
                  return;
                }

                if (!mounted) return;
                await showLectureDocumentsSheet(
                  this.context,
                  documents: documents,
                  subjectId: _controller!.subjectId,
                  lectureId: _controller!.lectureId,
                  videoController: _controller,
                );
              } catch (_) {
                if (mounted) {
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('تعذر تحميل موارد المحاضرة.')),
                  );
                }
              }
            },
            onQualityTap: _showQualitySheet,
            onBookmarkTap: _saveBookmark,
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

  /// Persists a bookmark for the current lecture at the current position.
  Future<void> _saveBookmark() async {
    final controller = _controller;
    if (controller == null) return;
    final userId = widget.studentId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final position = controller.position;
    try {
      await ref.read(bookmarksRepositoryProvider).createBookmark(
            studentId: userId,
            subjectId: controller.subjectId,
            lectureId: controller.lectureId,
            title: controller.episodeTitle,
            videoTimestampSeconds: position.inSeconds,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'تم الحفظ عند الموضع ${_formatBookmarkTime(position)}.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر حفظ الإشارة المرجعية.')),
      );
    }
  }

  static String _formatBookmarkTime(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
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
