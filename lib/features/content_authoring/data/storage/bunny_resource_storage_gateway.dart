import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import 'resource_storage_gateway.dart';

/// Bunny Storage implementation (zone `dr-tarek-resources`).
///
/// UPLOAD — proxied through the `uploadBunnyResource` callable. Chosen over
/// direct client-to-Bunny because Bunny Storage has no presigned-upload
/// mechanism: a direct PUT would require shipping the Storage Zone password
/// inside the app, which is an unacceptable credential exposure. Tradeoff:
/// Cloud Functions/Cloud Run cap request bodies (~32MB; base64 overhead
/// leaves ~24MB of binary headroom enforced server-side), so the 50MB
/// placeholder ceiling applies in full only to the Firebase path today.
///
/// READS — `generateBunnyResourceUrl` mirrors `generateBunnySignedUrl`
/// exactly (same subject-access + subscription + plan-feature validation,
/// same HMAC token scheme). Credentials never reach this class; it only
/// ever receives finished URLs.
class BunnyResourceStorageGateway implements ResourceStorageGateway {
  final FirebaseFunctions functions;

  BunnyResourceStorageGateway({FirebaseFunctions? functions})
      : functions = functions ?? FirebaseFunctions.instance;

  @override
  ResourceStorageProvider get provider => ResourceStorageProvider.bunny;

  @override
  Future<StoredResourceFile> upload({
    required String lectureId,
    required String resourceId,
    required File file,
    String? contentTypeOverride,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);
    final fileName = file.uri.pathSegments.last;
    try {
      final response = await functions.httpsCallable('uploadBunnyResource').call({
        'lectureId': lectureId,
        'resourceId': resourceId,
        'fileName': fileName,
        'contentType': contentTypeOverride ?? 'application/octet-stream',
        'dataBase64': base64Encode(file.readAsBytesSync()),
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      final path = data['storagePath'] as String?;
      if (path == null || path.isEmpty) {
        throw const StorageGatewayException('Bunny upload returned no storage path.');
      }
      onProgress?.call(1.0);
      return StoredResourceFile(
        storagePath: path,
        provider: ResourceStorageProvider.bunny,
      );
    } on FirebaseFunctionsException catch (error) {
      throw StorageGatewayException('${error.code}: ${error.message}');
    }
  }

  @override
  Future<ResourceAccessUrl> getSignedAccessUrl({
    required String resourceId,
    required bool forDownload,
  }) async {
    try {
      final response =
          await functions.httpsCallable('generateBunnyResourceUrl').call({
        'resourceId': resourceId,
        'forDownload': forDownload,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      return ResourceAccessUrl(
        url: data['url'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (data['expiresAt'] as num).toInt(),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      throw StorageGatewayException('${error.code}: ${error.message}');
    }
  }

  @override
  Future<void> delete({
    required String lectureId,
    required String resourceId,
    required String fileName,
  }) async {
    try {
      await functions.httpsCallable('deleteBunnyResource').call({
        'storagePath': 'lecture_resources/$lectureId/$resourceId/$fileName',
      });
    } on FirebaseFunctionsException catch (error) {
      throw StorageGatewayException('${error.code}: ${error.message}');
    }
  }
}
