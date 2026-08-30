import '../entities/admin_content_entities.dart';
import '../repositories/admin_content_repository.dart';

/// One class per distinct section operation (08 Development Standards §4),
/// grouped per aggregate to avoid sixteen near-identical files (MA §9.1).

class WatchSections {
  final AdminContentRepository repository;
  const WatchSections(this.repository);

  Stream<List<AdminSection>> execute(String subjectId) =>
      repository.watchSections(subjectId);
}

class CreateSection {
  final AdminContentRepository repository;
  const CreateSection(this.repository);

  Future<String> execute({
    required String subjectId,
    required String title,
    required bool isVisible,
  }) =>
      repository.createSection(
          subjectId: subjectId, title: title, isVisible: isVisible);
}

class UpdateSection {
  final AdminContentRepository repository;
  const UpdateSection(this.repository);

  Future<void> execute(
    AdminSection section, {
    required String newTitle,
    required bool newIsVisible,
  }) =>
      repository.updateSection(section,
          newTitle: newTitle, newIsVisible: newIsVisible);
}

class ReorderSections {
  final AdminContentRepository repository;
  const ReorderSections(this.repository);

  /// Persists display_order for ALL affected sections atomically.
  Future<void> execute(List<AdminSection> orderedSections) =>
      repository.reorderSections(orderedSections);
}

class DeleteCustomSection {
  final AdminContentRepository repository;
  const DeleteCustomSection(this.repository);

  /// Throws:
  ///  - Failure(permissionDenied) for system sections — they may only be
  ///    hidden (the Security Rules block them at the boundary as well);
  ///  - Failure(sectionHasActiveLectures) when any non-archived lecture
  ///    remains inside (Part B / 05 Database v1.9 §9). The UI maps that
  ///    code to: «لا يمكن حذف القسم لوجود محاضرات نشطة بداخله.
  ///    يرجى أرشفة المحاضرات أولاً.»
  Future<void> execute(AdminSection section) =>
      repository.deleteCustomSection(section);
}

class WatchArchivedSections {
  final AdminContentRepository repository;
  const WatchArchivedSections(this.repository);

  Stream<List<AdminSection>> execute(String subjectId) =>
      repository.watchArchivedSections(subjectId);
}

class RestoreSection {
  final AdminContentRepository repository;
  const RestoreSection(this.repository);

  Future<void> execute(AdminSection section) =>
      repository.restoreSection(section);
}
