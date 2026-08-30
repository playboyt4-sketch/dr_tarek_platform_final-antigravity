import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Remote data source implementing the V1 Custom Token authentication flow.
///
/// Calls the `verifyPhonePassword` Cloud Function, then exchanges the
/// returned Custom Token for a Firebase Auth session via
/// `signInWithCustomToken`. No other login mechanism exists in this app.
class CustomTokenRemoteDataSource {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _functions;

  const CustomTokenRemoteDataSource(this._firebaseAuth, this._functions);

  /// Returns the authenticated Firebase user after establishing the session.
  Future<User> login({
    required String phoneNumber,
    required String password,
  }) async {
    final callable = _functions.httpsCallable('verifyPhonePassword');
    final result = await callable.call(<String, dynamic>{
      'phoneNumber': phoneNumber.trim(),
      'password': password,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final token = (data['token'] ?? data['customToken']) as String?;
    if (token == null || token.isEmpty) {
      throw StateError('Authentication token was not returned.');
    }

    final credential = await _firebaseAuth.signInWithCustomToken(token);
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase session was not established.');
    }
    return user;
  }

  Future<void> logout() => _firebaseAuth.signOut();
}
