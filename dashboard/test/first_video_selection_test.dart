import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the canonical first-video selector the Dashboard writer sync
/// (Phase 3) calls after every resource mutation. Pure and side-effect
/// free: eligibility is video + visible + not soft-deleted + non-empty
/// Bunny id; lowest display_order wins; document id breaks ties.
FirstVideoCandidate _candidate(
  String id,
  int order, {
  String type = 'video',
  bool isVisible = true,
  bool isDeleted = false,
  String? bunnyVideoId = '33333333-3333-4333-8333-333333333333',
}) {
  return FirstVideoCandidate(
    id: id,
    type: type,
    isVisible: isVisible,
    isDeleted: isDeleted,
    bunnyVideoId: bunnyVideoId,
    displayOrder: order,
  );
}

void main() {
  group('selectFirstVideoCandidate - canonical writer selector', () {
    test('single eligible video wins', () {
      expect(
        selectFirstVideoCandidate([_candidate('v1', 1)]),
        isNotNull,
      );
      expect(
        selectFirstVideoCandidate([_candidate('v1', 1)])?.id,
        'v1',
      );
    });

    test('no candidates yields null', () {
      expect(selectFirstVideoCandidate(const []), isNull);
    });

    test('lowest display_order wins regardless of input order', () {
      final winner = selectFirstVideoCandidate([
        _candidate('v-high', 9),
        _candidate('v-low', 2),
        _candidate('v-mid', 5),
      ]);

      expect(winner?.id, 'v-low');
    });

    test('document id ascending breaks display_order ties', () {
      final winner = selectFirstVideoCandidate([
        _candidate('v-b', 3),
        _candidate('v-a', 3),
      ]);

      expect(winner?.id, 'v-a');
    });

    test('invisible video is ignored', () {
      final winner = selectFirstVideoCandidate([
        _candidate('v-hidden', 0, isVisible: false),
        _candidate('v1', 4),
      ]);

      expect(winner?.id, 'v1');
    });

    test('soft-deleted video is ignored even while still visible', () {
      final winner = selectFirstVideoCandidate([
        _candidate('v-del', 0, isDeleted: true, isVisible: true),
        _candidate('v1', 6),
      ]);

      expect(winner?.id, 'v1');
    });

    test('missing or empty bunny_video_id is ignored', () {
      final winner = selectFirstVideoCandidate([
        _candidate('v-noid', 0, bunnyVideoId: null),
        _candidate('v-empty', 1, bunnyVideoId: '  '),
        _candidate('v1', 7),
      ]);

      expect(winner?.id, 'v1');
    });

    test('non-video types are ignored', () {
      final winner = selectFirstVideoCandidate([
        _candidate('p0', 0, type: 'pdf'),
        _candidate('a0', 1, type: 'attachment'),
        _candidate('v1', 2),
      ]);

      expect(winner?.id, 'v1');
    });

    test('all ineligible yields null (writer must clear first_video)', () {
      expect(
        selectFirstVideoCandidate([
          _candidate('v-del', 0, isDeleted: true),
          _candidate('p0', 1, type: 'pdf'),
        ]),
        isNull,
      );
    });
  });
}
