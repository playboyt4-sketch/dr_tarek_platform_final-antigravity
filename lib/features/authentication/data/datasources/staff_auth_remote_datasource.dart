import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<List<StaffDirectoryEntry>> listStaff() async {
    final callable = functions.httpsCallable('listStaffDirectory');
    final result = await callable.call(<String, dynamic>{});
    final data = Map<String, dynamic>.from(result.data as Map);
    final staff = (data['staff'] as List? ?? [])
        .whereType<Map>()
        .map((e) => StaffDirectoryEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return staff;
  }

  Future<UserCredential> login({
    required String displayName,
    required String password,
  }) async {
    final callable = functions.httpsCallable('verifyStaffPassword');

    final result = await callable.call({
      'displayName': displayName,
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
