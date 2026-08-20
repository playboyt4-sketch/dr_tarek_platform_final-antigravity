import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/datasources/pdf_remote_data_source.dart';

/// In-app PDF viewer that loads a protected PDF via signed URL.
/// Only requires `pdf.access` permission. Download button appears
/// only if `pdf.download` is separately granted.
class PdfViewerScreen extends StatefulWidget {
  final String resourceId;
  final String title;

  const PdfViewerScreen({
    required this.resourceId,
    required this.title,
    super.key,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfRemoteDataSource _dataSource = PdfRemoteDataSource();

  late Future<PdfSignedUrlResult> _viewUrlFuture;
  bool _canDownload = false;
  bool _downloadChecked = false;
  int _currentPage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _viewUrlFuture = _dataSource.getViewUrl(widget.resourceId);
    _checkDownloadPermission();
  }

  Future<void> _checkDownloadPermission() async {
    try {
      await _dataSource.getDownloadUrl(widget.resourceId);
      if (mounted) setState(() => _canDownload = true);
    } catch (_) {
      // pdf.download not enabled — button stays hidden
    } finally {
      if (mounted) setState(() => _downloadChecked = true);
    }
  }

  Future<void> _download() async {
    try {
      final result = await _dataSource.getDownloadUrl(widget.resourceId);
      final uri = Uri.parse(result.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح رابط التحميل.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'تحميل الملف غير متاح.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_downloadChecked && _canDownload)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'تحميل PDF',
              onPressed: _download,
            ),
        ],
        bottom: _totalPages > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'صفحة ${_currentPage + 1} من $_totalPages',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              )
            : null,
      ),
      body: FutureBuilder<PdfSignedUrlResult>(
        future: _viewUrlFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final message = snapshot.error is FirebaseFunctionsException
                ? (snapshot.error as FirebaseFunctionsException).message ??
                    'تعذر تحميل الملف.'
                : 'حدث خطأ أثناء تحميل الملف.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _viewUrlFuture = _dataSource.getViewUrl(widget.resourceId);
                        });
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          final url = snapshot.data!.url;
          return PDF(
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            fitPolicy: FitPolicy.WIDTH,
            onPageChanged: (page, total) {
              if (mounted) {
                setState(() {
                  _currentPage = page ?? 0;
                  _totalPages = total ?? _totalPages;
                });
              }
            },
            onRender: (pages) {
              if (mounted) {
                setState(() {
                  _totalPages = pages ?? 0;
                });
              }
            },
          ).cachedFromUrl(
            url,
            placeholder: (progress) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(value: progress / 100),
                  const SizedBox(height: 12),
                  Text('جاري تحميل الملف... $progress%'),
                ],
              ),
            ),
            errorWidget: (error) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('فشل عرض الملف: $error', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
