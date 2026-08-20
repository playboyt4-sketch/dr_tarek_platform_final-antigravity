import 'package:cloud_functions/cloud_functions.dart';

/// Provides signed URLs for viewing and downloading protected PDFs.
class PdfRemoteDataSource {
  final FirebaseFunctions _functions;

  PdfRemoteDataSource({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Get a signed URL for **viewing** (requires `pdf.access`).
  Future<PdfSignedUrlResult> getViewUrl(String resourceId) async {
    final callable = _functions.httpsCallable('generateProtectedPdfUrl');
    final result = await callable.call({'resourceId': resourceId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return PdfSignedUrlResult(
      url: data['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
      canDownload: data['canDownload'] as bool? ?? false,
    );
  }

  /// Get a signed URL for **downloading** (requires `pdf.download`).
  Future<PdfSignedUrlResult> getDownloadUrl(String resourceId) async {
    final callable = _functions.httpsCallable('generatePdfDownloadUrl');
    final result = await callable.call({'resourceId': resourceId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return PdfSignedUrlResult(
      url: data['url'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
      canDownload: true,
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
