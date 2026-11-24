import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../lecture/data/datasources/pdf_remote_data_source.dart';
import '../../../lecture/presentation/screens/pdf_viewer_screen.dart';
import '../../../pdf_viewer/presentation/providers/pdf_viewer_providers.dart';
import '../../../video_streaming/data/services/video_source_resolver.dart';
import '../../../video_streaming/presentation/components/video_documents_sheet.dart';
import '../../domain/entities/subject_learning_entities.dart';

/// Helper to persist offline downloaded state per lecture.
class LectureDownloadService {
  static const String _prefPrefix = 'offline_lecture_';
  static const String _resourcePrefPrefix = 'offline_lecture_res_';

  static Future<bool> isLectureDownloaded(String lectureId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefPrefix$lectureId') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getDownloadedResourceId(String lectureId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_resourcePrefPrefix$lectureId');
    } catch (_) {
      return null;
    }
  }

  static Future<void> markLectureDownloaded(
    String lectureId,
    String resourceId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefPrefix$lectureId', true);
      await prefs.setString('$_resourcePrefPrefix$lectureId', resourceId);
    } catch (_) {}
  }

  static Future<void> removeLectureDownloaded(String lectureId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefPrefix$lectureId');
      await prefs.remove('$_resourcePrefPrefix$lectureId');
    } catch (_) {}
  }
}

/// Interactive download button for lecture card on subject navigation page.
///
/// Features:
/// 1. Real-time checking if the lecture is already encrypted and saved in DRM.
/// 2. If downloaded: displays a green checkmark (`Icons.check_circle`).
///    Tapping gives options to open offline or delete the download.
/// 3. If downloading: displays a circular progress indicator with percentage.
/// 4. If not downloaded: displays `Icons.file_download_outlined`. Tapping
///    downloads the lecture resource (PDF/document) encrypted into the DRM vault.
class LectureDownloadButton extends ConsumerStatefulWidget {
  final LectureSummary lecture;
  final String subjectId;

  const LectureDownloadButton({
    super.key,
    required this.lecture,
    required this.subjectId,
  });

  @override
  ConsumerState<LectureDownloadButton> createState() =>
      _LectureDownloadButtonState();
}

class _LectureDownloadButtonState extends ConsumerState<LectureDownloadButton> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _resourceId;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final downloaded =
        await LectureDownloadService.isLectureDownloaded(widget.lecture.id);
    final resId =
        await LectureDownloadService.getDownloadedResourceId(widget.lecture.id);
    if (!mounted) return;

    if (downloaded && resId != null) {
      try {
        final drmRepo = await ref.read(drmRepositoryProvider.future);
        final hasFile = await drmRepo.hasEncryptedFile(
          subjectId: widget.subjectId,
          resourceId: resId,
        );
        if (mounted) {
          setState(() {
            _isDownloaded = hasFile;
            _resourceId = resId;
          });
        }
        return;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isDownloaded = downloaded;
        _resourceId = resId;
      });
    }
  }

  Future<void> _startDownload() async {
    if (widget.lecture.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المحاضرة مقفلة، يرجى تفعيل الاشتراك أولاً.'),
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final resources = await VideoSourceResolver(
        functions: FirebaseFunctions.instance,
      ).loadResources(widget.lecture.id);
      final documents = LectureDocuments.fromResources(resources);

      if (documents.isEmpty) {
        if (mounted) {
          setState(() => _isDownloading = false);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('لا توجد ملفات قابلة للتحميل أوفلاين لهذه المحاضرة.'),
            ),
          );
        }
        return;
      }

      final doc = documents.first;
      final result = await PdfRemoteDataSource().getDownloadUrl(
        doc.resourceId,
        storageProvider: doc.storageProvider,
      );

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(result.url));
      final response = await request.close();

      final total = response.contentLength;
      var received = 0;
      final bytes = <int>[];

      await for (final chunk in response) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() {
            _progress = received / total;
          });
        }
      }

      final userId = ref.read(authProvider).value?.id ?? 'offline_user';
      final drmRepo = await ref.read(drmRepositoryProvider.future);

      await drmRepo.saveEncryptedFile(
        subjectId: widget.subjectId,
        resourceId: doc.resourceId,
        plaintextBytes: bytes,
        userId: userId,
        expiresAt: result.expiresAt,
      );

      await LectureDownloadService.markLectureDownloaded(
        widget.lecture.id,
        doc.resourceId,
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isDownloaded = true;
          _resourceId = doc.resourceId;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'تم تحميل «${widget.lecture.title}» بنجاح ومتاحة للمذاكرة بدون إنترنت.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل المحاضرة. يرجى التحقق من اتصالك بالإنترنت.'),
          ),
        );
      }
    }
  }

  void _showDownloadedOptions() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.lecture.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'المحاضرة محملة ومحفوظة بشكل مشفر للمذاكرة بدون إنترنت.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text('فتح المحاضرة بدون إنترنت'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (_resourceId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            resourceId: _resourceId!,
                            title: widget.lecture.title,
                            subjectId: widget.subjectId,
                            lectureId: widget.lecture.id,
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف من التنزيلات'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (_resourceId != null) {
                      try {
                        final drmRepo =
                            await ref.read(drmRepositoryProvider.future);
                        await drmRepo.deleteEncryptedFile(
                          subjectId: widget.subjectId,
                          resourceId: _resourceId!,
                        );
                      } catch (_) {}
                    }
                    await LectureDownloadService.removeLectureDownloaded(
                      widget.lecture.id,
                    );
                    if (mounted) {
                      setState(() {
                        _isDownloaded = false;
                        _resourceId = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حذف المحاضرة من التنزيلات.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloading) {
      final percentage = (_progress * 100).toInt();
      return Tooltip(
        message: 'جارٍ التحميل $percentage%',
        child: SizedBox(
          width: context.rs(26),
          height: context.rs(26),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
                strokeWidth: 2.5,
                color: const Color(0xFF1D4ED8),
              ),
              if (_progress > 0)
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: context.rsFont(8),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_isDownloaded) {
      return IconButton(
        icon: Icon(
          Icons.check_circle,
          size: context.rs(23),
          color: const Color(0xFF10B981),
        ),
        tooltip: 'تم التحميل (اضغط للخيارات)',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: _showDownloadedOptions,
      );
    }

    return IconButton(
      icon: Icon(
        Icons.file_download_outlined,
        size: context.rs(23),
        color: Colors.black,
      ),
      tooltip: 'تحميل للمذاكرة بدون إنترنت',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: _startDownload,
    );
  }
}
