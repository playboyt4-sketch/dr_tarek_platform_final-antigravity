import '../../domain/entities/lecture.dart';
import '../../domain/entities/lecture_resource.dart';
import '../../domain/repositories/lecture_repository.dart';
import '../datasources/lecture_remote_data_source.dart';

class LectureRepositoryImpl implements LectureRepository {
  final LectureRemoteDataSource _remoteDataSource;

  LectureRepositoryImpl({
    LectureRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource =
           remoteDataSource ?? LectureRemoteDataSource();

  @override
  Future<List<Lecture>> getLecturesForSection(
    String sectionId,
  ) {
    return _remoteDataSource.getLecturesForSection(sectionId);
  }

  @override
  Future<List<LectureResource>> getResourcesForLecture(
    String lectureId,
  ) {
    return _remoteDataSource.getResourcesForLecture(lectureId);
  }
}
