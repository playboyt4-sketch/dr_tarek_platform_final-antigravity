import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/services/video_source_resolver.dart';
import '../../domain/entities/playback_entities.dart';

class VideoPlaybackController extends ChangeNotifier {
  final String userId;
  final String subjectId;
  final VideoSourceGateway sourceResolver;
  final VideoEntitlementGateway entitlementService;
  final PlaybackRepository playbackRepository;

  List<LectureSummary> episodes;
  String lectureId;
  String sectionId;
  String episodeTitle;
  String? episodeThumbnailUrl;
  Duration? skipIntroStart;
  Duration? skipIntroEnd;

  VideoPlayerController? _engine;
  VideoResource? _resource;
  VideoEntitlement? _entitlement;
  PlaybackProgressRecord? _resumeRecord;
  PlayerPlaybackStatus playbackStatus = PlayerPlaybackStatus.initial;
  VideoQuality selectedQuality = VideoQuality.auto;
  String? errorMessage;
  bool controlsVisible = true;
  bool locked = false;
  bool fullscreen = false;
  bool showResumePrompt = false;
  bool showNextEpisodePrompt = false;
  bool _disposed = false;
  bool _initializing = false;
  int _operationId = 0;
  DateTime? _lastProgressSave;
  DateTime? _lastCloudSave;
  DateTime? _sourceExpiresAt;
  DateTime? _bufferingStartedAt;
  bool _refreshingSource = false;
  bool _prefetchingNextEpisode = false;
  final Map<String, ResolvedVideoSource> _prefetchedSources = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  VideoPlaybackController({
    required this.userId,
    required this.subjectId,
    required this.sourceResolver,
    required this.entitlementService,
    required this.playbackRepository,
    required this.episodes,
    required LectureSummary episode,
  }) : lectureId = episode.id,
       sectionId = episode.sectionId ?? '',
       episodeTitle = episode.title,
       episodeThumbnailUrl = episode.thumbnailUrl,
       skipIntroStart = episode.skipIntroStart,
       skipIntroEnd = episode.skipIntroEnd;

  VideoPlayerController? get engine => _engine;
  VideoResource? get resource => _resource;
  PlaybackProgressRecord? get resumeRecord => _resumeRecord;
  VideoEntitlement? get entitlement => _entitlement;
  Duration get position => _engine?.value.position ?? Duration.zero;
  Duration get duration {
    final controllerDuration = _engine?.value.duration ?? Duration.zero;
    return controllerDuration > Duration.zero
        ? controllerDuration
        : _resource?.duration ?? Duration.zero;
  }

  bool get isPlaying => _engine?.value.isPlaying == true;
  bool get isBuffering => _engine?.value.isBuffering == true;
  bool get isReady => _engine?.value.isInitialized == true;
  bool get hasNextEpisode =>
      EpisodeNavigation.nextIndex(
        currentIndex: currentEpisodeIndex,
        count: episodes.length,
      ) !=
      null;
  int get currentEpisodeIndex => episodes
      .indexWhere((item) => item.id == lectureId)
      .clamp(0, episodes.isEmpty ? 0 : episodes.length - 1);
  double get progress => ProgressMath.percent(position, duration);
  bool get canSkipIntro =>
      skipIntroStart != null &&
      skipIntroEnd != null &&
      skipIntroEnd! > skipIntroStart! &&
      position >= skipIntroStart! &&
      position < skipIntroEnd!;

  Future<void> initialize() async {
    if (_disposed ||
        _initializing ||
        playbackStatus == PlayerPlaybackStatus.disposed) {
      return;
    }
    _initializing = true;
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none) &&
          playbackStatus == PlayerPlaybackStatus.error &&
          !_initializing) {
        unawaited(retry());
      }
    });
    errorMessage = null;
    playbackStatus = PlayerPlaybackStatus.loading;
    _notify();
    final operation = ++_operationId;
    try {
      _entitlement = await entitlementService.resolve(
        userId: userId,
        subjectId: subjectId,
      );
      if (_disposed || operation != _operationId) return;
      if (_entitlement?.allowed != true) {
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage =
            _entitlement?.message ?? 'لا تملك صلاحية مشاهدة هذا الفيديو.';
        _notify();
        return;
      }
      await _prepareSource(
        operation: operation,
        restoreProgress: true,
        autoplay: false,
      );
    } catch (error) {
      if (!_disposed && operation == _operationId) {
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage = error is VideoSourceException
            ? error.message
            : 'تعذر تهيئة مشغل الفيديو.';
        _notify();
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _prepareSource({
    required int operation,
    required bool restoreProgress,
    required bool autoplay,
  }) async {
    _resource = null;
    final resources = await sourceResolver.loadResources(lectureId);
    if (_disposed || operation != _operationId) return;
    final videoResources = resources.where((item) => item.isVideo).toList();
    if (videoResources.isEmpty) {
      throw const VideoSourceException(
        'لا يوجد مصدر فيديو منشور لهذه المحاضرة.',
      );
    }
    _resource = videoResources.first;

    if (restoreProgress) {
      _resumeRecord = await playbackRepository.read(lectureId);
      if (_disposed || operation != _operationId) return;
      showResumePrompt =
          ProgressMath.resumeAction(_resumeRecord) ==
          ResumeAction.continueWatching;
    }

    await _loadEngine(
      operation: operation,
      positionToRestore: restoreProgress ? _resumeRecord?.position : null,
      autoplay: autoplay,
    );
  }

  Future<void> _loadEngine({
    required int operation,
    Duration? positionToRestore,
    required bool autoplay,
  }) async {
    final resource = _resource;
    if (resource == null) {
      throw const VideoSourceException('مصدر الفيديو غير متاح.');
    }
    final cacheKey = _sourceCacheKey(lectureId, selectedQuality);
    final cachedSource = _prefetchedSources.remove(cacheKey);
    final source =
        cachedSource != null &&
            cachedSource.expiresAt.difference(DateTime.now()) >
                const Duration(seconds: 30)
        ? cachedSource
        : await sourceResolver.resolve(
            resource: resource,
            quality: selectedQuality,
            subjectId: subjectId,
          );
    _sourceExpiresAt = source.expiresAt;
    if (_disposed || operation != _operationId) return;

    final previous = _engine;
    previous?.removeListener(_onEngineUpdate);
    _engine = null;
    await previous?.dispose();

    final next = VideoPlayerController.networkUrl(source.url);
    _engine = next;
    next.addListener(_onEngineUpdate);
    await next.initialize();
    if (_disposed || operation != _operationId) {
      await next.dispose();
      return;
    }
    if (positionToRestore != null && positionToRestore > Duration.zero) {
      await next.seekTo(
        ProgressMath.clampPosition(positionToRestore, next.value.duration),
      );
    }
    playbackStatus = PlayerPlaybackStatus.ready;
    errorMessage = null;
    _notify();
    if (autoplay) await play();
    unawaited(prefetchNextEpisode());
  }

  String _sourceCacheKey(String episodeId, VideoQuality quality) =>
      '$episodeId:${quality.backendValue ?? 'auto'}';

  Future<void> prefetchNextEpisode() async {
    if (_disposed || _prefetchingNextEpisode || !hasNextEpisode) return;
    _prefetchingNextEpisode = true;
    try {
      final nextIndex = EpisodeNavigation.nextIndex(
        currentIndex: currentEpisodeIndex,
        count: episodes.length,
      );
      if (nextIndex == null) return;
      final nextEpisode = episodes[nextIndex];
      final resources = await sourceResolver.loadResources(nextEpisode.id);
      final resource = resources.where((item) => item.isVideo).firstOrNull;
      if (resource == null || _disposed) return;
      final quality = selectedQuality;
      final source = await sourceResolver.resolve(
        resource: resource,
        quality: quality,
        subjectId: subjectId,
      );
      if (!_disposed) {
        _prefetchedSources[_sourceCacheKey(nextEpisode.id, quality)] = source;
      }
    } catch (_) {
      // Prefetch is opportunistic and must never block normal playback.
    } finally {
      _prefetchingNextEpisode = false;
    }
  }

  void _onEngineUpdate() {
    if (_disposed) return;
    final value = _engine?.value;
    if (value == null || !value.isInitialized) return;
    if (value.hasError) {
      playbackStatus = PlayerPlaybackStatus.error;
      errorMessage = 'حدث خطأ أثناء تشغيل الفيديو. يمكنك إعادة المحاولة.';
      _notify();
      return;
    }
    if (value.isBuffering) {
      _bufferingStartedAt ??= DateTime.now();
      playbackStatus = PlayerPlaybackStatus.buffering;
      if (DateTime.now().difference(_bufferingStartedAt!) >=
          const Duration(seconds: 8)) {
        unawaited(_downgradeAfterBuffering());
      }
    } else if (value.isPlaying) {
      _bufferingStartedAt = null;
      playbackStatus = PlayerPlaybackStatus.playing;
    } else if (value.position >= value.duration &&
        value.duration > Duration.zero) {
      playbackStatus = PlayerPlaybackStatus.completed;
      if (!showNextEpisodePrompt) {
        showNextEpisodePrompt = true;
        unawaited(_persistProgress(forceCloud: true));
      }
    } else {
      playbackStatus = PlayerPlaybackStatus.paused;
    }
    final now = DateTime.now();
    if (now.difference(
          _lastProgressSave ?? DateTime.fromMillisecondsSinceEpoch(0),
        ) >=
        const Duration(seconds: 3)) {
      unawaited(_persistProgress(forceCloud: false));
    }
    if (_sourceExpiresAt != null &&
        _sourceExpiresAt!.difference(DateTime.now()) <=
            const Duration(seconds: 60)) {
      unawaited(_refreshSourceSilently());
    }
    _notify();
  }

  Future<void> _refreshSourceSilently() async {
    if (_disposed || _refreshingSource || _resource == null) return;
    _refreshingSource = true;
    final operation = ++_operationId;
    final restorePosition = position;
    final wasPlaying = isPlaying;
    try {
      await _loadEngine(
        operation: operation,
        positionToRestore: restorePosition,
        autoplay: wasPlaying,
      );
    } catch (_) {
      // Keep the current player alive; the regular retry path handles hard failures.
    } finally {
      _refreshingSource = false;
    }
  }

  Future<void> _downgradeAfterBuffering() async {
    if (_disposed || _refreshingSource || _entitlement == null) return;
    final lower =
        _entitlement!.allowedQualities
            .where((quality) => quality.rank < selectedQuality.rank)
            .toList()
          ..sort((left, right) => right.rank.compareTo(left.rank));
    if (lower.isEmpty) return;
    await changeQuality(lower.first);
  }

  Future<void> play() async {
    final engine = _engine;
    if (_disposed ||
        engine == null ||
        !engine.value.isInitialized ||
        engine.value.isPlaying) {
      return;
    }
    showResumePrompt = false;
    showNextEpisodePrompt = false;
    await engine.play();
    if (!_disposed) {
      playbackStatus = PlayerPlaybackStatus.playing;
      _notify();
    }
  }

  Future<void> pause() async {
    final engine = _engine;
    if (_disposed || engine == null || !engine.value.isPlaying) return;
    await engine.pause();
    await _persistProgress(forceCloud: true);
    if (!_disposed) {
      playbackStatus = PlayerPlaybackStatus.paused;
      _notify();
    }
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> seekRelative(Duration offset) async {
    unawaited(HapticFeedback.selectionClick());
    final target = ProgressMath.clampPosition(position + offset, duration);
    await seekTo(target);
  }

  Future<void> seekPreview(double fraction) async {
    final engine = _engine;
    if (_disposed || engine == null || !engine.value.isInitialized) return;
    final target = Duration(
      milliseconds:
          (engine.value.duration.inMilliseconds * fraction.clamp(0.0, 1.0))
              .round(),
    );
    await engine.seekTo(target);
    _notify();
  }

  Future<void> commitSeek(double fraction) async {
    final target = Duration(
      milliseconds: (duration.inMilliseconds * fraction.clamp(0.0, 1.0))
          .round(),
    );
    await seekTo(target);
  }

  Future<void> seekTo(Duration target) async {
    final engine = _engine;
    if (_disposed || engine == null || !engine.value.isInitialized) return;
    playbackStatus = PlayerPlaybackStatus.seeking;
    _notify();
    await engine.seekTo(
      ProgressMath.clampPosition(target, engine.value.duration),
    );
    await _persistProgress(forceCloud: true);
    if (!_disposed) {
      playbackStatus = engine.value.isPlaying
          ? PlayerPlaybackStatus.playing
          : PlayerPlaybackStatus.paused;
      _notify();
    }
  }

  Future<bool> changeQuality(VideoQuality quality) async {
    final allowedQualities = _entitlement?.allowedQualities ?? const {};
    final isAllowed =
        quality == VideoQuality.auto || allowedQualities.contains(quality);
    if (_disposed || quality == selectedQuality || !isAllowed) {
      return false;
    }
    final wasPlaying = isPlaying;
    final restorePosition = position;
    selectedQuality = quality;
    final operation = ++_operationId;
    playbackStatus = PlayerPlaybackStatus.loading;
    _notify();
    try {
      await _persistProgress(forceCloud: true);
      await _loadEngine(
        operation: operation,
        positionToRestore: restorePosition,
        autoplay: wasPlaying,
      );
      if (!_disposed) unawaited(HapticFeedback.selectionClick());
      return !_disposed && operation == _operationId;
    } catch (error) {
      if (!_disposed && operation == _operationId) {
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage = error is VideoSourceException
            ? error.message
            : 'تعذر تغيير الجودة.';
        _notify();
      }
      return false;
    }
  }

  void updateEpisodeCatalog(
    List<LectureSummary> catalog, {
    String? activeSectionId,
  }) {
    episodes = List<LectureSummary>.unmodifiable(catalog);
    if (activeSectionId != null && activeSectionId.isNotEmpty) {
      sectionId = activeSectionId;
    }
    _notify();
  }

  Future<void> switchEpisode(
    LectureSummary episode, {
    String? newSectionId,
  }) async {
    if (_disposed || episode.id == lectureId) return;
    final operation = ++_operationId;
    final shouldPlay = isPlaying;
    await _persistProgress(forceCloud: true);
    final previous = _engine;
    previous?.removeListener(_onEngineUpdate);
    _engine = null;
    await previous?.dispose();
    lectureId = episode.id;
    sectionId = newSectionId ?? episode.sectionId ?? sectionId;
    episodeTitle = episode.title;
    episodeThumbnailUrl = episode.thumbnailUrl;
    skipIntroStart = episode.skipIntroStart;
    skipIntroEnd = episode.skipIntroEnd;
    _resumeRecord = null;
    showResumePrompt = false;
    showNextEpisodePrompt = false;
    errorMessage = null;
    playbackStatus = PlayerPlaybackStatus.loading;
    _notify();
    try {
      await _prepareSource(
        operation: operation,
        restoreProgress: true,
        autoplay: shouldPlay,
      );
    } catch (error) {
      if (!_disposed && operation == _operationId) {
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage = error is VideoSourceException
            ? error.message
            : 'تعذر فتح الحلقة.';
        _notify();
      }
    }
  }

  Future<void> nextEpisode() async {
    final next = EpisodeNavigation.nextIndex(
      currentIndex: currentEpisodeIndex,
      count: episodes.length,
    );
    if (next == null) {
      showNextEpisodePrompt = false;
      _notify();
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    await switchEpisode(episodes[next]);
  }

  Future<void> skipIntro() async {
    final target = skipIntroEnd;
    if (!canSkipIntro || target == null) return;
    unawaited(HapticFeedback.selectionClick());
    await seekTo(target);
  }

  Future<void> startOver() async {
    showResumePrompt = false;
    await seekTo(Duration.zero);
    await play();
  }

  Future<void> continueWatching() async {
    showResumePrompt = false;
    await play();
  }

  Future<void> retry() async {
    if (_disposed) return;
    final operation = ++_operationId;
    playbackStatus = PlayerPlaybackStatus.loading;
    errorMessage = null;
    _notify();
    try {
      _entitlement ??= await entitlementService.resolve(
        userId: userId,
        subjectId: subjectId,
      );
      if (_entitlement?.allowed != true) {
        throw VideoSourceException(
          _entitlement?.message ?? 'لا تملك صلاحية المشاهدة.',
        );
      }
      await _prepareSource(
        operation: operation,
        restoreProgress: true,
        autoplay: false,
      );
    } catch (error) {
      if (!_disposed && operation == _operationId) {
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage = error is VideoSourceException
            ? error.message
            : 'تعذر إعادة تشغيل الفيديو.';
        _notify();
      }
    }
  }

  void toggleControls() {
    if (locked) return;
    controlsVisible = !controlsVisible;
    _notify();
  }

  void showControls() {
    if (!locked && !controlsVisible) {
      controlsVisible = true;
      _notify();
    }
  }

  void toggleLock() {
    locked = !locked;
    controlsVisible = !locked;
    _notify();
  }

  Future<void> setFullscreen(bool value) async {
    fullscreen = value;
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    if (!_disposed) _notify();
  }

  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      await _persistProgress(forceCloud: true);
      if (isPlaying) await _engine?.pause();
    }
  }

  Future<void> _persistProgress({required bool forceCloud}) async {
    if (_disposed || _engine == null || duration <= Duration.zero) return;
    final now = DateTime.now();
    if (!forceCloud &&
        now.difference(
              _lastProgressSave ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(seconds: 3)) {
      return;
    }
    _lastProgressSave = now;
    if (forceCloud ||
        now.difference(
              _lastCloudSave ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) >=
            const Duration(seconds: 15)) {
      _lastCloudSave = now;
      final record = _record();
      await playbackRepository.save(record, syncCloud: true);
    } else {
      await playbackRepository.save(_record(), syncCloud: false);
    }
  }

  PlaybackProgressRecord _record() {
    final safePosition = ProgressMath.clampPosition(position, duration);
    return PlaybackProgressRecord(
      userId: userId,
      lectureId: lectureId,
      subjectId: subjectId,
      sectionId: sectionId.isEmpty ? null : sectionId,
      lectureTitle: episodeTitle,
      thumbnailUrl: episodeThumbnailUrl,
      position: safePosition,
      duration: duration,
      progressPercent: ProgressMath.percent(safePosition, duration),
      completed: ProgressMath.isCompleted(safePosition, duration),
      updatedAt: DateTime.now(),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(_persistProgress(forceCloud: true));
    _disposed = true;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _sourceExpiresAt = null;
    _prefetchedSources.clear();
    final engine = _engine;
    engine?.removeListener(_onEngineUpdate);
    unawaited(engine?.dispose() ?? Future<void>.value());
    if (fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );
    }
    playbackStatus = PlayerPlaybackStatus.disposed;
    super.dispose();
  }
}
