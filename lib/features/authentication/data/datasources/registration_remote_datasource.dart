import 'package:cloud_functions/cloud_functions.dart';

class RegistrationRemoteDataSource {
  final FirebaseFunctions functions;

  const RegistrationRemoteDataSource({required this.functions});

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
      throw StateError('Registration did not return a user id.');
    }
    return userId;
  }
}
