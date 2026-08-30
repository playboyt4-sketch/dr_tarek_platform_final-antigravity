import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final FirebaseStorage storage;
  final FirebaseFirestore firestore;

  ProfileRepositoryImpl({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  })  : storage = storage ?? FirebaseStorage.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

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
}
