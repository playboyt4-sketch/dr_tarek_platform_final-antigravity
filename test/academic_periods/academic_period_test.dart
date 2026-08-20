import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/academic_periods/domain/entities/academic_period.dart';

void main() {
  group('AcademicPeriod.fromMap', () {
    test('parses the approved schema (label, is_core, active status)', () {
      final period = AcademicPeriod.fromMap(const {
        'id': 'term_1',
        'period_type': 'term_1',
        'label': 'الترم الأول',
        'is_core': true,
        'status': 'active',
        'display_order': 1,
        'started_at': {'_seconds': 1770000000},
        'ended_at': null,
      });

      expect(period.id, 'term_1');
      expect(period.type, AcademicPeriodType.term1);
      expect(period.label, 'الترم الأول');
      expect(period.isCore, isTrue);
      expect(period.status, AcademicPeriodStatus.active);
      expect(period.isActive, isTrue);
      expect(period.displayOrder, 1);
      expect(period.startedAt, isNotNull);
      expect(period.endedAt, isNull);
    });

    test('treats legacy STARTED/ENDED statuses as active/ended', () {
      final started = AcademicPeriod.fromMap(const {
        'id': 'term_2',
        'period_type': 'term_2',
        'name': 'Term 2',
        'status': 'STARTED',
      });
      final ended = AcademicPeriod.fromMap(const {
        'id': 'summer_course',
        'period_type': 'summer_course',
        'name': 'Summer Course',
        'status': 'ENDED',
      });

      expect(started.status, AcademicPeriodStatus.active);
      expect(started.label, 'Term 2');
      expect(ended.status, AcademicPeriodStatus.ended);
      expect(ended.isActive, isFalse);
    });

    test('maps free-text period types to exceptional', () {
      final period = AcademicPeriod.fromMap(const {
        'id': 'abc123',
        'period_type': 'individual_training',
        'label': 'تدريب فردي',
        'is_core': false,
        'status': 'ended',
      });

      expect(period.type, AcademicPeriodType.exceptional);
      expect(period.periodType, 'individual_training');
      expect(period.isCore, isFalse);
    });
  });
}
