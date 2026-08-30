/// Minimal authenticated-session view needed by the Dashboard router.
///
/// Claims are read verbatim from the Firebase ID token. The client never
/// invents default claim values — authorization remains a backend
/// responsibility; this entity only mirrors what the backend issued.
class DashboardSession {
  final String userId;
  final String? role;
  final bool approved;

  const DashboardSession({
    required this.userId,
    required this.role,
    required this.approved,
  });

  /// Whether this session may see the staff dashboard experience.
  ///
  /// Mirrors the existing approved dashboard behavior: only `teacher` and
  /// `admin` roles with an approved account are admitted.
  bool get isStaff => (role == 'teacher' || role == 'admin') && approved;
}
