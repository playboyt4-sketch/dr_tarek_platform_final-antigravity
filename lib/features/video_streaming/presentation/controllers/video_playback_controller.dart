import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/bunny_playback_headers.dart';
import '../../../subject_navigation/domain/entities/subject_learning_entities.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/services/video_source_resolver.dart';
import '../../domain/entities/playback_entities.dart';
import '../../domain/services/playback_session_coordinator.dart';

/// Pre-tap first-video pointer lookup (Phase 5 fast path).
///
/// Pure lookup of the denormalized `FirstVideoRef` riding the already-loaded
/// lecture list — no network, no authorization semantics. A non-null result
/// only *attempts* the fast lane; the server verdict inside `resolve()`
/// alone decides Full vs Guest, and any rejection falls back to the legacy
/// listing path. Null when the episode is unknown or carries no pointer.
FirstVideoRef? firstVideoForEpisode(
  List<LectureSummary> episodes,
  String lectureId,
) {
  for (final episode in episodes) {
    if (episode.id == lectureId) return episode.firstVideo;
  }
  return null;
}

class VideoPlaybackController extends ChangeNotifier {
  final String userId;
  final String subjectId;
  final VideoSourceGateway sourceResolver;
  final VideoEntitlementGateway entitlementService;
  final PlaybackRepository playbackRepository;

  /// FINAL_DECISIONS §12: self-read of the caller's rolling 24-hour window
  /// (null in tests / when unavailable — all consumers degrade gracefully).
  final WatchWindowGateway? watchWindowGateway;

  /// Max Subject session gateway (null = sessions disabled; every consumer
  /// degrades to the legacy path). Never decides authorization — the server
  /// response alone determines Full vs Guest and session ownership.
  final PlaybackSessionGateway? sessionGateway;

  /// Local device identity supplier for session calls. Defaults to the
  /// shared resolver used by URL issuance so both paths address the same
  /// device. Identity material only, never proof.
  final Future<String> Function()? deviceIdProvider;

  List<LectureSummary> episodes;
  String lectureId;
  String sectionId;
  String episodeTitle;

  /// Display-only live video name from the authoritative resource listing
  /// (`lecture_resources/title`). Adopted whenever the full listing loads
  /// (legacy path + fast-lane background refresh) so the header never
  /// sticks to a stale denormalized `first_video.title`. Never playback
  /// state — safe to refresh mid-playback.
  String? liveVideoTitle;
  String? episodeThumbnailUrl;
  Duration? skipIntroStart;
  Duration? skipIntroEnd;

  /// §12 window snapshot from the last [refreshWatchWindowState] poll.
  String? watchWindowActiveLectureId;
  DateTime? watchWindowExpiresAt;

  /// §12: set when generateBunnySignedUrl refused a DIFFERENT video while
  /// the rolling window is active. Drives the same VideoUpgradePrompt wall
  /// used by the §11 preview cap — surfaced BEFORE playback ever starts.
  DateTime? dailyWindowExpiresAt;

  bool get dailyWindowBlocked =>
      showUpgradePrompt && dailyWindowExpiresAt != null;

  VideoPlayerController? _engine;
  VideoResource? _resource;

  /// Whether the active lecture carries openable documents (PDF/attachment).
  /// Drives the conditional PDF toolbar button (reference design shows PDF
  /// only when a file is attached). Recomputed on every source prepare.
  bool hasDocuments = false;
  VideoEntitlement? _entitlement;
  PlaybackProgressRecord? _resumeRecord;

  /// Active Guest per-lecture cap (FINAL_DECISIONS §11); null =
  /// unlimited playback. Derived from the server-armed resource metadata —
  /// the client NEVER recomputes entitlement, it only enforces.
  Duration? _previewCap;

  /// Messaging-only audience for the active Guest verdict ("guest" =
  /// external Guest → Center-enrollment message; "center" = Center student
  /// on an unauthorized device → device message). Read-only projection of
  /// the server `previewAudience` discriminator; null/unknown preserves the
  /// legacy generic wall. Never authorization logic.
  String? previewAudience;

  /// True while the upgrade wall is up because the Guest verdict carried
  /// zero playable seconds (as opposed to a consumed positive cap or the
  /// rolling-window wall). Drives the audience-specific wall copy.
  bool get isPreviewBlockedAtZero =>
      _previewCap != null &&
      _previewCap == Duration.zero &&
      showUpgradePrompt &&
      !dailyWindowBlocked;

  /// Issuance-side device signal (presentation only): set when
  /// `generateBunnySignedUrl` declared this device Guest for the Subject
  /// (Guest-tier throw with no preview, or a `center` preview audience).
  /// Selects the device wall — never an upgrade CTA, since upgrading
  /// cannot authorize a device. Cleared on every fresh source attempt.
  bool deviceBlocked = false;

  /// Test-only seam: arms the exact wall state reached through
  /// [_loadEngine] (zero-preview verdict) or [_applyFreeWindowWall]
  /// without requiring a video engine. Production code never calls this;
  /// widget tests use it to render each wall variant deterministically.
  @visibleForTesting
  void debugArmUpgradeWall({
    Duration? previewCap,
    String? audience,
    DateTime? windowExpiresAt,
    bool deviceBlocked = false,
  }) {
    _previewCap = previewCap;
    previewAudience = audience;
    dailyWindowExpiresAt = windowExpiresAt;
    this.deviceBlocked = deviceBlocked;
    showUpgradePrompt = true;
  }

  /// Test-only seam: injects an engine whose [VideoPlayerValue] the test
  /// sets directly (e.g. initialized with [Size.zero]) so surface/layout
  /// fallbacks are widget-testable without platform channels. Production
  /// code never calls this.
  @visibleForTesting
  void debugInjectEngine(VideoPlayerController engine) {
    _engine?.removeListener(_onEngineUpdate);
    _engine = engine;
    _engine?.addListener(_onEngineUpdate);
  }
  PlayerPlaybackStatus playbackStatus = PlayerPlaybackStatus.initial;
  VideoQuality selectedQuality = VideoQuality.auto;
  String? errorMessage;
  // Cinematic playback: the student tapped a lecture expecting video only.
  // All chrome (header, controls, sliders, toolbar) stays hidden until the
  // first tap on the surface. Auto-hide after 4s of playback re-hides it.
  bool controlsVisible = false;
  bool locked = false;
  bool fullscreen = false;

  /// Per-video brightness factor (1.0 = unmodified). Used by the right-side
  /// slider on platforms without system brightness control (e.g. web):
  /// applied as a color filter on the video surface only.
  double videoBrightness = 1.0;

  /// Sets the per-video brightness from a 0..1 slider position, mirroring
  /// the reference design mapping (0.2 dim .. 1.5 vivid).
  void setVideoBrightness(double sliderValue) {
    videoBrightness = 0.2 + sliderValue.clamp(0.0, 1.0) * 1.3;
    _notify();
  }
  bool showResumePrompt = false;
  bool showNextEpisodePrompt = false;

  /// FINAL_DECISIONS §11: set when playback hits the per-lecture Public
  /// Free minute cap; the overlay shows the upgrade prompt and play() is
  /// refused until a different (unlocked) episode is opened.
  bool showUpgradePrompt = false;
  bool _disposed = false;
  bool _initializing = false;
  int _operationId = 0;
  // P3 TTF instrumentation: tap-anchored start for the exact
  // time-to-first-frame measurement. Read-only diagnostics only.
  DateTime? _initStartedAt;
  bool _firstFrameLogged = false;  DateTime? _lastProgressSave;
  DateTime? _lastCloudSave;
  DateTime? _sourceExpiresAt;
  DateTime? _bufferingStartedAt;
  // Set once a buffering downgrade has been attempted for the active engine
  // load: every downgrade is a full engine rebuild, so an unguarded trigger
  // re-fires immediately after reload on still-slow networks (reload loop).
  bool _downgradedThisEngine = false;
  bool _refreshingSource = false;
  bool _prefetchingNextEpisode = false;
  final Map<String, ResolvedVideoSource> _prefetchedSources = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Active Max session runtime (ADR-004 follow-up). Held per controller
  /// instance — the controller itself is already Subject-scoped, so no
  /// session state can leak across Subjects. Null on Free/Pro/Guest paths.
  PlaybackSessionCoordinator? _sessionCoordinator;

  /// Set when the server ends our session (takeover/expiry/revocation).
  /// While set, playback stays stopped; only explicit user intent
  /// ([play]) may request a new begin, which the server alone decides.
  /// BLOCKED (Figma): no dedicated takeover-interruption visual state
  /// exists — behavior routes to the existing generic error state below.
  bool _sessionInvalidated = false;

  VideoPlaybackController({
    required this.userId,
    required this.subjectId,
    required this.sourceResolver,
    required this.entitlementService,
    required this.playbackRepository,
    required this.episodes,
    required LectureSummary episode,
    this.watchWindowGateway,
    this.sessionGateway,
    this.deviceIdProvider,
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

  bool get isPlaying => _engine?.value.isPlaying == true;  bool get isBuffering => _engine?.value.isBuffering == true;
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

  /// Second header line: the Video Name from the dashboard.
  /// Preference: live listing title (authoritative, self-heals a stale
  /// denormalized `first_video.title`) → loaded resource → denormalized
  /// pointer (instant, pre-issuance). Null when unset — the header then
  /// shows only the lecture name with no automatic "حلقة X" numbering.
  String? get videoTitle {
    final live = liveVideoTitle?.trim();
    if (live != null && live.isNotEmpty) return live;
    final loaded = _resource?.title.trim();
    if (loaded != null && loaded.isNotEmpty) return loaded;
    return firstVideoForEpisode(episodes, lectureId)?.title;
  }

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
    var stage = 'entitlement';
    // P3 profiling: per-stage wall-clock from tap to first frame. Read the
    // [VIDEO-TIMING] lines in order — the slowest stage is the one to fix.
    final overallStopwatch = Stopwatch()..start();
    _initStartedAt = DateTime.now();
    try {
      // DIAGNOSIS-ONLY: identity + entry context for the failing op below.
      debugPrint(
        '[VIDEO-DIAG] player initialize start userId=$userId subjectId=$subjectId lectureId=$lectureId',
      );
      // Startup latency: entitlement (membership reads) and the lecture
      // resources callable are independent — fire both at once instead of
      // serially so open-to-first-frame costs a single round trip.
      // Phase 5 fast path: when the lecture list already carries the
      // denormalized first-video pointer, the full listing is NOT a
      // startup prerequisite — issuance + entitlement decide everything.
      // The listing still loads lazily for docs/art when the fast lane
      // cannot serve them (see _refreshSupplementalResources).
      final entitlementStopwatch = Stopwatch()..start();
      final entitlementFuture = entitlementService.resolve(
        userId: userId,
        subjectId: subjectId,
      );
      final preknown = firstVideoForEpisode(episodes, lectureId);
      // Malformed pointers (empty id) fall back to the legacy path.
      final bool fastLane =
          preknown != null && preknown.bunnyVideoId.isNotEmpty;
      final resourcesStopwatch = Stopwatch()..start();
      final Future<List<VideoResource>>? resourcesFuture =
          fastLane ? null : sourceResolver.loadResources(lectureId);
      _entitlement = await entitlementFuture;
      debugPrint(
        '[VIDEO-TIMING] stage=entitlement lectureId=$lectureId '
        'elapsedMs=${entitlementStopwatch.elapsedMilliseconds}',
      );
      if (_disposed || operation != _operationId) return;
      if (_entitlement?.allowed != true) {
        // Loser future must not go unobserved.
        unawaited(resourcesFuture?.then<void>((_) {}, onError: (_) {}));
        _applyEntitlementDenial(
          operation,
          fallbackMessage:
              'You do not have permission to watch this video.',
        );
        return;
      }
      stage = 'prepareSource';
      final preloaded = fastLane
          ? null
          : await resourcesFuture!.then((resources) {
              debugPrint(
                '[VIDEO-TIMING] stage=loadResources lectureId=$lectureId '
                'elapsedMs=${resourcesStopwatch.elapsedMilliseconds}',
              );
              return resources;
            });
      await _prepareSource(
        operation: operation,
        restoreProgress: true,
        // Autoplay on open: the student tapped a lecture expecting instant
        // playback. Engine-level autoplay rejections (e.g. browser policy)
        // are swallowed inside _loadEngine so they degrade to paused-ready.
        autoplay: true,
        preloadedResources: preloaded,
        fastVideoRef: fastLane ? preknown : null,
      );
      debugPrint(
        '[VIDEO-TIMING] stage=initializeTotal lectureId=$lectureId '
        'elapsedMs=${overallStopwatch.elapsedMilliseconds}',
      );
    } catch (error) {
      if (!_disposed && operation == _operationId) {
        // DIAGNOSIS-ONLY: full op context for the permission-denied hunt.
        debugPrint(
          '[VIDEO-DIAG] player initialize FAILED stage=$stage userId=$userId subjectId=$subjectId lectureId=$lectureId '
          'errorType=${error.runtimeType} error=$error',
        );
        playbackStatus = PlayerPlaybackStatus.error;
        errorMessage = error is VideoSourceException
            ? error.message
            : 'Could not initialize the video player. [stage=$stage ${error.runtimeType}: $error]';
        _notify();
      }
    } finally {
      _initializing = false;
    }
  }

  /// Pristine per-attempt source state shared by the legacy and fast lanes.
  void _resetSourceState() {
    _resource = null;
    liveVideoTitle = null;
    hasDocuments = false;
    _previewCap = null;
    previewAudience = null;
    deviceBlocked = false;
    // Fresh attempt: clear any previous §12 wall state (§11 state is
    // recomputed below exactly as before — the two gates are independent).
    dailyWindowExpiresAt = null;
    showUpgradePrompt = false;
  }

  /// Fires the restore-progress read for concurrent overlap (D1). The
  /// timing line is preserved; local-fallback tolerance lives in the
  /// repository. Callers join the future where the record is consumed.
  Future<PlaybackProgressRecord?> _fireProgressRead() {
    final resumeStopwatch = Stopwatch()..start();
    return playbackRepository.read(lectureId).then((record) {
      debugPrint(
        '[VIDEO-TIMING] stage=playbackRepositoryRead lectureId=$lectureId '
        'elapsedMs=${resumeStopwatch.elapsedMilliseconds}',
      );
      return record;
    });
  }

  /// Phase 5 fast lane: start playback from the pre-tap first-video pointer
  /// without awaiting the full listing. Authorization is NOT skipped: the
  /// entitlement gate already passed, `resolve()` runs the complete
  /// server-side issuance validation for this exact video, and the Guest
  /// verdict inside its response is enforced in [_loadEngine] exactly like
  /// the listing-stamped cap. Listing-dependent UI (docs button, episode
  /// art) refreshes in the background once playback is authoritative.
  Future<void> _prepareFastSource({
    required int operation,
    required bool restoreProgress,
    required bool autoplay,
    required FirstVideoRef ref,
  }) async {
    final refTitle = ref.title;
    _resource = VideoResource(
      id: ref.resourceId,
      title:
          refTitle != null && refTitle.isNotEmpty ? refTitle : episodeTitle,
      resourceType: 'video',
      bunnyVideoId: ref.bunnyVideoId,
    );
    hasDocuments = false;
    final Future<PlaybackProgressRecord?>? resumeFuture =
        restoreProgress ? _fireProgressRead() : null;
    await _loadEngine(
      operation: operation,
      resumeFuture: resumeFuture,
      autoplay: autoplay,
    );
    unawaited(_refreshSupplementalResources(operation, lectureId));
  }

  /// Background listing refresh for the fast lane: fills in the docs
  /// affordance, live video title, and episode artwork the full listing
  /// would have provided. Never touches playback state (`_resource`,
  /// caps, prompts, resume) — those are already authoritative from
  /// issuance. Stale-guarded by both operation and lecture so episode
  /// switches cannot cross-contaminate.
  Future<void> _refreshSupplementalResources(
    int operation,
    String targetLectureId,
  ) async {
    try {
      final resources = await sourceResolver.loadResources(targetLectureId);
      if (_disposed ||
          operation != _operationId ||
          targetLectureId != lectureId) {
        return;
      }
      hasDocuments = resources.any((item) => item.isDocument);
      final liveVideo = firstPlayableVideo(resources);
      final liveTitle = liveVideo?.title.trim();
      if (liveTitle != null && liveTitle.isNotEmpty) {
        liveVideoTitle = liveTitle;
      }
      final artwork = liveVideo?.thumbnailUrl;
      if (artwork != null &&
          artwork.isNotEmpty &&
          artwork != episodeThumbnailUrl) {
        episodeThumbnailUrl = artwork;
        final index = episodes.indexWhere((item) => item.id == targetLectureId);
        if (index >= 0 && episodes[index].thumbnailUrl != artwork) {
          final updated = [...episodes];
          updated[index] = updated[index].copyWith(thumbnailUrl: artwork);
          episodes = List<LectureSummary>.unmodifiable(updated);
        }
      }
      _notify();
    } catch (_) {
      // Nicety only — playback is already authoritative and unaffected.
    }
  }

  /// FINAL_DECISIONS §12 wall shared by the legacy and fast lanes: a
  /// DIFFERENT video was requested while the rolling window is active.
  /// Surfaced BEFORE playback starts, never mid-playback.
  void _applyFreeWindowWall(FreeWindowBlockedException blocked, int operation) {
    if (_disposed || operation != _operationId) return;
    final expiresMs = blocked.windowExpiresAtMs;
    dailyWindowExpiresAt =
        expiresMs == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresMs);
    errorMessage = null;
    showUpgradePrompt = true;
    playbackStatus = PlayerPlaybackStatus.paused;
    unawaited(refreshWatchWindowState());
    _notify();
  }

  /// Presentation-only entitlement-denial routing (verdicts unchanged —
  /// the allow/deny decision stays in the entitlement service / server):
  /// - missing/inactive per-subject subscription → distinct message, never
  ///   an upsell (the plan may already be correct; Subject Access itself
  ///   may be off);
  /// - genuine plan-tier gap → the upgrade wall (the only wall with a Pro
  ///   CTA);
  /// - anything else → the legacy error state, message untouched.
  void _applyEntitlementDenial(int operation, {required String fallbackMessage}) {
    if (_disposed || operation != _operationId) return;
    final kind = _entitlement?.denialKind;
    if (kind == VideoDenialKind.planUpsell) {
      errorMessage = null;
      showUpgradePrompt = true;
      playbackStatus = PlayerPlaybackStatus.paused;
      _notify();
      return;
    }
    playbackStatus = PlayerPlaybackStatus.error;
    errorMessage = kind == VideoDenialKind.subscriptionInactive
        ? 'ليس لديك اشتراك فعال في هذه المادة.'
        : (_entitlement?.message ?? fallbackMessage);
    _notify();
  }

  /// Issuance-declared device block (Guest tier, no preview for this
  /// lecture). Surfaces the device wall — contact the administration,
  /// never an upgrade CTA. Reached only from the exact server sentinel
  /// mapped to [DeviceNotAuthorizedException]; every other issuance
  /// failure keeps its existing path.
  void _applyDeviceBlockedWall(int operation) {
    if (_disposed || operation != _operationId) return;
    errorMessage = null;
    deviceBlocked = true;
    showUpgradePrompt = true;
    playbackStatus = PlayerPlaybackStatus.paused;
    _notify();
  }

  Future<void> _prepareSource({
    required int operation,
    required bool restoreProgress,
    required bool autoplay,
    List<VideoResource>? preloadedResources,
    FirstVideoRef? fastVideoRef,
  }) async {
    _resetSourceState();
    // Phase 5 fast lane: a pre-tap pointer with no preloaded listing starts
    // playback without the full-listing round trip. The pointer authorizes
    // nothing — issuance validates server-side; any rejection falls back
    // to the authoritative legacy listing path with pristine state.
    if (preloadedResources == null && fastVideoRef != null) {
      try {
        await _prepareFastSource(
          operation: operation,
          restoreProgress: restoreProgress,
          autoplay: autoplay,
          ref: fastVideoRef,
        );
        return;
      } on FreeWindowBlockedException catch (blocked) {
        _applyFreeWindowWall(blocked, operation);
        return;
      } on DeviceNotAuthorizedException {
        _applyDeviceBlockedWall(operation);
        return;
      } catch (_) {
        _resetSourceState();
      }
    }
    final resources =
        preloadedResources ?? await sourceResolver.loadResources(lectureId);
    if (_disposed || operation != _operationId) return;
    hasDocuments = resources.any((item) => item.isDocument);
    // Canonical fallback selection (not a security boundary — the server
    // filtered and ordered the listing). Null when nothing is playable.
    final video = firstPlayableVideo(resources);
    if (video == null) {
      throw const VideoSourceException(
        'No published video source found for this lecture.',
      );
    }
    _resource = video;
    final legacyTitle = video.title.trim();
    if (legacyTitle.isNotEmpty) liveVideoTitle = legacyTitle;
    // Storage-delivery Fix 2: the callable now returns a SERVER-RESOLVED,
    // short-lived thumbnail URL (Firebase signed URL or Bunny token URL).
    // Adopt it for the active episode so episode cards and progress
    // records render a real image even when the lectures-collection
    // thumbnail is unset. Presentation never branches on the provider.
    final resolvedThumbnail = _resource!.thumbnailUrl;
    if (resolvedThumbnail != null && resolvedThumbnail.isNotEmpty) {
      episodeThumbnailUrl = resolvedThumbnail;
      final index = episodes.indexWhere((item) => item.id == lectureId);
      if (index >= 0 && episodes[index].thumbnailUrl != resolvedThumbnail) {
        final updated = [...episodes];
        updated[index] = updated[index].copyWith(thumbnailUrl: resolvedThumbnail);
        episodes = List<LectureSummary>.unmodifiable(updated);
      }
    }
    // Per-lecture Guest preview cap (FINAL_DECISIONS §11). The server already
    // reconciled the lecture minutes against the plan's
    // video.preview_duration default; here we only read the verdict.
    _previewCap = PreviewCapPolicy.capFor(_resource);
    previewAudience = _resource?.previewAudience;
    showUpgradePrompt =
        _previewCap != null && _previewCap == Duration.zero;

    // D1 overlap (shared helper): the restore-progress read runs
    // concurrently with source resolution and is joined in _loadEngine.
    final Future<PlaybackProgressRecord?>? resumeFuture =
        restoreProgress ? _fireProgressRead() : null;

    try {
      await _loadEngine(
        operation: operation,
        resumeFuture: resumeFuture,
        autoplay: autoplay,
      );
    } on FreeWindowBlockedException catch (blocked) {
      _applyFreeWindowWall(blocked, operation);
      return;
    } on DeviceNotAuthorizedException {
      _applyDeviceBlockedWall(operation);
      return;
    }
    unawaited(refreshWatchWindowState());
  }

  /// Best-effort §12 window snapshot for UI niceties (countdown text,
  /// locked badges on other episode cards). Never throws; non-Center-Free
  /// callers simply get an active:false verdict from the callable.
  Future<void> refreshWatchWindowState() async {
    final gateway = watchWindowGateway;
    if (_disposed || gateway == null) return;
    try {
      final snapshot = await gateway.load();
      if (_disposed) return;
      watchWindowActiveLectureId = snapshot.activeLectureId;
      watchWindowExpiresAt = snapshot.expiresAt;
      _notify();
    } catch (_) {
      // Nicety only — must never disturb playback.
    }
  }

  /// Drops any adopted session (episode switch, quality reload, retry).
  /// Stops its heartbeat; resuming requires a fresh server verdict.
  void _dropSession() {
    _sessionCoordinator?.dispose();
    _sessionCoordinator = null;
    _sessionInvalidated = false;
  }

  Future<void> _loadEngine({
    required int operation,
    Duration? positionToRestore,
    Future<PlaybackProgressRecord?>? resumeFuture,
    required bool autoplay,
  }) async {
    final resource = _resource;
    if (resource == null) {
      throw const VideoSourceException('Video source unavailable.');
    }
    _dropSession();
    // Fresh engine attempt: exactly one firstFrame line will be logged for
    // this initialization (see _onEngineUpdate). Buffering/downgrade state
    // restarts here too so a previous stall cannot trigger an immediate
    // downgrade of the new attempt.
    _firstFrameLogged = false;
    _bufferingStartedAt = null;
    _downgradedThisEngine = false;
    _prefetchedSources.removeWhere((_, source) =>
        source.expiresAt.difference(DateTime.now()) <
        const Duration(seconds: 30));
    final cacheKey = _sourceCacheKey(lectureId, selectedQuality);
    final cachedSource = _prefetchedSources.remove(cacheKey);
    final resolveStopwatch = Stopwatch()..start();
    final source =
        cachedSource != null &&
            cachedSource.expiresAt.difference(DateTime.now()) >
                const Duration(seconds: 30)
        ? cachedSource
        : await sourceResolver.resolve(
            resource: resource,
            quality: selectedQuality,
            subjectId: subjectId,
            // Identity fix: the route lecture is the authorization
            // identity (the video file only selects the bytes).
            lectureId: lectureId,
          );
    debugPrint(
      '[VIDEO-TIMING] stage=signedUrl lectureId=$lectureId cached=${cachedSource != null} '
      'elapsedMs=${resolveStopwatch.elapsedMilliseconds}',
    );
    // Issuance-verdict diagnostics (read-only): distinguishes a Full
    // issuance from a Guest-tier preview verdict (device-blocked) and from
    // denials, which throw before reaching this line.
    debugPrint(
      '[VIDEO-DIAG] issuance verdict lectureId=$lectureId '
      'previewLimitSeconds=${source.previewLimitSeconds} '
      'previewAudience=${source.previewAudience} '
      'hasSession=${source.hasActiveSession}',
    );
    // A `center` preview audience means the server resolved this device to
    // the Guest tier for the Subject: remember it for wall selection only
    // (a consumed positive cap must render the device wall, not an upsell).
    if (source.previewAudience == kPreviewAudienceCenter) {
      deviceBlocked = true;
    }
    _sourceExpiresAt = source.expiresAt;
    if (_disposed || operation != _operationId) return;

    // Issuance-echoed Guest verdict (Phase 5): the server attaches
    // previewLimitSeconds on Guest issuance only. Enforce it exactly like
    // the listing-stamped cap (PreviewCapPolicy.capFor semantics). Absent
    // on Full — no-op. On the legacy path the values are identical (same
    // server verdict for the same student+lecture), so the shared
    // _loadEngine callers (quality change, silent refresh) are unaffected.
    if (source.previewLimitSeconds != null) {
      final previewSeconds = source.previewLimitSeconds!;
      _previewCap = previewSeconds <= 0
          ? Duration.zero
          : Duration(seconds: previewSeconds);
      // A missing discriminator (older backend) must not wipe the
      // listing-stamped audience adopted above — messaging falls back.
      if (source.previewAudience != null) {
        previewAudience = source.previewAudience;
      }
      showUpgradePrompt = _previewCap == Duration.zero;
    }

    // Max session adoption (ADR-004 follow-up): only when the server
    // attached a session (2-allowance Subject, Full tier) and this is not
    // a Guest preview. The server position below overrides any stale
    // local restore point — it was just computed from persisted progress.
    PlaybackSession? adoptedSession;
    if (source.hasActiveSession &&
        _previewCap == null &&
        sessionGateway != null) {
      final deviceId = await resolveLocalDeviceId(
        override: deviceIdProvider,
      );
      if (_disposed || operation != _operationId) return;
      final coordinator = PlaybackSessionCoordinator(
        gateway: sessionGateway!,
        studentId: userId,
        subjectId: subjectId,
        deviceId: deviceId,
      );
      adoptedSession = PlaybackSession(
        subjectId: subjectId,
        lectureId: lectureId,
        videoId: resource.bunnyVideoId,
        sessionToken: source.sessionToken!,
        position: Duration(
          seconds: (source.sessionPositionSeconds ?? 0).clamp(0, 24 * 60 * 60),
        ),
        takeover: source.sessionTakeover,
        heartbeatInterval: source.heartbeatIntervalMs != null &&
                source.heartbeatIntervalMs! > 0
            ? Duration(milliseconds: source.heartbeatIntervalMs!)
            : const Duration(seconds: 30),
      );
      coordinator.adopt(adoptedSession);
      _sessionCoordinator = coordinator;
    }

    final previous = _engine;
    previous?.removeListener(_onEngineUpdate);
    _engine = null;
    await previous?.dispose();

    final next = VideoPlayerController.networkUrl(
      source.url,
      httpHeaders: bunnyPlaybackHttpHeaders,
      formatHint: source.url.path.toLowerCase().contains('.m3u8') ||
              source.url.toString().toLowerCase().contains('.m3u8')
          ? VideoFormat.hls
          : null,
    );
    _engine = next;
    next.addListener(_onEngineUpdate);
    final engineStopwatch = Stopwatch()..start();
    final initStart = _initStartedAt;
    if (initStart != null) {
      debugPrint(
        '[VIDEO-TIMING] stage=engineInitStart lectureId=$lectureId '
        'elapsedSinceInitMs=${DateTime.now().difference(initStart).inMilliseconds}',
      );
    }
    await next.initialize();
    debugPrint(
      '[VIDEO-TIMING] stage=engineInitialize lectureId=$lectureId '
      'elapsedMs=${engineStopwatch.elapsedMilliseconds}',
    );
    if (_disposed || operation != _operationId) {
      await next.dispose();
      return;
    }
    // D1 join: the restore-progress read overlapped resolve() above, so this
    // usually completes instantly. Same record, same prompt flag, same
    // restore position as the serial path — set before the ready
    // notification below, so observers see one consistent update.
    // Other _loadEngine callers pass no future and are unaffected.
    PlaybackProgressRecord? resumeRecord;
    if (resumeFuture != null) {
      try {
        resumeRecord = await resumeFuture;
      } catch (_) {
        // Preserve the serial path's propagation: a restore-read failure
        // surfaces from startup identically (the just-built engine is
        // disposed first — at that point it did not exist yet).
        await next.dispose();
        rethrow;
      }
      if (_disposed || operation != _operationId) {
        await next.dispose();
        return;
      }
      _resumeRecord = resumeRecord;
      showResumePrompt =
          ProgressMath.resumeAction(resumeRecord) ==
          ResumeAction.continueWatching;
    }
    final effectiveRestore = adoptedSession != null
        ? adoptedSession.position
        : resumeRecord?.position ?? positionToRestore;
    if (effectiveRestore != null && effectiveRestore > Duration.zero) {
      await next.seekTo(
        ProgressMath.clampPosition(effectiveRestore, next.value.duration),
      );
    }
    playbackStatus = PlayerPlaybackStatus.ready;
    errorMessage = null;
    _notify();
    final coordinator = _sessionCoordinator;
    if (coordinator != null) {
      coordinator.startHeartbeat(
        positionProvider: () => position,
        onInvalidated: () => _onSessionInvalidated(),
      );
      // Fail fast on stale (e.g. prefetched) tokens instead of waiting
      // for the first interval tick.
      unawaited(coordinator.beatNow());
    }
    if (autoplay) {
      // Autoplay must never fail the whole load: browsers (web) and OS
      // policies can reject programmatic play without a user gesture.
      // A rejection degrades to paused-ready; the student taps play once.
      try {
        await play();
      } catch (_) {
        if (!_disposed && operation == _operationId) {
          playbackStatus = PlayerPlaybackStatus.paused;
          _notify();
        }
      }
    }
    unawaited(prefetchNextEpisode());
  }

  /// Server ended our session (takeover by the other authorized device,
  /// expiry, or revocation). Stop protected playback immediately, keep the
  /// latest local position, and stay stopped: no silent rebind, no retry
  /// loop. Only explicit user intent ([play]) may request a new begin.
  Future<void> _onSessionInvalidated() async {
    if (_disposed) return;
    _sessionInvalidated = true;
    final engine = _engine;
    if (engine != null && engine.value.isPlaying) {
      await engine.pause();
    }
    await _persistProgress(forceCloud: true);
    playbackStatus = PlayerPlaybackStatus.error;
    // Existing generic error state (no invented copy/layout).
    // BLOCKED (Figma): dedicated takeover-interruption visual state.
    errorMessage = 'A playback error occurred. Please retry.';
    _notify();
  }

  /// Explicit user-intent re-begin after invalidation. Returns true when
  /// the server grants a fresh session (which may itself take over the
  /// other device — symmetric by design).
  Future<bool> _beginAfterInvalidation() async {
    final coordinator = _sessionCoordinator;
    final resource = _resource;
    if (coordinator == null || resource == null) return false;
    try {
      final session = await coordinator.begin(
        lectureId: lectureId,
        videoId: resource.bunnyVideoId,
      );
      _sessionInvalidated = false;
      errorMessage = null;
      await _engine?.seekTo(
        ProgressMath.clampPosition(
          session.position,
          _engine?.value.duration ?? session.position,
        ),
      );
      coordinator.startHeartbeat(
        positionProvider: () => position,
        onInvalidated: () => _onSessionInvalidated(),
      );
      _notify();
      return true;
    } on PlaybackSessionInvalidatedException {
      return false;
    } on PlaybackSessionTransportException {
      return false;
    }
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
      // §12: never mint (or cache) a signed URL the window will refuse —
      // the switch path walls from the snapshot instead.
      if (await _windowSnapshotBlocking(nextEpisode.id) != null) return;
      final resources = await sourceResolver.loadResources(nextEpisode.id);
      final resource = firstPlayableVideo(resources);
      if (resource == null || _disposed) return;
      final quality = selectedQuality;
      final source = await sourceResolver.resolve(
        resource: resource,
        quality: quality,
        subjectId: subjectId,
        // Prefetched bytes belong to the NEXT episode: assert its lecture
        // so the cached URL carries the correct authorization identity.
        lectureId: nextEpisode.id,
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
    // Exact time-to-first-frame: first observed playing event per engine
    // initialization. Logged once; behavior-neutral (read-only timestamp).
    if (!_firstFrameLogged && value.isPlaying) {
      _firstFrameLogged = true;
      final initStart = _initStartedAt;
      debugPrint(
        '[VIDEO-TIMING] stage=firstFrame lectureId=$lectureId '
        'tapToFirstFrameMs=${initStart == null ? -1 : DateTime.now().difference(initStart).inMilliseconds}',
      );
    }
    if (value.hasError) {
      playbackStatus = PlayerPlaybackStatus.error;
      errorMessage = 'A playback error occurred. Please retry.';
      _sessionCoordinator?.stopHeartbeat();
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
      _sessionCoordinator?.stopHeartbeat();
      if (!showNextEpisodePrompt) {
        showNextEpisodePrompt = true;
        unawaited(_persistProgress(forceCloud: true));
      }
    } else {
      playbackStatus = PlayerPlaybackStatus.paused;
    }

    // FINAL_DECISIONS §11 enforcement: stop playback the moment the
    // per-lecture allowed minutes are consumed and surface the upgrade
    // prompt. Position-based (not wall-clock) so buffering/pauses are fair.
    if (_previewCap != null &&
        PreviewCapPolicy.shouldStop(value.position, _previewCap)) {
      unawaited(_enforcePreviewCap());
      return;
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
    if (_disposed ||
        _refreshingSource ||
        _downgradedThisEngine ||
        _entitlement == null) {
      return;
    }
    // Startup-stall guard (TTFF fix): never rebuild the engine for buffering
    // observed BEFORE the first frame. On slow networks the initial HLS
    // attach + manifest + first segments can buffer >8s; downgrading there
    // disposes the initializing engine and starts a second signed-URL +
    // initialize cycle (2x engine init, 2x loading). Post-playback stalls
    // (after first frame) still downgrade exactly once per engine load.
    if (!_firstFrameLogged) return;
    final activeEngine = _engine;
    if (activeEngine == null || !activeEngine.value.isInitialized) return;
    // `auto` (rank 0) means the server served the highest permitted
    // rendition, so stepping down must reference the top of the allowed set
    // — otherwise the filter below is empty and the default selection can
    // never recover from sustained buffering.
    final allowed = _entitlement!.allowedQualities;
    final referenceRank = selectedQuality == VideoQuality.auto
        ? allowed.fold<int>(
            0,
            (max, quality) => quality.rank > max ? quality.rank : max,
          )
        : selectedQuality.rank;
    final lower =
        allowed.where((quality) => quality.rank < referenceRank).toList()
          ..sort((left, right) => right.rank.compareTo(left.rank));
    if (lower.isEmpty) return;
    _downgradedThisEngine = true;
    await changeQuality(lower.first);
  }

  /// Stops playback at the Guest preview cap and shows the upgrade prompt.
  Future<void> _enforcePreviewCap() async {
    final engine = _engine;
    if (engine != null && engine.value.isPlaying) {
      await engine.pause();
    }
    showUpgradePrompt = true;
    if (_previewCap == Duration.zero) {
      // Nothing allowed at all — treat like a locked lecture.
      playbackStatus = PlayerPlaybackStatus.paused;
    } else {
      playbackStatus = PlayerPlaybackStatus.paused;
    }
    unawaited(_persistProgress(forceCloud: true));
    _notify();
  }

  Future<void> play() async {
    if (_sessionInvalidated) {
      // Explicit user intent after a server invalidation: one begin
      // attempt, decided by the server alone. Failure stays stopped.
      final rebegun = await _beginAfterInvalidation();
      if (!rebegun || _disposed) return;
    }
    final engine = _engine;
    if (_disposed ||
        engine == null ||
        !engine.value.isInitialized ||
        showUpgradePrompt) {
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
    // Preview caps also fence seeking — no skipping past the wall (§11).
    final fenced = PreviewCapPolicy.clampSeek(target, _previewCap);
    await engine.seekTo(
      ProgressMath.clampPosition(fenced, engine.value.duration),
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
    _prefetchedSources.removeWhere((key, _) => key.startsWith('$lectureId:'));
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
            : 'Could not change the video quality.';
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

  /// §12 pre-check shared by [switchEpisode] and [prefetchNextEpisode]:
  /// returns the live window snapshot when it blocks [targetLectureId]
  /// (active window owned by a DIFFERENT lecture), null otherwise.
  /// Read-only projection of the server verdict (`getVideoWatchWindow`) —
  /// never authorization logic; the issuance callable re-validates anyway.
  /// Fail-open (null) on any error so a nicety read can never strand playback.
  Future<WatchWindowSnapshot?> _windowSnapshotBlocking(
    String targetLectureId,
  ) async {
    final gateway = watchWindowGateway;
    if (_disposed || gateway == null) return null;
    try {
      final snapshot = await gateway.load();
      if (_disposed) return null;
      watchWindowActiveLectureId = snapshot.activeLectureId;
      watchWindowExpiresAt = snapshot.expiresAt;
      if (!snapshot.active) return null;
      final activeId = snapshot.activeLectureId;
      if (activeId == null || activeId.isEmpty) return null;
      final expires = snapshot.expiresAt;
      if (expires != null && !expires.isAfter(DateTime.now())) return null;
      return activeId != targetLectureId ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> switchEpisode(
    LectureSummary episode, {
    String? newSectionId,
  }) async {
    if (_disposed || episode.id == lectureId) return;
    final operation = ++_operationId;
    // §12 pre-check (FINAL_DECISIONS): never tear down the current engine
    // for a switch the server window will refuse — wall immediately for
    // the target instead (no wasted issuance, no playback flicker).
    final blocking = await _windowSnapshotBlocking(episode.id);
    if (blocking != null) {
      if (_disposed || operation != _operationId) return;
      _dropSession();
      _prefetchedSources.clear();
      await _persistProgress(forceCloud: true);
      final previous = _engine;
      previous?.removeListener(_onEngineUpdate);
      _engine = null;
      await previous?.dispose();
      lectureId = episode.id;
      sectionId = episode.sectionId ?? sectionId;
      episodeTitle = episode.title;
      episodeThumbnailUrl = episode.thumbnailUrl;
      liveVideoTitle = null;
      skipIntroStart = episode.skipIntroStart;
      skipIntroEnd = episode.skipIntroEnd;
      _resumeRecord = null;
      showResumePrompt = false;
      showNextEpisodePrompt = false;
      deviceBlocked = false;
      _previewCap = null;
      errorMessage = null;
      playbackStatus = PlayerPlaybackStatus.loading;
      _notify();
      _applyFreeWindowWall(
        FreeWindowBlockedException(
          message: 'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة.',
          windowExpiresAtMs:
              blocking.expiresAt?.millisecondsSinceEpoch,
          activeLectureId: blocking.activeLectureId,
        ),
        operation,
      );
      return;
    }
    _dropSession();
    _prefetchedSources.clear();
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
    liveVideoTitle = null;
    skipIntroStart = episode.skipIntroStart;
    skipIntroEnd = episode.skipIntroEnd;
    _resumeRecord = null;
    showResumePrompt = false;
    showNextEpisodePrompt = false;
    showUpgradePrompt = false;
    deviceBlocked = false;
    _previewCap = null; // recomputed by _prepareSource
    errorMessage = null;
    playbackStatus = PlayerPlaybackStatus.loading;
    _notify();
    try {
      // Entitlement-first gate (parity with initialize/retry): the active
      // subject's subscription is confirmed BEFORE any signed-URL issuance
      // below, so an episode switch never mints a Bunny URL for a student
      // who will be blocked anyway. The server re-validates on issuance
      // regardless — this only avoids the wasted call.
      _entitlement = await entitlementService.resolve(
        userId: userId,
        subjectId: subjectId,
      );
      if (_entitlement?.allowed != true) {
        _applyEntitlementDenial(
          operation,
          fallbackMessage: 'You do not have permission to watch.',
        );
        return;
      }
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
            : 'Could not open this episode.';
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
    showUpgradePrompt = false; // recomputed by _prepareSource
    deviceBlocked = false;
    _initStartedAt = DateTime.now();
    _notify();
    try {
      _entitlement ??= await entitlementService.resolve(
        userId: userId,
        subjectId: subjectId,
      );
      if (_entitlement?.allowed != true) {
        _applyEntitlementDenial(
          operation,
          fallbackMessage: 'You do not have permission to watch.',
        );
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
            : 'Could not restart the video. [${error.runtimeType}: $error]';
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
    // The flag itself must ALWAYS apply (it drives the immersive layout);
    // platform calls are individually best-effort because the web
    // orientation lock can reject without a user gesture — previously that
    // rejection aborted the whole call and fullscreen never engaged.
    fullscreen = value;
    try {
      if (value) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
    try {
      if (value) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    } catch (_) {}
    if (!_disposed) _notify();
  }

  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      await _persistProgress(forceCloud: true);
      if (isPlaying) await _engine?.pause();
    } else if (state == AppLifecycleState.resumed) {
      // Reconnection/foreground: validate the server session before any
      // continuation. A rejection runs the standard invalidation path.
      final coordinator = _sessionCoordinator;
      if (coordinator != null && coordinator.hasLiveSession && !_disposed) {
        unawaited(coordinator.beatNow());
      }
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
    _dropSession();
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
