import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class SubjectPosterGateway {
  final FirebaseStorage storage;

  SubjectPosterGateway({FirebaseStorage? storage})
      : storage = storage ?? FirebaseStorage.instance;

  Future<String> uploadPoster({
    required String subjectId,
    required File file,
    required String fileName,
  }) async {
    final ref = storage.ref('subject_posters/$subjectId/$fileName');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> deletePoster(String posterUrl) async {
    try {
      final ref = storage.refFromURL(posterUrl);
      await ref.delete();
    } catch (_) {
      // Non-critical if deletion fails
    }
  }
}
