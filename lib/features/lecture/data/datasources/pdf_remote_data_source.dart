import 'package:cloud_functions/cloud_functions.dart';

/// Signed-URL delivery for protected PDFs/attachments.
///
/// FINAL_DECISIONS §15 dual-provider dispatch: the resource's
/// storage_provider (delivered through getLectureResources) decides which
/// authorized callable serves the bytes — Bunny-hosted resources go to
/// `generateBunnyResourceUrl` (same HMAC/token pattern as video), Firebase-
/// hosted ones keep `generateProtectedPdfUrl` / `generatePdfDownloadUrl`.
/// This branching lives HERE in the Data layer; the Presentation layer only
/// forwards the provider string it received with the resource and never
/// inspects it.
class PdfRemoteDataSource {
  final FirebaseFunctions _functions;

  PdfRemoteDataSource({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Get a signed URL for **viewing** (requires `pdf.access`).
  Future<PdfSignedUrlResult> getViewUrl(
    String resourceId, {
    String? storageProvider,
  }) async {
    if (storageProvider == 'bunny') {
      return _callBunny(resourceId, forDownload: false);
    }
    final data = await _call('generateProtectedPdfUrl', resourceId);
    return PdfSignedUrlResult(
      url: data['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
      canDownload: data['canDownload'] as bool? ?? false,
    );
  }

  /// Get a signed URL for **downloading** (requires `pdf.download`).
  Future<PdfSignedUrlResult> getDownloadUrl(
    String resourceId, {
    String? storageProvider,
  }) async {
    if (storageProvider == 'bunny') {
      return _callBunny(resourceId, forDownload: true);
    }
    final data = await _call('generatePdfDownloadUrl', resourceId);
    return PdfSignedUrlResult(
      url: data['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
      canDownload: true,
    );
  }

  Future<Map<String, dynamic>> _call(
    String callableName,
    String resourceId,
  ) async {
    final result =
        await _functions.httpsCallable(callableName).call({'resourceId': resourceId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<PdfSignedUrlResult> _callBunny(
    String resourceId, {
    required bool forDownload,
  }) async {
    final result = await _functions.httpsCallable('generateBunnyResourceUrl')
        .call({'resourceId': resourceId, 'forDownload': forDownload});
    final data = Map<String, dynamic>.from(result.data as Map);
    return PdfSignedUrlResult(
      url: data['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
      canDownload: forDownload,
    );
  }
}

class PdfSignedUrlResult {
  final String url;
  final DateTime expiresAt;
  final bool canDownload;

  const PdfSignedUrlResult({
    required this.url,
    required this.expiresAt,
    required this.canDownload,
  });
}
