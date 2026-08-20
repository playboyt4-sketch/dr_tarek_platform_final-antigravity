import '../entities/lecture.dart';
import '../entities/lecture_resource.dart';

abstract class LectureRepository {
  Future<List<Lecture>> getLecturesForSection(String sectionId);

  Future<List<LectureResource>> getResourcesForLecture(String lectureId);
}
