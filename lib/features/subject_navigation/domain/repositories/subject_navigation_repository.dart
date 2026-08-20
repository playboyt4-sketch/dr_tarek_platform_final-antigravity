import '../entities/subject_learning_entities.dart';

abstract interface class SubjectNavigationRepository {
  Future<List<LearningSection>> getSections(String subjectId);
  Future<List<LectureSummary>> getLectures(String sectionId);
}
