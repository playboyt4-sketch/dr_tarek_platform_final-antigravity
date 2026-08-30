import 'dart:io';

import '../../domain/entities/admin_content_entities.dart'
    show ResourceStorageProvider;

export '../../domain/entities/admin_content_entities.dart'
    show ResourceStorageProvider;

/// A file placed into one of the storage backends.
class StoredResourceFile {
  /// Canonical path as recorded on the lecture_resources document:
  /// /lecture_resources/{lectureId}/{resourceId}/{fileName} for both
  /// backends (11 Assets §4.2), zone-relative for Bunny.
  final String storagePath;
  final ResourceStorageProvider provider;

  const StoredResourceFile({required this.storagePath, required this.provider});
}

/// A time-limited access URL minted by a Cloud Function after entitlement
/// validation. The student-facing UI consumes [url] blindly.
class ResourceAccessUrl {
  final String url;
  final DateTime expiresAt;

  const ResourceAccessUrl({required this.url, required this.expiresAt});
}

/// The dual-provider abstraction at the heart of FINAL_DECISIONS §15.
///
/// WHY THIS EXISTS: "either backend works identically" must be true for
/// every layer ABOVE the data layer. This interface is the single seam
/// where Bunny-specifics (HMAC token URLs, proxied uploads through
/// uploadBunnyResource because Bunny has no presigned uploads) and
/// Firebase-specifics (Storage SDK uploads, function-issued signed URLs)
/// are absorbed. AdminContentRepositoryImpl picks an implementation per
/// upload from the chosen/default provider; student delivery callables
/// dispatch per-resource server-side. A widget or provider that branches
/// on "is this Bunny or Firebase" anywhere outside these implementations
/// is a Clean Architecture violation.
abstract class ResourceStorageGateway {
  ResourceStorageProvider get provider;

  /// Uploads bytes for a pdf/attachment/thumbnail under the REAL resource
  /// id so both backends share one path convention. Returns the stored
  /// path to persist alongside the metadata document.
  Future<StoredResourceFile> upload({
    required String lectureId,
    required String resourceId,
    required File file,
    String? contentTypeOverride,
    void Function(double progress)? onProgress,
  });

  /// Resolves a short-lived, entitlement-checked access URL for a stored
  /// resource. Validation always happens server-side; this method only
  /// carries the request.
  Future<ResourceAccessUrl> getSignedAccessUrl({
    required String resourceId,
    required bool forDownload,
  });

  /// Removes the stored bytes for an archived/purged resource
  /// (staff-only, audited server-side).
  Future<void> delete({
    required String lectureId,
    required String resourceId,
    required String fileName,
  });
}

/// Runtime exception surface for gateway callers; repositories translate
/// this into typed [Failure]s.
class StorageGatewayException implements Exception {
  final String message;
  const StorageGatewayException(this.message);

  @override
  String toString() => message;
}
