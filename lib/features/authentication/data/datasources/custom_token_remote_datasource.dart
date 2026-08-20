import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomTokenRemoteDataSource {
  final FirebaseFunctions functions;
  final FirebaseAuth firebaseAuth;

  const CustomTokenRemoteDataSource({
    required this.functions,
    required this.firebaseAuth,
  });

  Future<UserCredential> login({
    required String phoneNumber,
    required String password,
  }) async {
    final callable = functions.httpsCallable('verifyPhonePassword');

    final result = await callable.call({
      'phoneNumber': phoneNumber,
      'password': password,
    });

    final data = Map<String, dynamic>.from(result.data as Map);

    final token = (data['token'] ?? data['customToken']) as String?;

    if (token == null || token.isEmpty) {
      throw StateError('Authentication token was not returned.');
    }

    return firebaseAuth.signInWithCustomToken(token);
  }
}
