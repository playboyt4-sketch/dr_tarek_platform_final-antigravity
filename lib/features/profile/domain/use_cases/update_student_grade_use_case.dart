import '../repositories/profile_repository.dart';

class UpdateStudentGradeUseCase {
  final ProfileRepository repository;

  const UpdateStudentGradeUseCase(this.repository);

  Future<void> execute({
    required String studentId,
    required String grade,
  }) async {
    return repository.updateStudentGrade(
      studentId: studentId,
      grade: grade,
    );
  }
}
