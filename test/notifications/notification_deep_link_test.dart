import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/routing/app_routes.dart';
import 'package:dr_tarek_platform/core/routing/notification_deep_link.dart';

/// Push payloads carry `deep_link`; a tap must open the student home for the
/// approval notification and must ignore unknown destinations.
void main() {
  group('notificationDeepLinkRoute', () {
    test('approval /home link opens the student home', () {
      expect(notificationDeepLinkRoute('/home'), AppRoutes.studentHomePath);
    });

    test('student-home and notifications links open the student home', () {
      expect(
        notificationDeepLinkRoute('/student-home'),
        AppRoutes.studentHomePath,
      );
      expect(
        notificationDeepLinkRoute('/notifications'),
        AppRoutes.studentHomePath,
      );
    });

    test('missing or unknown links are ignored', () {
      expect(notificationDeepLinkRoute(null), isNull);
      expect(notificationDeepLinkRoute(''), isNull);
      expect(notificationDeepLinkRoute('/unknown'), isNull);
    });
  });
}
