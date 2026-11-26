import 'package:firebase_storage/firebase_storage.dart';

import '../widgets/web_file_drop.dart';

/// Resolves a MIME type for common dashboard image, PDF, and attachment files.
String inferDashboardMimeType(String fileName, {String? fallback}) {
  final String lower = fileName.trim().toLowerCase();
  final int dot = lower.lastIndexOf('.');
  final String ext = dot >= 0 ? lower.substring(dot + 1) : '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    'txt' => 'text/plain',
    _ => fallback ?? 'application/octet-stream',
  };
}

/// Uploads [file] bytes to Firebase Storage under `[folder]/<timestamp>_<safeName>`
/// and returns its public download URL.
Future<String> uploadDashboardFileToStorage({
  required String folder,
  required DroppedFileData file,
  String? contentType,
}) async {
  final String safeName = file.name.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9._-]'),
    '_',
  );
  final String storagePath =
      '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
  final Reference storageRef =
      FirebaseStorage.instance.ref().child(storagePath);
  final String resolvedType =
      contentType ?? inferDashboardMimeType(file.name);
  await storageRef.putData(
    file.bytes,
    SettableMetadata(contentType: resolvedType),
  );
  return storageRef.getDownloadURL();
}
