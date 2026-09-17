/// Central route names/paths for the app.
///
/// [userTypeSelection] is used as the go_router route *name* via
/// `context.goNamed` and as the Navigator route *name* via
/// `context.pushReplacementNamed`, so it is kept as a plain name
/// (no leading slash) with a matching path for router configuration.
abstract final class AppRoutes {
  static const String userTypeSelection = 'userTypeSelection';
  static const String userTypeSelectionPath = '/user-type-selection';

  static const String splash = 'splash';
  static const String splashPath = '/splash';

  static const String newStudentWelcome = 'newStudentWelcome';
  static const String newStudentWelcomePath = '/new-student-welcome';

  static const String login = 'login';
  static const String loginPath = '/login';

  static const String teacherAdminSelection = 'teacherAdminSelection';
  static const String teacherAdminSelectionPath = '/teacher-admin-selection';

  static const String staffPassword = 'staffPassword';
  static const String staffPasswordPath = '/staff-password';
}
