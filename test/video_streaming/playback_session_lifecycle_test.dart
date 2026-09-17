import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/services/playback_session_coordinator.dart';

/// Scripted fake gateway: per-subject token registry with server-like
/// semantics (takeover rotates tokens, revoked subjects reject everything).
class _FakeSessionGateway implements PlaybackSessionGateway {
  final Map<String, String> liveTokens = {};
  final Map<String, String> tokenOwners = {};
  final Map<String, int> positions = {};
  final Set<String> revokedSubjects = {};
  final List<String> calls = [];
  int beginCalls = 0;
  int heartbeatCalls = 0;
  Duration positionToReturn = Duration.zero;

  @override
  Future<PlaybackSession> begin({
    required String studentId,
    required String subjectId,
    required String deviceId,
    String? lectureId,
    String? videoId,
  }) async {
    beginCalls++;
    calls.add('begin:$subjectId:$deviceId');
    if (revokedSubjects.contains(subjectId)) {
      throw const PlaybackSessionInvalidatedException('denied');
    }
    // Same-device re-begin refreshes the live token (server behavior);
    // a different device rotates it (takeover).
    final previous = liveTokens[subjectId];
    final sameOwner = previous != null && tokenOwners[subjectId] == deviceId;
    final token = sameOwner
        ? previous
        : 'tok-${subjectId.hashCode}-${deviceId.hashCode}-$beginCalls';
    liveTokens[subjectId] = token;
    tokenOwners[subjectId] = deviceId;
    return PlaybackSession(
      subjectId: subjectId,
      lectureId: lectureId,
      videoId: videoId,
      sessionToken: token,
      position: positionToReturn,
      takeover: previous != null && !sameOwner,
    );
  }

  @override
  Future<HeartbeatResult> heartbeat({
    required String studentId,
    required String subjectId,
    required String deviceId,
    required String sessionToken,
    required Duration position,
  }) async {
    heartbeatCalls++;
    calls.add('beat:$subjectId:$deviceId');
    if (revokedSubjects.contains(subjectId) ||
        liveTokens[subjectId] != sessionToken) {
      throw const PlaybackSessionInvalidatedException('stale');
    }
    positions[subjectId] = position.inSeconds;
    return HeartbeatResult(position: position, leaseExpiresAt: null);
  }
}

PlaybackSessionCoordinator _coordinator(
  PlaybackSessionGateway gateway, {
  String subjectId = 'sub-A',
  String deviceId = 'dev-A',
  HeartbeatTimerFactory? timerFactory,
}) {
  return PlaybackSessionCoordinator(
    gateway: gateway,
    studentId: 'student-1',
    subjectId: subjectId,
    deviceId: deviceId,
    timerFactory: timerFactory,
  );
}

/// Manual controllable timer for deterministic heartbeat tests.
class _ManualTimer implements Timer {
  _ManualTimer(this._callback);
  final void Function(Timer)? _callback;
  bool _active = true;
  int fireCount = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => fireCount;

  void fire() {
    if (!_active) return;
    fireCount++;
    _callback?.call(this);
  }

  @override
  void cancel() {
    _active = false;
  }
}

class _ManualTimerFactory {
  final List<_ManualTimer> created = [];

  Timer call(Duration duration, void Function(Timer) callback) {
    final timer = _ManualTimer(callback);
    created.add(timer);
    return timer;
  }
}

void main() {
  group('PlaybackSession entity (server payloads only)', () {
    test('1) begin payload yields token, position, takeover', () {
      final session = PlaybackSession.fromBeginPayload(
        subjectId: 'sub-A',
        lectureId: 'lec-1',
        data: {
          'sessionToken': 'tok-1',
          'positionSeconds': 123,
          'takeover': true,
          'leaseExpiresAtMs': 999,
          'heartbeatIntervalMs': 30000,
        },
      )!;
      expect(session.sessionToken, 'tok-1');
      expect(session.position, const Duration(seconds: 123));
      expect(session.takeover, isTrue);
      expect(session.state, PlaybackSessionState.active);
    });

    test('12) payload without token means no session (Free/Pro/Guest path)',
        () {
      expect(
        PlaybackSession.fromBeginPayload(
          subjectId: 'sub-A',
          data: {'positionSeconds': 10},
        ),
        isNull,
      );
      final source = ResolvedVideoSource(
        url: Uri.parse('https://example.com/v.m3u8'),
        expiresAt: DateTime.now(),
        selectedQuality: VideoQuality.auto,
      );
      expect(source.hasActiveSession, isFalse);
    });

    test('heartbeat payload parses position', () {
      final result = HeartbeatResult.fromPayload({
        'positionSeconds': 77,
        'leaseExpiresAtMs': 1000,
      });
      expect(result.position, const Duration(seconds: 77));
    });
  });

  group('mapSessionGatewayError', () {
    test('terminal codes invalidate; transport codes retry', () {
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'not-found',
        'failed-precondition'
      ]) {
        expect(mapSessionGatewayError(code, 'x'),
            isA<PlaybackSessionInvalidatedException>());
      }
      for (final code in ['unavailable', 'deadline-exceeded', 'internal']) {
        expect(mapSessionGatewayError(code, 'x'),
            isA<PlaybackSessionTransportException>());
      }
    });
  });

  group('PlaybackSessionCoordinator lifecycle', () {
    test('1) begin stores server token and state', () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway);
      final session = await coordinator.begin(lectureId: 'lec-1');
      expect(session.sessionToken, isNotEmpty);
      expect(coordinator.state, PlaybackSessionState.active);
      expect(coordinator.hasLiveSession, isTrue);
      coordinator.dispose();
    });

    test('2) adopted server position is authoritative state', () async {
      final gateway = _FakeSessionGateway()
        ..positionToReturn = const Duration(seconds: 456);
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      expect(coordinator.session!.position, const Duration(seconds: 456));
      expect(coordinator.lastKnownPosition, const Duration(seconds: 456));
      coordinator.dispose();
    });

    test('3) same-device continuation keeps one live session', () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway);
      final first = await coordinator.begin(lectureId: 'lec-1');
      final second = await coordinator.begin(lectureId: 'lec-1');
      expect(second.sessionToken, first.sessionToken);
      expect(gateway.liveTokens['sub-A'], first.sessionToken);
      coordinator.dispose();
    });

    test('4) takeover adopts the new token', () async {
      final gateway = _FakeSessionGateway();
      final coordA = _coordinator(gateway, deviceId: 'dev-A');
      final coordB = _coordinator(gateway, deviceId: 'dev-B');
      await coordA.begin(lectureId: 'lec-1');
      final sessionB = await coordB.begin(lectureId: 'lec-1');
      expect(sessionB.takeover, isTrue);
      // Old device's next validation fails closed.
      expect(await coordA.beatNow(), isFalse);
      expect(coordA.state, PlaybackSessionState.superseded);
      coordA.dispose();
      coordB.dispose();
    });

    test('5) superseded heartbeat invokes the stop callback once', () async {
      final gateway = _FakeSessionGateway();
      final coordA = _coordinator(gateway, deviceId: 'dev-A');
      final coordB = _coordinator(gateway, deviceId: 'dev-B');
      await coordA.begin(lectureId: 'lec-1');
      await coordB.begin(lectureId: 'lec-1');
      var stops = 0;
      coordA.startHeartbeat(
        positionProvider: () => Duration.zero,
        onInvalidated: () async => stops++,
      );
      expect(await coordA.beatNow(), isFalse);
      expect(stops, 1);
      // No retry: further beats stay false without new gateway calls.
      final callsBefore = gateway.heartbeatCalls;
      expect(await coordA.beatNow(), isFalse);
      expect(gateway.heartbeatCalls, callsBefore);
      expect(stops, 1);
      coordA.dispose();
      coordB.dispose();
    });

    test('6) heartbeat sends Subject, token, and position', () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      gateway.calls.clear();
      final ok = await coordinator.beatNow(
          position: const Duration(seconds: 42));
      expect(ok, isTrue);
      expect(gateway.calls, ['beat:sub-A:dev-A']);
      expect(gateway.positions['sub-A'], 42);
      expect(coordinator.lastKnownPosition, const Duration(seconds: 42));
      coordinator.dispose();
    });

    test('7) heartbeat never begins (no slot claiming)', () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      final beginsBefore = gateway.beginCalls;
      await coordinator.beatNow(position: Duration.zero);
      await coordinator.beatNow(position: Duration.zero);
      expect(gateway.beginCalls, beginsBefore);
      coordinator.dispose();
    });

    test('8/17) dispose cancels timers; double start keeps one timer',
        () async {
      final gateway = _FakeSessionGateway();
      final factory = _ManualTimerFactory();
      final coordinator =
          _coordinator(gateway, timerFactory: factory.call);
      await coordinator.begin(lectureId: 'lec-1');
      coordinator.startHeartbeat(
        positionProvider: () => Duration.zero,
        onInvalidated: () async {},
      );
      coordinator.startHeartbeat(
        positionProvider: () => Duration.zero,
        onInvalidated: () async {},
      );
      expect(factory.created.length, 1);
      expect(coordinator.hasActiveHeartbeat, isTrue);
      final timer = factory.created.single;
      for (var i = 0; i < 3; i++) {
        timer.fire();
        await _settle();
      }
      // One timer only: exactly three beats, never a doubled stream.
      expect(gateway.heartbeatCalls, 3);
      expect(timer.fireCount, 3);
      coordinator.dispose();
      expect(coordinator.hasActiveHeartbeat, isFalse);
      expect(coordinator.isDisposed, isTrue);
      timer.fire();
      await _settle();
      expect(gateway.heartbeatCalls, 3);
    });

    test('10/20) invalidation stops the timer permanently', () async {
      final gateway = _FakeSessionGateway();
      final factory = _ManualTimerFactory();
      final coordinator =
          _coordinator(gateway, timerFactory: factory.call);
      await coordinator.begin(lectureId: 'lec-1');
      var stops = 0;
      coordinator.startHeartbeat(
        positionProvider: () => Duration.zero,
        onInvalidated: () async => stops++,
      );
      gateway.revokedSubjects.add('sub-A');
      factory.created.single.fire();
      await _settle();
      expect(coordinator.state, PlaybackSessionState.superseded);
      expect(coordinator.hasActiveHeartbeat, isFalse);
      expect(stops, 1);
      final callsAfter = gateway.heartbeatCalls;
      factory.created.single.fire();
      await _settle();
      expect(gateway.heartbeatCalls, callsAfter);
      expect(stops, 1);
      coordinator.dispose();
    });

    test('11) server Guest denial surfaces as invalid without session',
        () async {
      final gateway = _FakeSessionGateway()
        ..revokedSubjects.add('sub-A');
      final coordinator = _coordinator(gateway);
      await expectLater(
        coordinator.begin(lectureId: 'lec-1'),
        throwsA(isA<PlaybackSessionInvalidatedException>()),
      );
      expect(coordinator.session, isNull);
      expect(coordinator.state, PlaybackSessionState.invalid);
      coordinator.dispose();
    });

    test('13) Subject A invalidation cannot affect Subject B', () async {
      final gateway = _FakeSessionGateway();
      final coordA = _coordinator(gateway, subjectId: 'sub-A');
      final coordB = _coordinator(gateway, subjectId: 'sub-B');
      await coordA.begin(lectureId: 'lec-A');
      await coordB.begin(lectureId: 'lec-B');
      gateway.revokedSubjects.add('sub-A');
      expect(await coordA.beatNow(), isFalse);
      expect(await coordB.beatNow(), isTrue);
      expect(coordB.state, PlaybackSessionState.active);
      coordA.dispose();
      coordB.dispose();
    });

    test('14) same device holds independent live sessions per Subject',
        () async {
      final gateway = _FakeSessionGateway();
      final coordA = _coordinator(gateway, subjectId: 'sub-A');
      final coordB = _coordinator(gateway, subjectId: 'sub-B');
      await coordA.begin(lectureId: 'lec-A');
      await coordB.begin(lectureId: 'lec-B');
      final tokenA = coordA.session!.sessionToken;
      final tokenB = coordB.session!.sessionToken;
      expect(tokenA == tokenB, isFalse);
      // Both stay live simultaneously: B never stops A.
      expect(await coordA.beatNow(), isTrue);
      expect(await coordB.beatNow(), isTrue);
      // Replaying A's token against B's session fails closed: adopt a
      // forged cross-subject session, then validate — the server binding
      // (per-subject token registry in the fake) rejects it.
      coordB.adopt(PlaybackSession(subjectId: 'sub-B', sessionToken: tokenA));
      expect(await coordB.beatNow(), isFalse);
      expect(coordB.state, PlaybackSessionState.superseded);
      coordA.dispose();
      coordB.dispose();
    });

    test('15) transport failure preserves position without invalidating',
        () async {
      final gateway = _FlakyGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      expect(await coordinator.beatNow(position: const Duration(seconds: 50)),
          isTrue);
      expect(coordinator.lastKnownPosition, const Duration(seconds: 50));
      expect(coordinator.state, PlaybackSessionState.active);
      coordinator.dispose();
    });

    test('16) recovery revalidates and resets failure count', () async {
      final gateway = _FlakyGateway()..failuresRemaining = 2;
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      expect(await coordinator.beatNow(), isTrue);
      expect(await coordinator.beatNow(), isTrue);
      expect(coordinator.transportFailures, 2);
      expect(await coordinator.beatNow(position: const Duration(seconds: 9)),
          isTrue);
      expect(coordinator.transportFailures, 0);
      expect(coordinator.lastKnownPosition, const Duration(seconds: 9));
      coordinator.dispose();
    });

    test('18) revocation stops next validation; explicit begin recovers',
        () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway);
      await coordinator.begin(lectureId: 'lec-1');
      gateway.revokedSubjects.add('sub-A');
      expect(await coordinator.beatNow(), isFalse);
      gateway.revokedSubjects.remove('sub-A');
      final session = await coordinator.begin(lectureId: 'lec-1');
      expect(coordinator.state, PlaybackSessionState.active);
      expect(session.sessionToken, isNotEmpty);
      coordinator.dispose();
    });

    test('19) no local ownership forcing; cross-subject adopt ignored',
        () async {
      final gateway = _FakeSessionGateway();
      final coordinator = _coordinator(gateway, subjectId: 'sub-A');
      // A payload minted for another Subject is dropped silently.
      coordinator.adopt(const PlaybackSession(
        subjectId: 'sub-B',
        sessionToken: 'forged',
      ));
      expect(coordinator.session, isNull);
      expect(coordinator.state, PlaybackSessionState.none);
      coordinator.dispose();
    });
  });
}

/// Flushes pending microtasks so timer-driven async beats settle
/// deterministically without wall-clock waits.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Gateway failing transport a bounded number of times, then recovering.
class _FlakyGateway implements PlaybackSessionGateway {
  int failuresRemaining = 0;

  @override
  Future<PlaybackSession> begin({
    required String studentId,
    required String subjectId,
    required String deviceId,
    String? lectureId,
    String? videoId,
  }) async {
    return PlaybackSession(
      subjectId: subjectId,
      lectureId: lectureId,
      sessionToken: 'tok-flaky',
    );
  }

  @override
  Future<HeartbeatResult> heartbeat({
    required String studentId,
    required String subjectId,
    required String deviceId,
    required String sessionToken,
    required Duration position,
  }) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const PlaybackSessionTransportException('blip');
    }
    return HeartbeatResult(position: position, leaseExpiresAt: null);
  }
}
