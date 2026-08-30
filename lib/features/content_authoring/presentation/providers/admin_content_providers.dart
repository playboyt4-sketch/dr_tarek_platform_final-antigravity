import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../lecture/domain/entities/lecture.dart';
import '../../data/datasources/admin_content_data_source.dart';
import '../../data/datasources/admin_content_remote_data_source_impl.dart';
import '../../data/datasources/system_settings_data_source.dart';
import '../../data/repositories/admin_content_repository_impl.dart';
import '../../domain/entities/admin_content_entities.dart';
import '../../domain/repositories/admin_content_repository.dart';
import '../../domain/use_cases/lecture_use_cases.dart';
import '../../domain/use_cases/resource_use_cases.dart';
import '../../domain/use_cases/section_use_cases.dart';

/// Riverpod graph for staff content authoring, per 07 Flutter Architecture
/// §6-7: StreamProvider lists for the live Firestore queries (07 §6:
/// "StreamProvider for real-time Firestore listeners where live updates
/// matter"), plain use-case Providers for mutations.

final adminContentDataSourceProvider = Provider<AdminContentDataSource>((ref) {
  return AdminContentRemoteDataSourceImpl();
});

final systemSettingsDataSourceProvider = Provider<SystemSettingsDataSource>(
    (ref) => SystemSettingsDataSource());

final adminContentRepositoryProvider = Provider<AdminContentRepository>((ref) {
  return AdminContentRepositoryImpl(
    dataSource: ref.watch(adminContentDataSourceProvider),
    // FINAL_DECISIONS §15: uploads default to the Teacher-configured
    // platform provider; the Admin can still override per file.
    platformDefaultProviderLoader: () =>
        ref.watch(systemSettingsDataSourceProvider).defaultStorageProvider(),
  );
});

final _repo = adminContentRepositoryProvider;

// ---- Section use cases ----
final watchSectionsUseCaseProvider =
    Provider<WatchSections>((ref) => WatchSections(ref.watch(_repo)));
final createSectionUseCaseProvider =
    Provider<CreateSection>((ref) => CreateSection(ref.watch(_repo)));
final updateSectionUseCaseProvider =
    Provider<UpdateSection>((ref) => UpdateSection(ref.watch(_repo)));
final reorderSectionsUseCaseProvider =
    Provider<ReorderSections>((ref) => ReorderSections(ref.watch(_repo)));
final deleteCustomSectionUseCaseProvider =
    Provider<DeleteCustomSection>((ref) => DeleteCustomSection(ref.watch(_repo)));
final watchArchivedSectionsUseCaseProvider = Provider<WatchArchivedSections>(
    (ref) => WatchArchivedSections(ref.watch(_repo)));
final restoreSectionUseCaseProvider =
    Provider<RestoreSection>((ref) => RestoreSection(ref.watch(_repo)));

// ---- Lecture use cases ----
final watchLecturesUseCaseProvider =
    Provider<WatchLectures>((ref) => WatchLectures(ref.watch(_repo)));
final createLectureUseCaseProvider =
    Provider<CreateLecture>((ref) => CreateLecture(ref.watch(_repo)));
final updateLectureMetadataUseCaseProvider = Provider<UpdateLectureMetadata>(
    (ref) => UpdateLectureMetadata(ref.watch(_repo)));
final setLecturePublishedUseCaseProvider = Provider<SetLecturePublished>(
    (ref) => SetLecturePublished(ref.watch(_repo)));
final setLecturePublicFreeUseCaseProvider = Provider<SetLecturePublicFree>(
    (ref) => SetLecturePublicFree(ref.watch(_repo)));
final archiveLectureUseCaseProvider =
    Provider<ArchiveLecture>((ref) => ArchiveLecture(ref.watch(_repo)));
final reorderLecturesUseCaseProvider =
    Provider<ReorderLectures>((ref) => ReorderLectures(ref.watch(_repo)));
final watchArchivedLecturesUseCaseProvider = Provider<WatchArchivedLectures>(
    (ref) => WatchArchivedLectures(ref.watch(_repo)));
final restoreLectureUseCaseProvider =
    Provider<RestoreLecture>((ref) => RestoreLecture(ref.watch(_repo)));

// ---- Resource use cases ----
final watchResourcesUseCaseProvider =
    Provider<WatchResources>((ref) => WatchResources(ref.watch(_repo)));
final addVideoResourceUseCaseProvider =
    Provider<AddVideoResource>((ref) => AddVideoResource(ref.watch(_repo)));
final addPdfResourceUseCaseProvider =
    Provider<AddPdfResource>((ref) => AddPdfResource(ref.watch(_repo)));
final addAttachmentResourceUseCaseProvider = Provider<AddAttachmentResource>(
    (ref) => AddAttachmentResource(ref.watch(_repo)));
final addExternalLinkResourceUseCaseProvider = Provider<AddExternalLinkResource>(
    (ref) => AddExternalLinkResource(ref.watch(_repo)));
final setResourceThumbnailUseCaseProvider = Provider<SetResourceThumbnail>(
    (ref) => SetResourceThumbnail(ref.watch(_repo)));
final setResourceVisibilityUseCaseProvider = Provider<SetResourceVisibility>(
    (ref) => SetResourceVisibility(ref.watch(_repo)));
final archiveResourceUseCaseProvider =
    Provider<ArchiveResource>((ref) => ArchiveResource(ref.watch(_repo)));
final reorderResourcesUseCaseProvider =
    Provider<ReorderResources>((ref) => ReorderResources(ref.watch(_repo)));
final watchArchivedResourcesUseCaseProvider = Provider<WatchArchivedResources>(
    (ref) => WatchArchivedResources(ref.watch(_repo)));
final restoreResourceUseCaseProvider =
    Provider<RestoreResource>((ref) => RestoreResource(ref.watch(_repo)));

/// Live sections list for one subject (system + custom), ordered by
/// display_order.
final adminSectionsProvider =
    StreamProvider.family<List<AdminSection>, String>((ref, subjectId) {
  return ref.watch(watchSectionsUseCaseProvider).execute(subjectId);
});

/// Live lectures list for one section (non-archived), ordered by
/// display_order, publish status on the entity.
final adminLecturesProvider =
    StreamProvider.family<List<Lecture>, String>((ref, sectionId) {
  return ref.watch(watchLecturesUseCaseProvider).execute(sectionId);
});

/// Live resources list for one lecture — soft-deleted entries are filtered
/// out by the datasource query itself.
final adminResourcesProvider =
    StreamProvider.family<List<AdminLectureResource>, String>(
        (ref, lectureId) {
  return ref.watch(watchResourcesUseCaseProvider).execute(lectureId);
});

// ---- Archive System (Part B) ----
final adminArchivedSectionsProvider =
    StreamProvider.family<List<AdminSection>, String>((ref, subjectId) {
  return ref.watch(watchArchivedSectionsUseCaseProvider).execute(subjectId);
});

final adminArchivedLecturesProvider =
    StreamProvider.family<List<ArchivedLecture>, String>((ref, subjectId) {
  return ref.watch(watchArchivedLecturesUseCaseProvider).execute(subjectId);
});

final adminArchivedResourcesProvider =
    StreamProvider.family<List<AdminLectureResource>, String>(
        (ref, lectureId) {
  return ref.watch(watchArchivedResourcesUseCaseProvider).execute(lectureId);
});

/// Subjects available in the authoring picker (staff-readable collection).
final adminSubjectsProvider = FutureProvider.autoDispose((ref) async {
  final repo = ref.watch(adminContentRepositoryProvider);
  return repo.listSubjects();
});
