import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // Landscape-first player: the course videos are 16:9 landscape, so the
    // route locks to landscape + immersive while it is on screen. Restored
    // to portrait in [dispose]. Best-effort on web (orientation lock may
    // reject without a user gesture — the layout itself is responsive).
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
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
        sessionGateway: ref.read(playbackSessionGatewayProvider),
      );
      // NOTE: a temporary DIAGNOSIS-ONLY forced token refresh
      // (`getIdTokenResult(true)`) lived here during the permission-denied
      // hunt and was removed: the player needs only the uid (above), every
      // authorization verdict is re-checked server-side per issuance, and a
      // forced refresh on every open adds avoidable auth latency.
      controller.addListener(_onControllerChanged);
      _controller = controller;
      _initializingController = false;
      // Keep the controller flag in sync with the route-level landscape
      // lock above (drives any fullscreen-aware layout + its own dispose
      // restore). Orientation calls are idempotent.
      controller.fullscreen = true;
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
      // Single-route loading state: full-screen black, no AppBar — the
      // overlay chevron below is the only back affordance and pops the
      // player route exactly once (same contract as the ready state).
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: CircularProgressIndicator()),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              child: IconButton(
                // P4: pinned LTR so the chevron always points left even
                // under the app's RTL Directionality.
                icon: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Icon(
                    Icons.chevron_left,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      );
    }
    if (preferences.hasError) {
      // Single-route error state: full-screen black, no AppBar widget.
      // The overlay chevron is the only back affordance (single pop to
      // the subject page); retry stays in-route, never pushes.
      final message = 'تعذر تهيئة التخزين المحلي: ${preferences.error}';
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 8,
              child: IconButton(
                // P4: pinned LTR so the chevron always points left even
                // under the app's RTL Directionality.
                icon: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Icon(
                    Icons.chevron_left,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller!,
      // Reference design has no app bar: the overlay top bar (back chevron
      // + title + quality pill) is the only chrome. The overlay back
      // chevron pops this route exactly once, landing directly on the
      // subject page — no intermediate route, no fullscreen-exit hop.
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayerLayout(
          controller: _controller!,
          sectionButtonLabel: _sectionButtonLabel(),
          onBack: () {
            Navigator.pop(context);
          },
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

  /// Section-aware toolbar label matching the reference design order:
  /// Lectures (explanation/default) | Revisions | Finals | Online.
  /// Resolved from the active episode's section against the catalog.
  String _sectionButtonLabel() {
    final sectionId = _controller?.sectionId;
    String? key;
    if (sectionId != null && sectionId.isNotEmpty) {
      for (final section in widget.seasons) {
        if (section.id == sectionId) {
          key = section.sectionKey?.toLowerCase();
          break;
        }
      }
    }
    return switch (key) {
      'revision' || 'revisions' => 'Revisions',
      'final_review' || 'final' || 'finals' => 'Finals',
      'online' => 'Online',
      _ => 'Lectures',
    };
  }

  Future<void> _showQualitySheet() async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quality',
      // Transparent barrier: the sheet itself paints the single reference
      // rgba(0,0,0,0.8) overlay and handles outside-tap close, so the
      // dialog barrier must not add a second dim layer.
      barrierColor: Colors.transparent,
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
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) => VideoLecturePanel(
        controller: _controller!,
        panelTitle: _sectionButtonLabel(),
        seasonLabel: _activeSeasonTitle(),
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  /// Title of the active section for the season pill ('' hides it).
  String _activeSeasonTitle() {
    final sectionId = _controller?.sectionId;
    if (sectionId == null || sectionId.isEmpty) return '';
    for (final section in widget.seasons) {
      if (section.id == sectionId) return section.title;
    }
    return '';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    // Restore the app-wide portrait + edge-to-edge chrome on exit.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    super.dispose();
  }
}
