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
}
