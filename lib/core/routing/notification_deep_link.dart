import 'app_routes.dart';

/// Maps a push-notification `deep_link` payload to an in-app route.
///
/// Unknown/absent links return null and are ignored, so a malformed payload
/// can never push the app into an error route. `/home` is the link written by
/// the approval notification; `/notifications` lands on the student home
/// where the in-app inbox tab lives.
String? notificationDeepLinkRoute(String? deepLink) {
  switch (deepLink) {
    case '/home':
    case '/student-home':
    case '/notifications':
      return AppRoutes.studentHomePath;
    default:
      return null;
  }
}
