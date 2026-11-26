import '../../domain/entities/subject_learning_entities.dart';
import '../../domain/repositories/subject_navigation_repository.dart';
import '../datasources/subject_navigation_remote_data_source.dart';

class SubjectNavigationRepositoryImpl implements SubjectNavigationRepository {
  final SubjectNavigationRemoteDataSource remoteDataSource;

  const SubjectNavigationRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<LearningSection>> getSections(String subjectId) {
    return remoteDataSource.getSections(subjectId);
  }

  @override
  Future<List<LectureSummary>> getLectures(String sectionId) {
    return remoteDataSource.getLectures(sectionId);
  }

  @override
  Stream<List<LearningSection>> watchSections(String subjectId) {
    return remoteDataSource.watchSections(subjectId);
  }

  @override
  Stream<List<LectureSummary>> watchLectures(String sectionId) {
    return remoteDataSource.watchLectures(sectionId);
  }
}
