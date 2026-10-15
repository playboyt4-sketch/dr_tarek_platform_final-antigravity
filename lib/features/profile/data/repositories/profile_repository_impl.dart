import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../authentication/data/datasources/user_profile_remote_datasource.dart';
import '../../../authentication/domain/entities/auth_user.dart';
import '../../domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final FirebaseStorage storage;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final UserProfileRemoteDataSource userProfiles;

  ProfileRepositoryImpl({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    UserProfileRemoteDataSource? userProfiles,
  })  : storage = storage ?? FirebaseStorage.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance,
        userProfiles = userProfiles ??
            UserProfileRemoteDataSource(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final ref = storage.ref('profile_photos/$userId/$fileName');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  @override
  Future<void> updateProfilePhotoUrl({
    required String userId,
    required String url,
  }) async {
    await firestore.collection('users').doc(userId).update({
      'profile_photo': url,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': userId,
    });
  }

  @override
  Future<void> updateFullName({
    required String userId,
    required String fullName,
  }) async {
    final name = fullName.trim();
    if (name.isEmpty) {
      throw ArgumentError('fullName must not be blank.');
    }
    await firestore.collection('users').doc(userId).update({
      'full_name': name,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': userId,
    });
  }

  @override
  Future<AuthUser> getStudentProfile(String studentId) async {
    final profile = await userProfiles.getUserById(studentId);
    if (profile == null) {
      throw StateError('Student profile was not found.');
    }
    return profile;
  }

  @override
  Future<void> updateStudentGrade({
    required String studentId,
    required String grade,
  }) async {
    // No client-side grade validation beyond transport: the
    // `updateStudentGrade` callable is authoritative for normalization,
    // authorization (`requireStudentAccessManager`) and auditing.
    // FirebaseFunctionsException propagates for UI mapping via
    // `friendlyFunctionErrorMessage`.
    await functions.httpsCallable('updateStudentGrade').call({
      'studentId': studentId,
      'grade': grade,
    });
  }
}
