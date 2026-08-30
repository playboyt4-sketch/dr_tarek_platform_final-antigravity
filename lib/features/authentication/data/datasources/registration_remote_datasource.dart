import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/errors/failure.dart';

class RegistrationRemoteDataSource {
  final FirebaseFunctions functions;

  const RegistrationRemoteDataSource({required this.functions});

  /// Submits a new-student registration through the `registerNewStudent`
  /// callable (no auth required before submission) and resolves with the
  /// created user id.
  ///
  /// Backend business failures — including BR-01 phone uniqueness, surfaced
  /// as `already-exists` — are mapped into the shared [Failure] hierarchy so
  /// no raw FirebaseFunctionsException crosses into Domain/Presentation
  /// (08 Development Standards Section 5).
  Future<String> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) async {
    final callable = functions.httpsCallable('registerNewStudent');

    try {
      final result = await callable.call({
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'profilePhoto': profilePhoto,
        'grade': grade,
        'customGroupId': customGroupId,
        'customGroupName': customGroupName,
        'password': password,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final userId = data['userId'] as String?;
      if (userId == null || userId.isEmpty) {
        throw const Failure(
          FailureCode.server,
          debugDetail: 'Registration did not return a user id.',
        );
      }
      return userId;
    } on FirebaseFunctionsException catch (e, stackTrace) {
      // 'already-exists' maps to FailureCode.phoneAlreadyExists via
      // Failure.from (both by gRPC code and by the backend message
      // dictionary), letting Presentation show the specific duplicate-phone
      // message instead of a generic error.
      throw Failure.from(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    }
  }
}
