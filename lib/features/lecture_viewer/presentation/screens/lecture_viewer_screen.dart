import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Three-state layout for the lecture viewer.
///
/// - [fullPdf]: PDF occupies 100% of the screen, video hidden.
/// - [splitScreen]: video on top (40% flex), PDF on bottom (60% flex).
/// - [floatingPdf]: video fullscreen background, PDF in a compact
///   draggable floating card in the lower corner.
enum ViewMode { fullPdf, splitScreen, floatingPdf }

/// Note composer type inside the notes bottom sheet.
enum NoteType { private, teacher }

/// Responsive, RTL lecture viewer with synchronized PDF + video layouts.
///
/// Production wiring notes (see §4 of the task spec):
/// - Video: replace the placeholder in [_buildVideoContainer] with a
///   `VideoPlayer(controller)` or `Chewie(controller)` tree created from
///   [videoUrl] (e.g. `VideoPlayerController.networkUrl(Uri.parse(videoUrl))`).
///   Keep `BoxFit.contain` / aspect-ratio handling in split + floating modes.
/// - PDF: replace the mock content in [_buildPdfContainer] with
///   `SfPdfViewer.network(pdfUrl)` / `SfPdfViewer.asset(...)` or
///   `PDF().cachedFromUrl(pdfUrl)` from `flutter_cached_pdfview`
///   (already in pubspec). Keep the watermark [Stack] layer above it inside
///   an [IgnorePointer] so scroll/zoom gestures pass through to the PDF
///   controller.
/// - Floating PDF is draggable via [_floatingOffset] + `onPanUpdate`
///   (clamped to the viewport), per the spec's floating-interaction note.
class LectureViewerScreen extends StatefulWidget {
  final String title;
  final int currentPage;
  final int totalPages;
  final String studentName;
  final String? videoUrl;
  final String? pdfUrl;

  const LectureViewerScreen({
    super.key,
    this.title = 'المحاسبة المالية - محاضرة 01',
    this.currentPage = 18,
    this.totalPages = 42,
    this.studentName = 'أحمد محمد',
    this.videoUrl,
    this.pdfUrl,
  });

  @override
  State<LectureViewerScreen> createState() => _LectureViewerScreenState();
}

class _LectureViewerScreenState extends State<LectureViewerScreen> {
  ViewMode _currentMode = ViewMode.fullPdf;
  bool _isOfflineEnabled = false;

  /// Free position of the floating PDF card. `null` means "docked at the
  /// default lower-corner anchor". Mutated by the drag gesture in
  /// floating mode and clamped to the viewport in [_buildFloatingPdfCard].
  final ValueNotifier<Offset?> _floatingOffset = ValueNotifier<Offset?>(null);

  // App Theme Palette
  static const Color brandPrimary = Color(0xFF2563EB);
  static const Color notePrivateColor = Color(0xFFF59E0B);
  static const Color notePrivateBg = Color(0xFFFFFBEB);
  static const Color noteTeacherColor = Color(0xFF8B5CF6);
  static const Color noteTeacherBg = Color(0xFFF5F3FF);

  /// Default anchor of the floating card (matches spec: left 16, bottom 90,
  /// size 175x250).
  static const double _floatingWidth = 175;
  static const double _floatingHeight = 250;
  static const double _floatingMargin = 16;
  static const double _floatingBottomMargin = 90;

  @override
  void dispose() {
    _floatingOffset.dispose();
    super.dispose();
  }

  void _switchViewMode() {
    setState(() {
      switch (_currentMode) {
        case ViewMode.fullPdf:
          _currentMode = ViewMode.splitScreen;
          _showSnackBar('وضع الشاشة المنقسمة');
          break;
        case ViewMode.splitScreen:
          _currentMode = ViewMode.floatingPdf;
          _showSnackBar('وضع الـ PDF العائم');
          break;
        case ViewMode.floatingPdf:
          _currentMode = ViewMode.fullPdf;
          _showSnackBar('وضع القراءة الكامل');
          break;
      }
    });
  }

  IconData get _fabIcon {
    switch (_currentMode) {
      case ViewMode.fullPdf:
        return Icons.splitscreen_rounded;
      case ViewMode.splitScreen:
        return Icons.picture_in_picture_alt_rounded;
      case ViewMode.floatingPdf:
        return Icons.fullscreen_rounded;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            _buildMainLayout(),
            _buildFloatingActionButton(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_forward_rounded, color: Colors.black87),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          Text(
            'صفحة ${widget.currentPage} من ${widget.totalPages}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.black87),
          onPressed: _openMainMenuSheet,
        ),
      ],
    );
  }

  Widget _buildMainLayout() {
    switch (_currentMode) {
      case ViewMode.fullPdf:
        return _buildPdfContainer(isFloating: false);

      case ViewMode.splitScreen:
        return Column(
          children: [
            Expanded(flex: 4, child: _buildVideoContainer()),
            Expanded(flex: 6, child: _buildPdfContainer(isFloating: false)),
          ],
        );

      case ViewMode.floatingPdf:
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(child: _buildVideoContainer()),
                _buildFloatingPdfCard(
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                ),
              ],
            );
          },
        );
    }
  }

  /// Draggable floating PDF card. The drag position is clamped so the card
  /// always stays fully inside the video viewport.
  Widget _buildFloatingPdfCard({
    required double maxWidth,
    required double maxHeight,
  }) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: _floatingOffset,
      builder: (context, offset, _) {
        // Default dock: lower corner. In RTL the spec anchors with
        // left: 16 / bottom: 90 — keep those exact numbers.
        double left = _floatingMargin;
        double top = maxHeight - _floatingBottomMargin - _floatingHeight;
        if (offset != null) {
          left = offset.dx.clamp(
              0.0, (maxWidth - _floatingWidth).clamp(0.0, double.infinity));
          top = offset.dy.clamp(
              0.0, (maxHeight - _floatingHeight).clamp(0.0, double.infinity));
        }
        return Positioned(
          left: left,
          top: top,
          width: _floatingWidth,
          height: _floatingHeight,
          child: GestureDetector(
            onPanUpdate: (details) {
              final current = offset ??
                  Offset(left, top);
              final next = current + details.delta;
              _floatingOffset.value = Offset(
                next.dx.clamp(
                    0.0,
                    (maxWidth - _floatingWidth)
                        .clamp(0.0, double.infinity)),
                next.dy.clamp(
                    0.0,
                    (maxHeight - _floatingHeight)
                        .clamp(0.0, double.infinity)),
              );
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildPdfContainer(isFloating: true),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoContainer() {
    // PRODUCTION: replace this placeholder with a real player, e.g.:
    //   final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!));
    //   ... await controller.initialize() ...
    //   AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))
    // or Chewie(controller: ChewieController(videoPlayerController: controller, autoPlay: true)).
    // Keep BoxFit.contain / aspect-ratio so split + floating layouts don't distort.
    return Container(
      color: Colors.black,
      width: double.infinity,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill_rounded,
                color: Colors.white, size: 54),
            SizedBox(height: 8),
            Text(
              'فيديو المحاضرة يعمل الآن',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfContainer({required bool isFloating}) {
    // PRODUCTION: replace the mock SingleChildScrollView content below with:
    //   SfPdfViewer.network(widget.pdfUrl!)  (syncfusion_flutter_pdfviewer)
    // or PDF().cachedFromUrl(widget.pdfUrl!) (flutter_cached_pdfview).
    // Keep it as the bottom layer of this Stack and keep the watermark
    // Positioned.fill layer wrapped in IgnorePointer above it so that
    // scroll & pinch-to-zoom gestures reach the PDF controller.
    return Container(
      color: const Color(0xFFE5E7EB),
      width: double.infinity,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isFloating ? 8.0 : 16.0),
        child: Center(
          child: Container(
            constraints: BoxConstraints(
                maxWidth: isFloating ? double.infinity : 800),
            padding: EdgeInsets.all(isFloating ? 12.0 : 28.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Stack(
              children: [
                // Watermark Layer (must stay above the PDF, below nothing
                // interactive; IgnorePointer lets gestures pass through).
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.rotate(
                        angle: -math.pi / 6,
                        child: Opacity(
                          opacity: 0.05,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Dr. Tarek Platform',
                                style: TextStyle(
                                  fontSize: isFloating ? 14 : 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.studentName,
                                style: TextStyle(
                                    fontSize: isFloating ? 10 : 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Page Content Sample (placeholder for the real PDF view).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مبدأ الاعتراف بالإيراد',
                      style: TextStyle(
                        fontSize: isFloating ? 12 : 20,
                        fontWeight: FontWeight.bold,
                        color: brandPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'يُعد مبدأ الاعتراف بالإيراد حجر الزاوية في أساس الاستحقاق المحاسبي. وينص على أنه يجب تسجيل الإيراد عندما يتحقق ويكون مكتسباً، بغض النظر عن وقت تحصيل النقدية.',
                      style: TextStyle(
                        fontSize: isFloating ? 10 : 14,
                        height: 1.7,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.justify,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          right: BorderSide(color: brandPrimary, width: 4),
                        ),
                      ),
                      child: Text(
                        'ملاحظة هامة: يمكن تقليب الصفحات بالسحب (Swipe) وتكبيرها باللمس المزدوج (Pinch to zoom).',
                        style: TextStyle(
                          fontSize: isFloating ? 9 : 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: FloatingActionButton(
        backgroundColor: brandPrimary,
        foregroundColor: Colors.white,
        onPressed: _switchViewMode,
        child: Icon(_fabIcon),
      ),
    );
  }

  void _openMainMenuSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading:
                        const Icon(Icons.search_rounded, color: Colors.grey),
                    title: const Text('البحث والفهرس',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showSnackBar('فتح الفهرس والبحث');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit_document,
                        color: Colors.grey),
                    title: const Text('الملاحظات والأسئلة',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openNotesSheet();
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.offline_pin_rounded,
                                color: Colors.grey),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Offline mode',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text('متاح داخل التطبيق فقط',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: _isOfflineEnabled,
                          activeThumbColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            setSheetState(() => _isOfflineEnabled = val);
                            setState(() => _isOfflineEnabled = val);
                            _showSnackBar(
                              val
                                  ? 'تم حفظ الملف داخل التطبيق للمذاكرة بدون إنترنت'
                                  : 'تم إزالة الملف من الذاكرة المحلية',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openNotesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _NotesBottomSheet(currentPage: widget.currentPage);
      },
    );
  }
}

class _NotesBottomSheet extends StatefulWidget {
  final int currentPage;
  const _NotesBottomSheet({required this.currentPage});

  @override
  State<_NotesBottomSheet> createState() => _NotesBottomSheetState();
}

class _NotesBottomSheetState extends State<_NotesBottomSheet> {
  NoteType _activeType = NoteType.private;
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPrivate = _activeType == NoteType.private;
    final primaryColor = isPrivate
        ? _LectureViewerScreenState.notePrivateColor
        : _LectureViewerScreenState.noteTeacherColor;
    final bgColor = isPrivate
        ? _LectureViewerScreenState.notePrivateBg
        : _LectureViewerScreenState.noteTeacherBg;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'إضافة ملاحظة (صفحة ${widget.currentPage})',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeType = NoteType.private),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isPrivate ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ملاحظة للمذاكرة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isPrivate
                              ? _LectureViewerScreenState.notePrivateColor
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeType = NoteType.teacher),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !isPrivate ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'اسأل د. طارق',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !isPrivate
                              ? _LectureViewerScreenState.noteTeacherColor
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: InputDecoration(
              filled: true,
              fillColor: bgColor,
              hintText: isPrivate
                  ? 'اكتب ملاحظتك الشخصية هنا...'
                  : 'اكتب سؤالك بخصوص هذا الجزء...',
              hintStyle:
                  const TextStyle(fontSize: 14, color: Colors.black38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              final content = _textController.text.trim();
              Navigator.pop(context);
              if (content.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('تم الحفظ بنجاح',
                          textAlign: TextAlign.center)),
                );
              }
            },
            child: Text(
              isPrivate ? 'حفظ الملاحظة' : 'إرسال السؤال للدكتور',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
