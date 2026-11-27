import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../membership/presentation/providers/membership_providers.dart';
import '../../../notes/presentation/providers/notes_providers.dart';
import '../../../video_streaming/domain/entities/playback_entities.dart';
import '../../../video_streaming/presentation/components/video_surface.dart';
import '../../../video_streaming/presentation/controllers/video_playback_controller.dart';
import '../../../video_streaming/presentation/providers/video_streaming_providers.dart';
import '../../../membership/presentation/screens/membership_plans_screen.dart';
import '../../../pdf_viewer/presentation/providers/pdf_viewer_providers.dart';
import '../../data/datasources/pdf_remote_data_source.dart';

/// In-app PDF viewer that loads a protected PDF via signed URL or decrypts it locally from DRM.
/// Supports Full Screen, Split-Screen, and Floating PDF layouts matching docs/pdf viewer.html.
class PdfViewerScreen extends ConsumerStatefulWidget {
  final String resourceId;
  final String title;
  final String? subjectId;
  final String? lectureId;

  /// Dual-provider key delivered with the resource metadata
  /// (FINAL_DECISIONS §15). Forwarded opaquely to the Data layer — this
  /// widget never branches on it.
  final String? storageProvider;
  final VideoPlaybackController? videoController;

  /// When true, renders as a self-contained floating, draggable & resizable
  /// PDF window over an active [VideoStreamingScreen] without pushing a new
  /// full-screen route or drawing a screen-wide AppBar.
  final bool embeddedOverlay;
  final VoidCallback? onClose;

  const PdfViewerScreen({
    required this.resourceId,
    required this.title,
    this.subjectId,
    this.lectureId,
    this.storageProvider,
    this.videoController,
    this.embeddedOverlay = false,
    this.onClose,
    super.key,
  });

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final PdfRemoteDataSource _dataSource = PdfRemoteDataSource();

  late Future<({PdfSignedUrlResult? urlResult, PlaybackProgressRecord? progress, String? tempFilePath})> _initializationFuture;
  bool _canDownload = false;
  bool _downloadChecked = false;
  int _currentPage = 0;
  int _totalPages = 0;
  int _viewMode = 0; // 0: Full PDF, 1: Split Screen, 2: Floating PDF
  bool _isOfflineEnabled = false;
  int? _offlineMaxLimit;
  String? _tempFilePath;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeData();
  }

  static const Set<String> _transientFunctionCodes = {
    'unavailable',
    'deadline-exceeded',
    'aborted',
    'internal',
    'unknown',
    'unauthenticated',
  };

  bool _isTransientPdfError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    if (error is FirebaseFunctionsException) {
      return _transientFunctionCodes.contains(error.code.toLowerCase());
    }
    if (error is FirebaseException) {
      return _transientFunctionCodes.contains(error.code.toLowerCase()) ||
          error.code == 'network-request-failed';
    }
    return false;
  }

  Future<T> _runWithSilentRetry<T>(
    Future<T> Function() action, {
    int maxSilentRetries = 2,
    Future<void> Function(Object error, int attempt)? onRetry,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= maxSilentRetries; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (attempt >= maxSilentRetries || !_isTransientPdfError(error)) {
          rethrow;
        }
        if (onRetry != null) {
          await onRetry(error, attempt);
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  @override
  void dispose() {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    super.dispose();
  }

  Future<String> _writeDecryptedToTemp(List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_${widget.resourceId}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    _tempFilePath = file.path;
    return file.path;
  }

  Future<({PdfSignedUrlResult? urlResult, PlaybackProgressRecord? progress, String? tempFilePath})> _initializeData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final lectureId = widget.lectureId;
    if (userId == null || lectureId == null) {
      throw Exception('مستخدم غير مصرح له.');
    }

    // 1. Device authorization is enforced server-side per Subject (ADR-004):
    // signed-URL issuance resolves the Full vs Guest tier, so no client
    // global device gate exists here. A Guest device receives limited
    // online preview and is never issued protected offline keys.

    // 2. Validate subscription & features (await .future so first-open does not
    // race while activeSubscriptionProvider is still AsyncLoading).
    final subArgs = (
      studentId: userId,
      subjectId: widget.subjectId ?? '',
    );
    final subscription = await _runWithSilentRetry(
      () => ref.read(activeSubscriptionProvider(subArgs).future),
      maxSilentRetries: 1,
      onRetry: (_, _) async {
        ref.invalidate(activeSubscriptionProvider(subArgs));
      },
    );
    if (subscription == null) {
      throw Exception('لا يوجد اشتراك نشط لهذه المادة.');
    }

    final features = await _runWithSilentRetry(
      () => ref.read(planFeaturesProvider(subscription.planId).future),
      maxSilentRetries: 1,
      onRetry: (_, _) async {
        ref.invalidate(planFeaturesProvider(subscription.planId));
      },
    );
    final accessFeature = features.where((f) => f.featureKey == 'pdf.access').firstOrNull;
    if (accessFeature == null || !accessFeature.enabled) {
      throw Exception('ليس لديك صلاحية لمشاهدة هذا الملف.');
    }

    // Get max offline limit
    final offlineMaxFeature = features.where((f) => f.featureKey == 'pdf.offline_max_files').firstOrNull;
    if (offlineMaxFeature != null) {
      final valueStr = offlineMaxFeature.featureValue?.toString();
      _offlineMaxLimit = int.tryParse(valueStr?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 5;
    }
    final downloadFeature = features.where((f) => f.featureKey == 'pdf.download').firstOrNull;
    final hasDownloadPlanFeature = downloadFeature?.enabled == true;

    // Load progress
    PlaybackProgressRecord? record;
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final repo = playbackRepositoryFor(userId: userId, preferences: preferences);
      record = await repo.read(lectureId);
      if (record?.pdfLastPage != null && record!.pdfLastPage! > 0) {
        _currentPage = record.pdfLastPage! - 1;
      }
    } catch (_) {}

    // 3. Load resource key and file from this Subject's offline partition
    // first (if offline, or if cached). Without a Subject there is no
    // partition to read, so offline is skipped (fail closed).
    final drmRepo = await ref.read(drmRepositoryProvider.future);
    final offlineSubjectId = widget.subjectId;
    final hasLocal = offlineSubjectId == null
        ? false
        : await drmRepo.hasEncryptedFile(subjectId: offlineSubjectId, resourceId: widget.resourceId);

    final offlineSubject = offlineSubjectId;
    if (hasLocal && offlineSubject != null) {
      // Revalidate pdf.offline entitlement
      final offlineFeature = features.where((f) => f.featureKey == 'pdf.offline').firstOrNull;
      final canOffline = offlineFeature != null && offlineFeature.enabled && hasDownloadPlanFeature;

      if (!canOffline) {
        // Entitlement revoked -> purge this Subject's local cache immediately
        await drmRepo.deleteEncryptedFile(subjectId: offlineSubject, resourceId: widget.resourceId);
      } else {
        // Valid entitlement -> decrypt in memory
        final bytes = await drmRepo.getDecryptedFile(subjectId: offlineSubject, resourceId: widget.resourceId, userId: userId);
        if (bytes != null) {
          final tempPath = await _writeDecryptedToTemp(bytes);
          _isOfflineEnabled = true;
          if (mounted) {
            setState(() {
              _canDownload = hasDownloadPlanFeature;
              _downloadChecked = true;
            });
          }
          return (urlResult: null, progress: record, tempFilePath: tempPath);
        }
      }
    }

    // 4. If not offline/cached, fetch signed URL (requires internet)
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      connectivityResult = await Connectivity().checkConnectivity();
    }
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw Exception('لا يوجد اتصال بالإنترنت والملف غير متوفر في الذاكرة المؤقتة.');
    }

    // Ensure auth token is warm before the first protected callable request.
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    final urlResult = await _runWithSilentRetry(
      () => _dataSource.getViewUrl(
        widget.resourceId,
        storageProvider: widget.storageProvider,
      ),
      maxSilentRetries: 2,
      onRetry: (error, _) async {
        if (error is FirebaseFunctionsException &&
            error.code.toLowerCase() == 'unauthenticated') {
          try {
            await FirebaseAuth.instance.currentUser?.getIdToken(true);
          } catch (_) {}
        }
      },
    );

    if (hasDownloadPlanFeature) {
      unawaited(_checkDownloadPermission());
    } else if (mounted) {
      setState(() {
        _canDownload = false;
        _downloadChecked = true;
      });
    }

    return (urlResult: urlResult, progress: record, tempFilePath: null);
  }

  Future<void> _checkDownloadPermission() async {
    try {
      await _dataSource.getDownloadUrl(widget.resourceId, storageProvider: widget.storageProvider);
      if (mounted) setState(() => _canDownload = true);
    } catch (_) {
      // pdf.download not enabled — button stays hidden
    } finally {
      if (mounted) setState(() => _downloadChecked = true);
    }
  }

  Future<void> _download() async {
    try {
      final result = await _dataSource.getDownloadUrl(widget.resourceId, storageProvider: widget.storageProvider);
      final uri = Uri.parse(result.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        _showToast('تعذر فتح رابط التحميل.');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        _showToast(friendlyFunctionErrorMessage(e, 'تحميل الملف غير متاح.'));
      }
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.only(bottom: 100, left: 60, right: 60),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveProgress(int page, int total) async {
    final lectureId = widget.lectureId;
    final subjectId = widget.subjectId;
    if (lectureId == null) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final repo = playbackRepositoryFor(userId: userId, preferences: preferences);

      final pageNumber = page + 1;
      final progressPercent = total > 0 ? pageNumber / total : 0.0;
      final completed = progressPercent >= 0.95;

      final record = PlaybackProgressRecord(
        userId: userId,
        lectureId: lectureId,
        subjectId: subjectId,
        position: Duration.zero,
        duration: Duration.zero,
        progressPercent: progressPercent,
        completed: completed,
        updatedAt: DateTime.now(),
        pdfLastPage: pageNumber,
        pdfTotalPages: total,
      );

      await repo.save(record);
    } catch (_) {}
  }

  Future<void> _toggleOfflineMode(bool enabled) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final subjectId = widget.subjectId;
    if (userId == null || subjectId == null) return;

    final drmRepo = await ref.read(drmRepositoryProvider.future);

    if (!enabled) {
      // Disabling offline mode: purge this Subject's local cache
      await drmRepo.deleteEncryptedFile(subjectId: subjectId, resourceId: widget.resourceId);
      setState(() => _isOfflineEnabled = false);
      _showToast('تم إزالة الملف من الذاكرة المحلية.');
      return;
    }

    // Enabling offline mode: check entitlements
    final subscriptionAsync = ref.read(activeSubscriptionProvider((
      studentId: userId,
      subjectId: subjectId,
    )));
    final subscription = subscriptionAsync.value;
    if (subscription == null) {
      _showToast('لا يوجد اشتراك نشط لتحميل الملف.');
      return;
    }

    final features = await ref.read(planFeaturesProvider(subscription.planId).future);
    final accessFeature = features.where((f) => f.featureKey == 'pdf.access').firstOrNull;
    final offlineFeature = features.where((f) => f.featureKey == 'pdf.offline').firstOrNull;
    final downloadFeature = features.where((f) => f.featureKey == 'pdf.download').firstOrNull;

    if (accessFeature?.enabled == true && accessFeature?.featureValue == 'Preview') {
      _showToast('غير مسموح بتحميل النسخة التجريبية للمذاكرة بدون اتصال.');
      return;
    }

    final canOffline = offlineFeature != null && offlineFeature.enabled && downloadFeature != null && downloadFeature.enabled;
    if (!canOffline) {
      _showToast('خطتك الحالية لا تدعم المذاكرة بدون اتصال.');
      return;
    }

    // Check maximum offline limit within this Subject's partition
    final list = await drmRepo.listEncryptedResources(subjectId: subjectId);
    if (_offlineMaxLimit != null && list.length >= _offlineMaxLimit!) {
      _showToast('لقد وصلت للحد الأقصى للملفات المحملة ($_offlineMaxLimit ملفات).');
      return;
    }

    if (!mounted) return;

    // Capture navigator
    final navigator = Navigator.of(context);

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final downloadResult = await _dataSource.getDownloadUrl(widget.resourceId, storageProvider: widget.storageProvider);
      
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(downloadResult.url));
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }

      final expiresAt = subscription.endDate ?? DateTime.now().add(const Duration(days: 30));
      await drmRepo.saveEncryptedFile(
        subjectId: subjectId,
        resourceId: widget.resourceId,
        plaintextBytes: bytes,
        userId: userId,
        expiresAt: expiresAt,
      );

      if (mounted) {
        navigator.pop(); // Dismiss loading
        setState(() => _isOfflineEnabled = true);
        _showToast('تم حفظ الملف بنجاح للمذاكرة بدون اتصال.');
      }
    } catch (_) {
      if (mounted) {
        navigator.pop(); // Dismiss loading
        _showToast('فشل تحميل الملف للتخزين المؤقت.');
      }
    }
  }

  void _showMainMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext modalContext) {
        return PdfViewerMainMenuSheet(
          isOfflineEnabled: _isOfflineEnabled,
          onSearchTap: () {
            Navigator.pop(modalContext);
            _showToast('ميزة البحث والفهرس ستكون متاحة قريباً.');
          },
          onNotesTap: () {
            Navigator.pop(modalContext);
            _showNotesCreator(this.context);
          },
          onOfflineChanged: (bool value) async {
            Navigator.pop(modalContext);
            await _toggleOfflineMode(value);
          },
        );
      },
    );
  }

  Future<void> _showNotesCreator(BuildContext context) async {
    final noteController = TextEditingController();

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إضافة ملاحظة (صفحة ${_currentPage + 1})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFfffbeb),
                    border: Border.all(color: const Color(0xFFf59e0b).withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TextField(
                     controller: noteController,
                     maxLines: 4,
                     decoration: const InputDecoration(
                       border: InputBorder.none,
                       hintText: 'اكتب ملاحظتك الشخصية هنا...',
                       hintStyle: TextStyle(color: Color(0xFFd97706), fontSize: 13),
                     ),
                     style: const TextStyle(color: Color(0xFF78350f), fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final text = noteController.text.trim();
                      if (text.isEmpty) return;

                      Navigator.pop(context);

                      final userId = FirebaseAuth.instance.currentUser?.uid;
                      final subjectId = widget.subjectId;
                      final lectureId = widget.lectureId;

                      if (userId != null && subjectId != null && lectureId != null) {
                        try {
                          final repo = ref.read(notesRepositoryProvider);
                          await repo.createNote(
                            studentId: userId,
                            subjectId: subjectId,
                            lectureId: lectureId,
                            content: text,
                            pdfPageNumber: _currentPage + 1,
                          );
                          _showToast('تم حفظ الملاحظة بنجاح.');
                        } catch (e) {
                          _showToast('تعذر حفظ الملاحظة.');
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFf59e0b),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'حفظ الملاحظة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    noteController.dispose();
  }
}

  void _switchViewMode() {
    setState(() {
      _viewMode = (_viewMode + 1) % 3;
    });
    if (_viewMode == 0) {
      _showToast('وضع القراءة الكامل');
    } else if (_viewMode == 1) {
      _showToast('وضع الشاشة المنقسمة');
    } else {
      _showToast('وضع الـ PDF العائم');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final user = ref.watch(authProvider).value;

    int? previewPagesLimit;
    if (user != null && widget.subjectId != null) {
      final subscriptionAsync = ref.watch(activeSubscriptionProvider((
        studentId: user.id,
        subjectId: widget.subjectId!,
      )));
      final subscription = subscriptionAsync.value;
      if (subscription != null) {
        final planFeaturesAsync = ref.watch(planFeaturesProvider(subscription.planId));
        final features = planFeaturesAsync.value;
        if (features != null) {
          final accessFeature = features.where((f) => f.featureKey == 'pdf.access').firstOrNull;
          if (accessFeature != null && accessFeature.enabled) {
            final previewPagesFeature = features.where((f) => f.featureKey == 'pdf.preview_pages').firstOrNull;
            if (previewPagesFeature != null) {
              final valueStr = previewPagesFeature.featureValue?.toString();
              previewPagesLimit = int.tryParse(valueStr?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ?? 5;
            }
          }
        }
      }
    }

    final hasVideo = widget.videoController != null;

    final bodyFuture = FutureBuilder<({PdfSignedUrlResult? urlResult, PlaybackProgressRecord? progress, String? tempFilePath})>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final message = friendlyFunctionErrorMessage(error, 'تعذر تحميل الملف. حاول مرة أخرى.');
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
                          _initializationFuture = _initializeData();
                        });
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          final isOfflineMode = snapshot.data!.tempFilePath != null;
          final url = snapshot.data!.urlResult?.url;

          // Watermark overlay
          Widget buildWatermark() {
            return Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Transform.rotate(
                    angle: -30 * 3.1415926535 / 180,
                    child: Opacity(
                      opacity: 0.05,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Dr. Tarek Platform',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                          if (user != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${user.fullName}\n${user.phoneNumber}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // PDF reader stack containing viewer, watermark and possible lock overlay
          Widget buildPdfReader() {
            final isLocked = previewPagesLimit != null && _currentPage >= previewPagesLimit;

            final pdfViewer = isOfflineMode
                ? PDF(
                    swipeHorizontal: false,
                    autoSpacing: true,
                    pageFling: true,
                    fitPolicy: FitPolicy.WIDTH,
                    defaultPage: _currentPage,
                    onPageChanged: (page, total) {
                      if (mounted && page != null && total != null) {
                        setState(() {
                          _currentPage = page;
                          _totalPages = total;
                        });
                        unawaited(_saveProgress(page, total));
                      }
                    },
                    onRender: (pages) {
                      if (mounted && pages != null) {
                        setState(() {
                          _totalPages = pages;
                        });
                      }
                    },
                  ).fromPath(
                    snapshot.data!.tempFilePath!,
                  )
                : PDF(
                    swipeHorizontal: false,
                    autoSpacing: true,
                    pageFling: true,
                    fitPolicy: FitPolicy.WIDTH,
                    defaultPage: _currentPage,
                    onPageChanged: (page, total) {
                      if (mounted && page != null && total != null) {
                        setState(() {
                          _currentPage = page;
                          _totalPages = total;
                        });
                        unawaited(_saveProgress(page, total));
                      }
                    },
                    onRender: (pages) {
                      if (mounted && pages != null) {
                        setState(() {
                          _totalPages = pages;
                        });
                      }
                    },
                  ).cachedFromUrl(
                    url!,
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
                    errorWidget: (_) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                            const SizedBox(height: 12),
                            const Text('فشل عرض الملف. يرجى المحاولة مرة أخرى.', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _initializationFuture = _initializeData();
                                });
                              },
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

            return Stack(
              fit: StackFit.expand,
              children: [
                pdfViewer,
                buildWatermark(),
                if (isLocked)
                  _LockedPageOverlay(
                    onSubscribe: () {
                      if (user != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MembershipPlansScreen(user: user),
                          ),
                        );
                      }
                    },
                  ),
              ],
            );
          }

          // When embedded as a floating overlay directly on top of
          // VideoStreamingScreen, return only the PDF reader surface; the
          // ResizableFloatingPdfWindow chrome wraps it below without replacing
          // the full-screen video player underneath.
          if (widget.embeddedOverlay) {
            return buildPdfReader();
          }

          // Render appropriate layout based on viewMode
          // (`docs/pdf viewer.html`: split = video 40% + pdf 60%;
          // floating = fullscreen video + draggable/resizable pdf card).
          Widget content;
          if (_viewMode == 1 && hasVideo) {
            // Split screen mode
            content = Column(
              children: [
                SizedBox(
                  height: media.size.height * 0.40,
                  child: VideoSurface(controller: widget.videoController!),
                ),
                Expanded(child: buildPdfReader()),
              ],
            );
          } else if (_viewMode == 2 && hasVideo) {
            // Floating PDF mode (draggable + resizable within SafeArea bounds)
            content = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: VideoSurface(controller: widget.videoController!),
                ),
                Positioned.fill(
                  child: SafeArea(
                    top: false,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        return ResizableFloatingPdfWindow(
                          areaWidth: constraints.maxWidth,
                          areaHeight: constraints.maxHeight,
                          initialWidth: context.rs(180),
                          initialHeight: context.rsV(260),
                          child: buildPdfReader(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Full PDF mode
            content = buildPdfReader();
          }

          return SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                content,
                if (hasVideo)
                  Positioned(
                    bottom: media.padding.bottom + context.rsV(24),
                    right: media.padding.right + context.rs(24),
                    child: FloatingActionButton(
                      onPressed: _switchViewMode,
                      backgroundColor: const Color(0xFF2563eb),
                      foregroundColor: Colors.white,
                      child: Icon(
                        _viewMode == 0
                            ? Icons.splitscreen
                            : _viewMode == 1
                                ? Icons.picture_in_picture_outlined
                                : Icons.fullscreen,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

    if (widget.embeddedOverlay) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final initW = math.min(
            math.max(constraints.maxWidth * 0.48, 220.0),
            constraints.maxWidth - 16.0,
          );
          final initH = math.min(
            math.max(constraints.maxHeight * 0.78, 200.0),
            constraints.maxHeight - 16.0,
          );
          return ResizableFloatingPdfWindow(
            areaWidth: constraints.maxWidth,
            areaHeight: constraints.maxHeight,
            initialWidth: initW,
            initialHeight: initH,
            title: widget.title,
            pageLabel: _totalPages > 0 ? '${_currentPage + 1}/$_totalPages' : null,
            onCloseTap: widget.onClose,
            onMenuTap: () => _showMainMenu(context),
            onDownloadTap: (_downloadChecked && _canDownload)
                ? (_isOfflineEnabled
                    ? () => _showToast('الملف محفوظ بالفعل للمذاكرة بدون إنترنت.')
                    : _download)
                : null,
            isOfflineEnabled: _isOfflineEnabled,
            child: bodyFuture,
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFf4f6f8),
      // Top bar per `docs/pdf viewer.html`: fixed 60px, white surface,
      // title 15/w600 + page counter 12/secondary, back + menu actions.
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            if (_totalPages > 0) ...[
              const SizedBox(height: 2),
              Text(
                'صفحة ${_currentPage + 1} من $_totalPages',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6b7280)),
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_downloadChecked && _canDownload)
            IconButton(
              icon: Icon(
                _isOfflineEnabled ? Icons.check_circle : Icons.download_outlined,
                color: _isOfflineEnabled ? const Color(0xFF10B981) : Colors.black87,
              ),
              tooltip: _isOfflineEnabled ? 'تم التحميل أوفلاين' : 'تحميل PDF للمذاكرة بدون إنترنت',
              onPressed: _isOfflineEnabled
                  ? () => _showToast('الملف محفوظ بالفعل للمذاكرة بدون إنترنت.')
                  : _download,
            ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => _showMainMenu(context),
          ),
        ],
      ),
      body: bodyFuture,
    );
  }
}

class _LockedPageOverlay extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _LockedPageOverlay({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Color(0xFFf59e0b),
              ),
              const SizedBox(height: 16),
              const Text(
                'الصفحة مغلقة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'هذه الصفحة غير متاحة في النسخة التجريبية. يرجى الاشتراك في إحدى باقاتنا لمشاهدة كامل الملف.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onSubscribe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563eb),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'الاشتراكات والخطط',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable, SafeArea-aware main menu bottom sheet for the PDF viewer.
class PdfViewerMainMenuSheet extends StatelessWidget {
  final bool isOfflineEnabled;
  final VoidCallback onSearchTap;
  final VoidCallback onNotesTap;
  final ValueChanged<bool> onOfflineChanged;

  const PdfViewerMainMenuSheet({
    super.key,
    required this.isOfflineEnabled,
    required this.onSearchTap,
    required this.onNotesTap,
    required this.onOfflineChanged,
  });

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFe5e7eb),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.search, color: Color(0xFF6b7280)),
                title: const Text(
                  'البحث والفهرس',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: onSearchTap,
              ),
              const Divider(color: Color(0xFFe5e7eb)),
              ListTile(
                leading: const Icon(Icons.edit_document, color: Color(0xFF6b7280)),
                title: const Text(
                  'الملاحظات الشخصية',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: onNotesTap,
              ),
              const Divider(color: Color(0xFFe5e7eb)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.offline_pin_outlined, color: Color(0xFF6b7280)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Offline mode',
                                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                ),
                                Text(
                                  'متاح داخل التطبيق فقط',
                                  style: TextStyle(color: Color(0xFF6b7280), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isOfflineEnabled,
                      activeThumbColor: const Color(0xFF10b981),
                      activeTrackColor: const Color(0xFF10b981).withValues(alpha: 0.5),
                      onChanged: onOfflineChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draggable and resizable floating PDF window for PiP/floating mode.
///
/// Moving is handled by the top drag bar and resizing by the bottom-right
/// corner handle so neither conflicts with PDF internal scroll/zoom gestures.
class ResizableFloatingPdfWindow extends StatefulWidget {
  final double areaWidth;
  final double areaHeight;
  final double initialWidth;
  final double initialHeight;
  final Widget child;
  final String? title;
  final String? pageLabel;
  final VoidCallback? onCloseTap;
  final VoidCallback? onMenuTap;
  final VoidCallback? onDownloadTap;
  final bool isOfflineEnabled;

  const ResizableFloatingPdfWindow({
    super.key,
    required this.areaWidth,
    required this.areaHeight,
    required this.initialWidth,
    required this.initialHeight,
    required this.child,
    this.title,
    this.pageLabel,
    this.onCloseTap,
    this.onMenuTap,
    this.onDownloadTap,
    this.isOfflineEnabled = false,
  });

  @override
  State<ResizableFloatingPdfWindow> createState() =>
      _ResizableFloatingPdfWindowState();
}

class _ResizableFloatingPdfWindowState
    extends State<ResizableFloatingPdfWindow> {
  static const double _edgeMargin = 8.0;
  static const double _minWidthBase = 140.0;
  static const double _minHeightBase = 180.0;

  late double _left;
  late double _top;
  late double _width;
  late double _height;
  bool _initialized = false;

  double get _minWidth =>
      math.min(_minWidthBase, math.max(80.0, widget.areaWidth - _edgeMargin * 2));

  double get _minHeight => math.min(
      _minHeightBase, math.max(100.0, widget.areaHeight - _edgeMargin * 2));

  double get _maxWidth =>
      math.max(_minWidth, widget.areaWidth - _edgeMargin * 2);

  double get _maxHeight =>
      math.max(_minHeight, widget.areaHeight - _edgeMargin * 2);

  void _ensureBounds({bool resetIfUninitialized = false}) {
    if (!_initialized && resetIfUninitialized) {
      _width = widget.initialWidth.clamp(_minWidth, _maxWidth);
      _height = widget.initialHeight.clamp(_minHeight, _maxHeight);
      final double maxLeft =
          math.max(_edgeMargin, widget.areaWidth - _width - _edgeMargin);
      final double maxTop =
          math.max(_edgeMargin, widget.areaHeight - _height - _edgeMargin);
      _left = (_edgeMargin + 8.0).clamp(_edgeMargin, maxLeft);
      _top = (widget.areaHeight - _height - 24.0).clamp(_edgeMargin, maxTop);
      _initialized = true;
      return;
    }

    _width = _width.clamp(_minWidth, _maxWidth);
    _height = _height.clamp(_minHeight, _maxHeight);
    final double maxLeft =
        math.max(_edgeMargin, widget.areaWidth - _width - _edgeMargin);
    final double maxTop =
        math.max(_edgeMargin, widget.areaHeight - _height - _edgeMargin);
    _left = _left.clamp(_edgeMargin, maxLeft);
    _top = _top.clamp(_edgeMargin, maxTop);
  }

  @override
  void initState() {
    super.initState();
    _ensureBounds(resetIfUninitialized: true);
  }

  @override
  void didUpdateWidget(covariant ResizableFloatingPdfWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.areaWidth != widget.areaWidth ||
        oldWidget.areaHeight != widget.areaHeight) {
      _ensureBounds();
    }
  }

  void _onMoveDrag(DragUpdateDetails details) {
    setState(() {
      final double maxLeft =
          math.max(_edgeMargin, widget.areaWidth - _width - _edgeMargin);
      final double maxTop =
          math.max(_edgeMargin, widget.areaHeight - _height - _edgeMargin);
      _left = (_left + details.delta.dx).clamp(_edgeMargin, maxLeft);
      _top = (_top + details.delta.dy).clamp(_edgeMargin, maxTop);
    });
  }

  void _onResizeDrag(DragUpdateDetails details) {
    setState(() {
      final double maxWidthAtPos =
          math.max(_minWidth, widget.areaWidth - _edgeMargin - _left);
      final double maxHeightAtPos =
          math.max(_minHeight, widget.areaHeight - _edgeMargin - _top);
      _width = (_width + details.delta.dx).clamp(_minWidth, maxWidthAtPos);
      _height = (_height + details.delta.dy).clamp(_minHeight, maxHeightAtPos);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          key: const Key('floating-pdf-window'),
          left: _left,
          top: _top,
          width: _width,
          height: _height,
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        key: const Key('floating-pdf-drag-handle'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _onMoveDrag,
                        child: Container(
                          height: (widget.onCloseTap != null ||
                                  widget.onMenuTap != null ||
                                  widget.title != null)
                              ? 38
                              : 28,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                          ),
                          child: (widget.onCloseTap != null ||
                                  widget.onMenuTap != null ||
                                  widget.title != null)
                              ? Row(
                                  children: [
                                    if (widget.onCloseTap != null)
                                      IconButton(
                                        key: const Key('floating-pdf-close-btn'),
                                        tooltip: 'إغلاق الـ PDF',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        iconSize: 18,
                                        color: const Color(0xFF111827),
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: widget.onCloseTap,
                                      ),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 3,
                                            margin: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF9CA3AF),
                                              borderRadius:
                                                  BorderRadius.circular(9999),
                                            ),
                                          ),
                                          if (widget.title != null)
                                            Text(
                                              widget.pageLabel != null
                                                  ? '${widget.title} (${widget.pageLabel})'
                                                  : widget.title!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (widget.onDownloadTap != null)
                                      IconButton(
                                        tooltip: widget.isOfflineEnabled
                                            ? 'محفوظ أوفلاين'
                                            : 'تحميل PDF',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        iconSize: 17,
                                        color: widget.isOfflineEnabled
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF111827),
                                        icon: Icon(
                                          widget.isOfflineEnabled
                                              ? Icons.check_circle
                                              : Icons.download_outlined,
                                        ),
                                        onPressed: widget.onDownloadTap,
                                      ),
                                    if (widget.onMenuTap != null)
                                      IconButton(
                                        key: const Key('floating-pdf-menu-btn'),
                                        tooltip: 'قائمة الـ PDF',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        iconSize: 18,
                                        color: const Color(0xFF111827),
                                        icon: const Icon(Icons.menu_rounded),
                                        onPressed: widget.onMenuTap,
                                      ),
                                  ],
                                )
                              : Center(
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF9CA3AF),
                                      borderRadius: BorderRadius.circular(9999),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Expanded(child: widget.child),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      key: const Key('floating-pdf-resize-handle'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _onResizeDrag,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xE6FFFFFF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD1D5DB)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: _ResizeCornerPainter(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResizeCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.78),
      Offset(size.width * 0.78, size.height * 0.42),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.78),
      Offset(size.width * 0.78, size.height * 0.62),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ResizeCornerPainter oldDelegate) => false;
}
