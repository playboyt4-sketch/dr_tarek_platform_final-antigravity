import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/errors/failure.dart';

class StaffDirectoryEntry {
  final String displayName;
  final String roleKind; // 'dr' | 'admin'

  const StaffDirectoryEntry({required this.displayName, required this.roleKind});

  factory StaffDirectoryEntry.fromMap(Map<String, dynamic> map) {
    return StaffDirectoryEntry(
      displayName: (map['displayName'] ?? '') as String,
      roleKind: (map['roleKind'] ?? 'admin') as String,
    );
  }
}

class StaffAuthRemoteDataSource {
  final FirebaseFunctions functions;
  final FirebaseAuth firebaseAuth;

  const StaffAuthRemoteDataSource({
    required this.functions,
    required this.firebaseAuth,
  });

  /// Lists staff directory entries through the `listStaffDirectory`
  /// callable. Failures are mapped into the shared [Failure] hierarchy so
  /// no raw exception crosses into Domain/Presentation
  /// (08 Development Standards Section 5).
  Future<List<StaffDirectoryEntry>> listStaff() async {
    try {
      final callable = functions.httpsCallable('listStaffDirectory');
      final result = await callable.call(<String, dynamic>{});
      final data = Map<String, dynamic>.from(result.data as Map);
      final staff = (data['staff'] as List? ?? [])
          .whereType<Map>()
          .map((e) => StaffDirectoryEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      return staff;
    } on Failure {
      rethrow;
    } on FirebaseFunctionsException catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      throw Failure.from(e, stackTrace);
    }
  }

  /// Signs staff in via the `verifyStaffPassword` callable + custom-token
  /// exchange. Same throw-[Failure] contract as
  /// [CustomTokenRemoteDataSource.login].
  Future<UserCredential> login({
    required String displayName,
    required String password,
  }) async {
    try {
      final callable = functions.httpsCallable('verifyStaffPassword');

      final result = await callable.call({
        'displayName': displayName,
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
