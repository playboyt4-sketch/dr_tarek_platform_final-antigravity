import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../../core/errors/failure.dart';

class CustomTokenRemoteDataSource {
  final FirebaseFunctions functions;
  final FirebaseAuth firebaseAuth;

  const CustomTokenRemoteDataSource({
    required this.functions,
    required this.firebaseAuth,
  });

  /// Applies the login "Remember me" choice to the Firebase session.
  ///
  /// Web honors it natively (unchecked drops to tab-lifetime persistence).
  /// Mobile has no session-only mode — the cold-start sweep in `main()`
  /// signs out restored opt-out sessions instead. Best-effort by contract:
  /// persistence must never fail a login.
  Future<void> applySessionPersistence({required bool rememberMe}) async {
    if (!kIsWeb) return;
    try {
      await firebaseAuth.setPersistence(
        rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
    } catch (_) {
      // Continue with the platform default.
    }
  }

  /// Signs in via the `verifyPhonePassword` callable + custom-token exchange.
  ///
  /// Every failure — callable errors (including App Check rejections, mapped
  /// to [FailureCode.appCheckFailed], never [FailureCode.wrongCredentials]),
  /// custom-token sign-in errors, and malformed backend payloads — is mapped
  /// into the shared [Failure] hierarchy so no raw exception crosses into
  /// Domain/Presentation (08 Development Standards Section 5). Same
  /// throw-[Failure] contract as [RegistrationRemoteDataSource].
  Future<UserCredential> login({
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final callable = functions.httpsCallable('verifyPhonePassword');

      final result = await callable.call({
        'phoneNumber': phoneNumber,
        'password': password,
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      final token = (data['token'] ?? data['customToken']) as String?;

      if (token == null || token.isEmpty) {
        throw const Failure(
          FailureCode.server,
          debugDetail: 'Authentication token was not returned.',
        );
      }

      return await firebaseAuth.signInWithCustomToken(token);
    } on Failure {
      rethrow;
    } on FirebaseFunctionsException catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    } on FirebaseAuthException catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    }
  }
}
