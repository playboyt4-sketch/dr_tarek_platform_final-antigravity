import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../lecture/data/datasources/pdf_remote_data_source.dart';
import '../../../lecture/presentation/screens/pdf_viewer_screen.dart';
import '../../domain/entities/playback_entities.dart';
import '../controllers/video_playback_controller.dart';

/// A lecture resource the student can open from the player's documents
/// sheet: either the lecture PDF or an uploaded attachment (storage-
/// delivery audit Gap 1). [storageProvider] rides along opaquely — it is
/// forwarded to the Data layer exactly like PdfViewerScreen does, so this
/// Presentation code never branches on which backend serves the bytes.
@immutable
class OpenableLectureDocument {
  final String resourceId;
  final String title;
  final bool isPdf;
  final String storageProvider;

  const OpenableLectureDocument({
    required this.resourceId,
    required this.title,
    required this.isPdf,
    required this.storageProvider,
  });
}

/// Pure classification of callable resources into openable documents,
/// preserving display order (PDFs and attachments interleaved as delivered).
/// Kept side-effect-free for direct unit testing.
class LectureDocuments {
  static List<OpenableLectureDocument> fromResources(
    List<VideoResource> resources,
  ) {
    final documents = <OpenableLectureDocument>[];
    for (final resource in resources) {
      if (!resource.isDocument) continue;
      documents.add(
        OpenableLectureDocument(
          resourceId: resource.id,
          title: resource.title,
          isPdf: resource.resourceType == 'pdf',
          storageProvider: resource.storageProvider,
        ),
      );
    }
    return documents;
  }
}

/// Opens a document from the sheet: PDFs render through the existing
/// PdfViewerScreen pipeline (view + optional plan-gated download);
/// attachments download via the SAME provider-aware signed-URL callables
/// and hand off to the platform opener (zip/doc/xls cannot render inline).
class LectureDocumentActions {
  const LectureDocumentActions._();

  static Future<void> open(
    BuildContext context, {
    required OpenableLectureDocument document,
    String? subjectId,
    String? lectureId,
    VideoPlaybackController? videoController,
  }) async {
    if (document.isPdf) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            resourceId: document.resourceId,
            title: document.title,
            subjectId: subjectId,
            lectureId: lectureId,
            storageProvider: document.storageProvider,
            videoController: videoController,
          ),
        ),
      );
      return;
    }
    await _downloadAttachment(context, document);
  }

  /// Mirrors PdfViewerScreen._download(): provider-aware Data layer returns
  /// a short-lived URL (generateBunnyResourceUrl or generatePdfDownloadUrl),
  /// then the platform handles the actual bytes.
  static Future<void> _downloadAttachment(
    BuildContext context,
    OpenableLectureDocument document,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await PdfRemoteDataSource().getDownloadUrl(
        document.resourceId,
        storageProvider: document.storageProvider,
      );
      final uri = Uri.parse(result.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذر فتح المرفق.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(friendlyFunctionErrorMessage(error, 'تعذر تحميل المرفق.')),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر تحميل المرفق. حاول مرة أخرى.')),
      );
    }
  }
}

/// Bottom sheet listing the lecture's openable documents (PDF + مرفقات).
Future<void> showLectureDocumentsSheet(
  BuildContext context, {
  required List<OpenableLectureDocument> documents,
  String? subjectId,
  String? lectureId,
  VideoPlaybackController? videoController,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'ملفات المحاضرة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        document.isPdf
                            ? Icons.picture_as_pdf_outlined
                            : Icons.attach_file,
                        color: const Color(0xFF00c896),
                      ),
                      // Attachments are clearly labeled per audit Fix 1.
                      title: Text(
                        document.isPdf
                            ? document.title
                            : 'مرفق: ${document.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        document.isPdf ? 'عرض الملف' : 'تنزيل الملف',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        document.isPdf
                            ? Icons.arrow_forward_ios
                            : Icons.download_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(
                          LectureDocumentActions.open(
                            context,
                            document: document,
                            subjectId: subjectId,
                            lectureId: lectureId,
                            videoController: videoController,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
