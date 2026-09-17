import 'dart:async';

import '../../data/services/video_source_resolver.dart';
import '../entities/playback_entities.dart';

/// Maximum consecutive transport failures tolerated before the coordinator
/// surfaces the outage (it still never invalidates on transport errors —
/// only a server terminal verdict invalidates).
const int kMaxHeartbeatTransportFailures = 3;

/// Subject-scoped Max playback-session lifecycle (ADR-004 follow-up).
///
/// Pure-Dart owner of one Student + Subject session: explicit begin,
/// periodic heartbeat while active, and fail-closed invalidation. The
/// coordinator never decides authorization — every state transition is a
/// projection of a server verdict. No timers survive [dispose], and no
/// invalidation is ever retried automatically: continuation after
/// invalidation requires a new explicit [begin] (user intent), which the
/// server alone decides.
///
/// One instance per Subject playback context. Instance state must never be
/// shared across Subjects (see [subjectId]).
/// Injectable periodic-timer factory (defaults to [Timer.periodic]).
/// Tests substitute a manual timer; production uses the real clock.
typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer) callback,
);

class PlaybackSessionCoordinator {
  PlaybackSessionCoordinator({
    required PlaybackSessionGateway gateway,
    required String studentId,
    required String subjectId,
    required String deviceId,
    HeartbeatTimerFactory? timerFactory,
  })  : _gateway = gateway,
        _studentId = studentId,
        _subjectId = subjectId,
        _deviceId = deviceId,
        _timerFactory = timerFactory ?? Timer.periodic;

  final PlaybackSessionGateway _gateway;
  final String _studentId;
  final String _subjectId;
  final String _deviceId;
  final HeartbeatTimerFactory _timerFactory;

  String get subjectId => _subjectId;

  PlaybackSession? _session;
  PlaybackSessionState _state = PlaybackSessionState.none;
  Timer? _heartbeatTimer;
  bool _beating = false;
  bool _disposed = false;
  int _transportFailures = 0;
  Duration? _lastKnownPosition;
  Future<void> Function()? _onInvalidated;

  PlaybackSession? get session => _session;
  PlaybackSessionState get state => _state;
  bool get hasLiveSession =>
      _session != null && _state == PlaybackSessionState.active;
  bool get hasActiveHeartbeat => _heartbeatTimer?.isActive == true;
  int get transportFailures => _transportFailures;
  Duration? get lastKnownPosition => _lastKnownPosition;
  bool get isDisposed => _disposed;

  /// Explicit user-intent begin (or re-begin after invalidation). The server
  /// decides Full vs Guest, takeover, token, and resume position.
  Future<PlaybackSession> begin({String? lectureId, String? videoId}) async {
    _throwIfDisposed();
    try {
      final session = await _gateway.begin(
        studentId: _studentId,
        subjectId: _subjectId,
        deviceId: _deviceId,
        lectureId: lectureId,
        videoId: videoId,
      );
      _adopt(session);
      return session;
    } on PlaybackSessionInvalidatedException {
      _state = PlaybackSessionState.invalid;
      rethrow;
    }
  }

  /// Adopts a server-issued session obtained alongside URL issuance
  /// (same-device begin is idempotent server-side, so adoption never
  /// creates a second session).
  void adopt(PlaybackSession session) {
    _throwIfDisposed();
    if (session.subjectId != _subjectId) return;
    _adopt(session);
  }

  void _adopt(PlaybackSession session) {
    _session = session;
    _state = PlaybackSessionState.active;
    _transportFailures = 0;
    _lastKnownPosition = session.position;
  }

  /// Starts the single heartbeat timer. Calling twice never creates a
  /// second timer. [positionProvider] supplies the live engine position;
  /// [onInvalidated] runs once when the server ends the session.
  void startHeartbeat({
    required Duration Function() positionProvider,
    required Future<void> Function() onInvalidated,
  }) {
    _throwIfDisposed();
    if (_session == null) return;
    _positionProvider = positionProvider;
    _onInvalidated = onInvalidated;
    if (_heartbeatTimer?.isActive == true) return;
    final interval = _session!.heartbeatInterval;
    _heartbeatTimer = _timerFactory(interval, (_) {
      unawaited(beatNow());
    });
  }

  Duration Function()? _positionProvider;

  /// One heartbeat round-trip. Returns true while the session stays live.
  /// Terminal server verdicts cancel the timer permanently and report
  /// false exactly once; transport errors are counted and retried on the
  /// next tick without invalidating.
  Future<bool> beatNow({Duration? position}) async {
    final session = _session;
    if (_disposed || session == null || _state != PlaybackSessionState.active) {
      return false;
    }
    if (_beating) return true;
    _beating = true;
    try {
      final reported = position ?? _positionProvider?.call() ?? session.position;
      final result = await _gateway.heartbeat(
        studentId: _studentId,
        subjectId: _subjectId,
        deviceId: _deviceId,
        sessionToken: session.sessionToken,
        position: reported,
      );
      _lastKnownPosition = result.position;
      _session = session.copyWith(position: result.position);
      _transportFailures = 0;
      return true;
    } on PlaybackSessionInvalidatedException {
      _lastKnownPosition =
          position ?? _positionProvider?.call() ?? _lastKnownPosition;
      _state = _isLeasePast() ? PlaybackSessionState.expired : PlaybackSessionState.superseded;
      _cancelTimer();
      final callback = _onInvalidated;
      _onInvalidated = null;
      if (callback != null) await callback();
      return false;
    } on PlaybackSessionTransportException {
      _transportFailures++;
      return _state == PlaybackSessionState.active;
    } finally {
      _beating = false;
    }
  }

  bool _isLeasePast() {
    final lease = _session?.leaseExpiresAt;
    return lease != null && DateTime.now().isAfter(lease);
  }

  /// Stops heartbeats without invalidating (pause, episode switch,
  /// completion). The adopted token is dropped; resuming requires begin.
  void stopHeartbeat() {
    _cancelTimer();
  }

  void _cancelTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _throwIfDisposed() {
    if (_disposed) throw StateError('PlaybackSessionCoordinator is disposed.');
  }

  void dispose() {
    if (_disposed) return;
    _cancelTimer();
    _onInvalidated = null;
    _positionProvider = null;
    _disposed = true;
  }
}
