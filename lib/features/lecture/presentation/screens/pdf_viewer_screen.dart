import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/friendly_error_message.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../authentication/presentation/providers/auth_provider.dart';
import '../../../membership/presentation/providers/membership_providers.dart';
import '../../../notes/presentation/providers/notes_providers.dart';
import '../../../video_streaming/domain/entities/playback_entities.dart';
import '../../../video_streaming/presentation/components/video_surface.dart';
import '../../../video_streaming/presentation/controllers/video_playback_controller.dart';
import '../../../video_streaming/presentation/providers/video_streaming_providers.dart';
import '../../../membership/presentation/screens/membership_plans_screen.dart';
import '../../../device_binding/presentation/providers/device_binding_provider.dart';
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

  const PdfViewerScreen({
    required this.resourceId,
    required this.title,
    this.subjectId,
    this.lectureId,
    this.storageProvider,
    this.videoController,
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
    _checkDownloadPermission();
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

    // 1. Validate device binding
    final deviceBindingRepo = ref.read(deviceBindingRepositoryProvider);
    final deviceInfo = await deviceBindingRepo.getDeviceInfo();
    final isValidDevice = await deviceBindingRepo.validateDevice(userId: userId, deviceInfo: deviceInfo);
    if (!isValidDevice) {
      throw Exception('هذا الجهاز غير مصرح له للوصول للمحاضرة.');
    }

    // 2. Validate subscription & features
    final subscriptionAsync = ref.read(activeSubscriptionProvider((
      studentId: userId,
      subjectId: widget.subjectId ?? '',
    )));
    final subscription = subscriptionAsync.value;
    if (subscription == null) {
      throw Exception('لا يوجد اشتراك نشط لهذه المادة.');
    }

    final features = await ref.read(planFeaturesProvider(subscription.planId).future);
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

    // 3. Load resource key and file from offline cache first (if offline, or if cached)
    final drmRepo = await ref.read(drmRepositoryProvider.future);
    final hasLocal = await drmRepo.hasEncryptedFile(resourceId: widget.resourceId);
    
    if (hasLocal) {
      // Revalidate pdf.offline entitlement
      final offlineFeature = features.where((f) => f.featureKey == 'pdf.offline').firstOrNull;
      final downloadFeature = features.where((f) => f.featureKey == 'pdf.download').firstOrNull;
      final canOffline = offlineFeature != null && offlineFeature.enabled && downloadFeature != null && downloadFeature.enabled;
      
      if (!canOffline) {
        // Entitlement revoked -> purge local cache immediately
        await drmRepo.deleteEncryptedFile(resourceId: widget.resourceId);
      } else {
        // Valid entitlement -> decrypt in memory
        final bytes = await drmRepo.getDecryptedFile(resourceId: widget.resourceId, userId: userId);
        if (bytes != null) {
          final tempPath = await _writeDecryptedToTemp(bytes);
          _isOfflineEnabled = true;
          return (urlResult: null, progress: record, tempFilePath: tempPath);
        }
      }
    }

    // 4. If not offline/cached, fetch signed URL (requires internet)
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw Exception('لا يوجد اتصال بالإنترنت والملف غير متوفر في الذاكرة المؤقتة.');
    }

    final urlResult = await _dataSource.getViewUrl(widget.resourceId, storageProvider: widget.storageProvider);
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
      // Disabling offline mode: purge local cache
      await drmRepo.deleteEncryptedFile(resourceId: widget.resourceId);
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

    // Check maximum offline limit
    final list = await drmRepo.listEncryptedResources();
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                    onTap: () {
                      Navigator.pop(context);
                      _showToast('ميزة البحث والفهرس ستكون متاحة قريباً.');
                    },
                  ),
                  const Divider(color: Color(0xFFe5e7eb)),
                  ListTile(
                    leading: const Icon(Icons.edit_document, color: Color(0xFF6b7280)),
                    title: const Text(
                      'الملاحظات الشخصية',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showNotesCreator(context);
                    },
                  ),
                  const Divider(color: Color(0xFFe5e7eb)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.offline_pin_outlined, color: Color(0xFF6b7280)),
                            SizedBox(width: 12),
                            Column(
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
                          ],
                        ),
                        Switch(
                          value: _isOfflineEnabled,
                          activeThumbColor: const Color(0xFF10b981),
                          activeTrackColor: const Color(0xFF10b981).withValues(alpha: 0.5),
                          onChanged: (value) async {
                            Navigator.pop(context);
                            await _toggleOfflineMode(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showNotesCreator(BuildContext context) {
    final noteController = TextEditingController();

    showModalBottomSheet(
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

    return Scaffold(
      backgroundColor: const Color(0xFFf4f6f8),
      appBar: AppBar(
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
                style: const TextStyle(fontSize: 11, color: Color(0xFF6b7280)),
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
              icon: const Icon(Icons.download_outlined, color: Colors.black87),
              tooltip: 'تحميل PDF',
              onPressed: _download,
            ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => _showMainMenu(context),
          ),
        ],
      ),
      body: FutureBuilder<({PdfSignedUrlResult? urlResult, PlaybackProgressRecord? progress, String? tempFilePath})>(
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

          // Render appropriate layout based on viewMode
          Widget content;
          if (_viewMode == 1 && hasVideo) {
            // Split screen mode
            content = Column(
              children: [
                SizedBox(
                  height: media.size.height * 0.35,
                  child: VideoSurface(controller: widget.videoController!),
                ),
                Expanded(child: buildPdfReader()),
              ],
            );
          } else if (_viewMode == 2 && hasVideo) {
            // Floating PDF mode
            content = Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: VideoSurface(controller: widget.videoController!),
                ),
                Positioned(
                  bottom: 24,
                  left: 16,
                  child: Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      width: 160,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: buildPdfReader(),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Full PDF mode
            content = buildPdfReader();
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (hasVideo)
                Positioned(
                  bottom: 24,
                  right: 24,
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
          );
        },
      ),
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
