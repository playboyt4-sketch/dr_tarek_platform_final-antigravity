import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'resource_storage_gateway.dart';

/// Firebase Storage implementation for pdf/attachment/thumbnail bytes.
///
/// UPLOAD — direct SDK upload from the Data layer (never from a widget) to
/// /lecture_resources/{lectureId}/{resourceId}/{file} under staff-only
/// storage.rules (11 Assets §4.2). No request-body ceiling beyond the
/// rules' 50MB placeholder, unlike the proxied Bunny path.
///
/// READS — `generateProtectedPdfUrl` / `generatePdfDownloadUrl` keep client
/// reads DENIED by Storage Rules and instead mint short-lived signed URLs
/// after per-request subscription validation. This approach is kept over
/// custom-claim-checked Rules because it matches the established
/// video-adjacent protection pattern (06 §5.2/§5.3): zero public surface,
/// one auditable entitlement checkpoint.
class FirebaseResourceStorageGateway implements ResourceStorageGateway {
  final FirebaseStorage storage;
  final FirebaseFunctions functions;

  FirebaseResourceStorageGateway({
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
  })  : storage = storage ?? FirebaseStorage.instance,
        functions = functions ?? FirebaseFunctions.instance;

  @override
  ResourceStorageProvider get provider => ResourceStorageProvider.firebase;

  @override
  Future<StoredResourceFile> upload({
    required String lectureId,
    required String resourceId,
    required File file,
    String? contentTypeOverride,
    void Function(double progress)? onProgress,
  }) async {
    final fileName = file.uri.pathSegments.last;
    final ref = storage
        .ref()
        .child('lecture_resources')
        .child(lectureId)
        .child(resourceId)
        .child(fileName);
    final task = ref.putData(
      file.readAsBytesSync(),
      SettableMetadata(contentType: contentTypeOverride),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes == 0 ? 1 : snapshot.totalBytes;
        onProgress(snapshot.bytesTransferred / total);
      });
    }
    final snapshot = await task;
    return StoredResourceFile(
      storagePath: snapshot.ref.fullPath,
      provider: ResourceStorageProvider.firebase,
    );
  }

  @override
  Future<ResourceAccessUrl> getSignedAccessUrl({
    required String resourceId,
    required bool forDownload,
  }) async {
    try {
      final callableName =
          forDownload ? 'generatePdfDownloadUrl' : 'generateProtectedPdfUrl';
      final response =
          await functions.httpsCallable(callableName).call({'resourceId': resourceId});
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
    await storage
        .ref()
        .child('lecture_resources')
        .child(lectureId)
        .child(resourceId)
        .child(fileName)
        .delete();
  }
}

/// Resolves the effective provider for an upload: the Admin's per-file
/// override wins; otherwise the platform default from
/// system_settings.default_storage_provider (Part E), itself defaulting to
/// firebase. Kept in the DATA layer so no caller re-implements the rule.
class ResourceStorageProviderResolver {
  final Future<String?> Function()? loadPlatformDefault;

  const ResourceStorageProviderResolver({this.loadPlatformDefault});

  Future<ResourceStorageProvider> resolve({Object? explicitChoice}) =>
      ResourceStorageProviders.resolveEffective(
        explicitChoice: explicitChoice,
        loadPlatformDefault: loadPlatformDefault,
      );
}

class ResourceStorageProviders {
  static Future<ResourceStorageProvider> resolveEffective({
    Object? explicitChoice,
    Future<String?> Function()? loadPlatformDefault,
  }) async {
    if (explicitChoice is ResourceStorageProvider) return explicitChoice;
    if (explicitChoice is String && explicitChoice.isNotEmpty) {
      return ResourceStorageProvider.fromWire(explicitChoice);
    }
    final loader = loadPlatformDefault;
    if (loader != null) {
      return ResourceStorageProvider.fromWire(await loader());
    }
    return ResourceStorageProvider.firebase;
  }
}
