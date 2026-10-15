import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/errors/failure.dart';

/// Server-side entry point for the V1 forgot-password flow.
///
/// Calls the existing `submitPasswordResetRequest` callable with the exact
/// V1 payload (`phoneNumber`). The backend normalizes/validates the Egyptian
/// number, applies per-phone throttling (3 requests / 15 min), and returns a
/// uniform `{submitted: true}` for eligible AND ineligible phones
/// (anti-enumeration) — so the response carries no account-state signal and
/// nothing here may branch on it.
///
/// This replaces the previous direct `FirebaseFunctions` call that lived in
/// the presentation layer; the backend contract (callable name + payload) is
/// unchanged. No password, token, or account data is logged or returned.
class PasswordResetRemoteDataSource {
  final FirebaseFunctions functions;

  const PasswordResetRemoteDataSource({required this.functions});

  Future<void> submitPasswordResetRequest({required String phoneNumber}) async {
    final callable = functions.httpsCallable('submitPasswordResetRequest');

    try {
      await callable.call(<String, dynamic>{'phoneNumber': phoneNumber});
    } on FirebaseFunctionsException catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    }
  }
}
