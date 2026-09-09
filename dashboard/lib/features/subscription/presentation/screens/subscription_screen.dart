import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Subscription Feature Matrix — Figma-faithful interactive UI.
//
// Shell contract (must NOT break):
// • DashboardShell already renders exactly ONE TheMenuButton at
//   Positioned(left:80, top:24, 80x80). This screen must NOT render its own
//   menu button (would duplicate → dashboard_shell_test fails).
// • This screen lives inside the shell's 1280x800 Stack, so it returns
//   Material + SizedBox.expand (not a nested Scaffold).
// • Top header keeps a 370px placeholder so the logo stays at X:370.
// Interactivity (from spec paste, adapted to shell):
// • Local _values map drives all switches + numeric badges.
// • Pixel-perfect switch: green 0xFF10B981 / gray 0xFFE5E7EB, white thumb.
// • Numeric badges are editable TextFormFields (digits only).
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionFeatureMatrixScreen extends ConsumerStatefulWidget {
  const SubscriptionFeatureMatrixScreen({super.key});

  @override
  ConsumerState<SubscriptionFeatureMatrixScreen> createState() =>
      _SubscriptionFeatureMatrixScreenState();
}

class _SubscriptionFeatureMatrixScreenState
    extends ConsumerState<SubscriptionFeatureMatrixScreen> {
  final ScrollController _scrollController = ScrollController();

  final Map<String, GlobalKey> _sectionKeys = {
    'video_media': GlobalKey(),
    'pdf_docs': GlobalKey(),
    'learning_assessment': GlobalKey(),
    'productivity': GlobalKey(),
    'device_security': GlobalKey(),
    'profile_account': GlobalKey(),
  };

  String _activeCategory = 'video_media';
  String _activePlan = 'free';
  bool _isAutoScrolling = false;

  // خريطة الحالة التفاعلية لكافة السويتشات والقيم الرقمية
  final Map<String, dynamic> _values = {
    // Video & Media
    'video.access': true,
    'video.rolling_enabled': false,
    'video.rolling_hours': '24',
    'video.limited_enabled': true,
    'video.limited_days': '7',
    'video.quality.144p': true,
    'video.quality.240p': true,
    'video.quality.360p': true,
    'video.quality.480p': true,
    'video.quality.720p': true,
    'video.quality.1080p': false,
    'video.quality.2kp': false,
    'video.quality.4kp': false,
    'video.speed.0_50': true,
    'video.speed.1_00': true,
    'video.speed.2_00': false,
    'video.speed.3_00': false,
    'video.speed.4_00': false,
    'video.pip': true,
    'video.cast': true,
    'video.resume': true,
    'video.seek': true,
    'video.heatmap': true,
    'video.offline_mode': true,
    'video.offline_quality_select': true,
    'video.offline_limit': '24',
    'video.watermark': true,
    'video.screen_record': true,
    'video.screenshot': true,

    // PDF
    'pdf.access': true,
    'pdf.offline': true,
    'pdf.offline_limit': '24',
    'pdf.watermark': true,
    'pdf.screen_record': true,
    'pdf.screenshot': true,
    'pdf.search': true,
    'pdf.toc': true,
    'pdf.zoom': true,
    'pdf.bookmarks': true,

    // Assessment
    'exam.access': true,
    'exam.timeline_quiz': true,
    'exam.review_solution': true,
    'exam.retake_limit': '2',
    'exam.anti_cheat': true,
    'exam.timer': true,
    'exam.shuffle': true,
    'exam.practice_bank': true,
    'exam.analytics': true,
    'exam.prerequisite_gate': true,

    // Productivity
    'prod.notes': true,
    'prod.bookmarks': true,
    'prod.progress': true,
    'prod.search_notes': true,
    'prod.export_notes': true,
    'prod.study_reminders': true,
    'prod.lecture_tags': true,

    // Device
    'device.max_count': '1',
    'device.security_score': true,
    'device.block_root': true,

    // Profile
    'profile.edit_name': true,
    'profile.edit_photo': true,
    'profile.view_membership': true,
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isAutoScrolling) return;

    for (final entry in _sectionKeys.entries) {
      final key = entry.value;
      final context = key.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          final position = box.localToGlobal(Offset.zero);
          if (position.dy >= 100 && position.dy <= 350) {
            if (_activeCategory != entry.key) {
              setState(() {
                _activeCategory = entry.key;
              });
            }
            break;
          }
        }
      }
    }
  }

  void _scrollToSection(String categoryKey) async {
    final key = _sectionKeys[categoryKey];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      setState(() {
        _isAutoScrolling = true;
        _activeCategory = categoryKey;
      });

      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
      );

      if (mounted) {
        setState(() {
          _isAutoScrolling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SizedBox.expand(
        child: Column(
          children: [
            // 1. FIXED STICKY HEADER
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 12),
                  _buildPlanSelectorTabs(),
                  const SizedBox(height: 16),
                  _buildCategoryAnchorTabs(),
                ],
              ),
            ),

            // 2. SCROLLABLE BODY
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 80, vertical: 32),
                child: Column(
                  children: [
                    // 1. Video & Media
                    _buildCategoryContainer(
                      key: _sectionKeys['video_media']!,
                      children: [
                        _buildFeatureRowItem('video.access', 'Video access'),
                        _buildRollingWindowCard(),
                        _buildLimitedDurationCard(),
                        _buildResolutionNestedCard(),
                        _buildPlaybackSpeedNestedCard(),
                        _buildFeatureRowItem(
                            'video.pip', 'Video Picture-in-Picture'),
                        _buildFeatureRowItem(
                            'video.cast', 'Video Cast on tv'),
                        _buildFeatureRowItem(
                            'video.resume', 'Video Resume Position'),
                        _buildFeatureRowItem(
                            'video.seek', 'Video Forward / Backward'),
                        _buildFeatureRowItem(
                            'video.heatmap', 'Video watch time heatmap'),
                        _buildOfflineModeNestedCard(),
                        _buildFeatureRowItem(
                            'video.watermark', 'Video Watermark'),
                        _buildFeatureRowItem('video.screen_record',
                            'Video security screen record detect'),
                        _buildFeatureRowItem('video.screenshot',
                            'Video security screenshot prevent'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 2. PDF & Documents
                    _buildCategoryContainer(
                      key: _sectionKeys['pdf_docs']!,
                      children: [
                        _buildFeatureRowItem('pdf.access', 'PDF access'),
                        _buildPdfOfflineGroupCard(),
                        _buildFeatureRowItem('pdf.watermark', 'PDF Watermark'),
                        _buildFeatureRowItem('pdf.screen_record',
                            'PDF security screen record detect'),
                        _buildFeatureRowItem('pdf.screenshot',
                            'PDF security screenshot prevent'),
                        _buildFeatureRowItem('pdf.search', 'PDF Search within'),
                        _buildFeatureRowItem(
                            'pdf.toc', 'PDF Table of contents'),
                        _buildFeatureRowItem('pdf.zoom', 'PDF Zoom control'),
                        _buildFeatureRowItem('pdf.bookmarks', 'PDF Bookmarks'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 3. Learning & Assessment
                    _buildCategoryContainer(
                      key: _sectionKeys['learning_assessment']!,
                      children: [
                        _buildFeatureRowItem('exam.access', 'Exams access'),
                        _buildFeatureRowItem(
                            'exam.timeline_quiz', 'Timeline Video Quizzes'),
                        _buildFeatureRowItem('exam.review_solution',
                            'Review Exam Solutions'),
                        _buildFeatureRowWithEditableBadge('exam.retake_limit',
                            'Exam Retake Attempts Limit'),
                        _buildFeatureRowItem(
                            'exam.anti_cheat', 'Anti-Cheat Exam Protection'),
                        _buildFeatureRowItem(
                            'exam.timer', 'Enforced Exam Countdown Timer'),
                        _buildFeatureRowItem(
                            'exam.shuffle', 'Shuffle Questions & Options'),
                        _buildFeatureRowItem('exam.practice_bank',
                            'Self-Practice Question Bank'),
                        _buildFeatureRowItem('exam.analytics',
                            'Performance & Weakness Analytics'),
                        _buildFeatureRowItem('exam.prerequisite_gate',
                            'Exam Prerequisite Gate'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 4. Productivity
                    _buildCategoryContainer(
                      key: _sectionKeys['productivity']!,
                      children: [
                        _buildFeatureRowItem(
                            'prod.notes', 'Create Personal Note'),
                        _buildFeatureRowItem(
                            'prod.bookmarks', 'Create Bookmarks'),
                        _buildFeatureRowItem(
                            'prod.progress', 'Course Progress Tracking'),
                        _buildFeatureRowItem(
                            'prod.search_notes', 'Search in Personal Notes'),
                        _buildFeatureRowItem(
                            'prod.export_notes', 'Export Personal Notes'),
                        _buildFeatureRowItem('prod.study_reminders',
                            'Study Reminders & Schedule'),
                        _buildFeatureRowItem(
                            'prod.lecture_tags', 'Lecture Revision Tagging'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 5. Device & Security
                    _buildCategoryContainer(
                      key: _sectionKeys['device_security']!,
                      children: [
                        _buildFeatureRowWithEditableBadge(
                            'device.max_count', 'Max active devices'),
                        _buildFeatureRowItem(
                            'device.security_score', 'View security score'),
                        _buildFeatureRowItem(
                            'device.block_root', 'Block Root & Emulators'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 6. Profile & Account
                    _buildCategoryContainer(
                      key: _sectionKeys['profile_account']!,
                      children: [
                        _buildFeatureRowItem(
                            'profile.edit_name', 'Edit full name'),
                        _buildFeatureRowItem(
                            'profile.edit_photo', 'Edit profile photo'),
                        _buildFeatureRowItem('profile.view_membership',
                            'View membership details'),
                      ],
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shell owns the single TheMenuButton at (80, 24, 80x80).
  // Brand box stays at X:370 w:540 (center 640 = dead center of 1280),
  // text itself is centered inside the box so the logo is visually centered.
  Widget _buildTopHeader() {
    return const SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 370),
          SizedBox(
            width: 540,
            height: 80,
            child: Align(
              alignment: Alignment.center,
              child: Text.rich(
                textAlign: TextAlign.center,
                TextSpan(
                  style: TextStyle(
                    fontFamily: 'Google Sans Flex',
                    fontSize: 48,
                    color: Color(0xFF000000),
                    letterSpacing: 0,
                    height: 1.0,
                  ),
                  children: [
                    TextSpan(
                      text: 'Tarek el araby ',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    TextSpan(
                      text: 'Platform',
                      style: TextStyle(fontWeight: FontWeight.w100),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================
  // PIXEL-PERFECT TOGGLE SWITCH (FIGMA GREEN & CLEAN GRAY)
  // ========================================================
  Widget _buildCustomSwitch(
      {required bool value, required ValueChanged<bool> onChanged}) {
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF10B981);
        }
        return const Color(0xFFE5E7EB);
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    );
  }

  // ========================================================
  // EDITABLE PILL BADGE (numeric input)
  // ========================================================
  Widget _buildEditableBadge(
      {required String initialValue,
      required ValueChanged<String> onChanged}) {
    return Container(
      width: 60,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        onChanged: onChanged,
        style: const TextStyle(
          fontFamily: 'Google Sans Flex',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
      ),
    );
  }

  // ========================================================
  // ROW ITEMS & NESTED CARDS
  // ========================================================
  Widget _buildFeatureRowItem(String key, String title) {
    final bool currentVal = _values[key] ?? false;
    return Container(
      width: 1118,
      height: 56,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF111827),
            ),
          ),
          _buildCustomSwitch(
            value: currentVal,
            onChanged: (val) => setState(() => _values[key] = val),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRowWithEditableBadge(String key, String title) {
    return Container(
      width: 1118,
      height: 56,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF111827),
            ),
          ),
          _buildEditableBadge(
            initialValue: (_values[key] ?? '1').toString(),
            onChanged: (val) => _values[key] = val,
          ),
        ],
      ),
    );
  }

  Widget _buildRollingWindowCard() {
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video Rolling Window',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildCustomSwitch(
                value: _values['video.rolling_enabled'] ?? false,
                onChanged: (val) =>
                    setState(() => _values['video.rolling_enabled'] = val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video Rolling hours',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildEditableBadge(
                initialValue:
                    (_values['video.rolling_hours'] ?? '24').toString(),
                onChanged: (val) => _values['video.rolling_hours'] = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLimitedDurationCard() {
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video Limited Duration',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildCustomSwitch(
                value: _values['video.limited_enabled'] ?? true,
                onChanged: (val) =>
                    setState(() => _values['video.limited_enabled'] = val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video Available Minutes',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildEditableBadge(
                initialValue:
                    (_values['video.limited_days'] ?? '7').toString(),
                onChanged: (val) => _values['video.limited_days'] = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionNestedCard() {
    final resolutions = [
      {'key': 'video.quality.144p', 'label': '144 p'},
      {'key': 'video.quality.240p', 'label': '240 p'},
      {'key': 'video.quality.360p', 'label': '360 p'},
      {'key': 'video.quality.480p', 'label': '480 p'},
      {'key': 'video.quality.720p', 'label': '720 p'},
      {'key': 'video.quality.1080p', 'label': '1080 p'},
      {'key': 'video.quality.2kp', 'label': '2K p'},
      {'key': 'video.quality.4kp', 'label': '4K p'},
    ];
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Video Resolution',
              style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 16,
                  color: Color(0xFF111827))),
          const SizedBox(height: 12),
          ...resolutions.map((res) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(res['label']!,
                          style: const TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 15,
                              color: Color(0xFF111827))),
                    ),
                    _buildCustomSwitch(
                      value: _values[res['key']] ?? false,
                      onChanged: (val) =>
                          setState(() => _values[res['key']!] = val),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPlaybackSpeedNestedCard() {
    final speeds = [
      {'key': 'video.speed.0_50', 'label': 'X0.50'},
      {'key': 'video.speed.1_00', 'label': 'X1.00'},
      {'key': 'video.speed.2_00', 'label': 'X2.00'},
      {'key': 'video.speed.3_00', 'label': 'X3.00'},
      {'key': 'video.speed.4_00', 'label': 'X4.00'},
    ];
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Video Playback Speed',
              style: TextStyle(
                  fontFamily: 'Google Sans Flex',
                  fontSize: 16,
                  color: Color(0xFF111827))),
          const SizedBox(height: 12),
          ...speeds.map((spd) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(spd['label']!,
                          style: const TextStyle(
                              fontFamily: 'Google Sans Flex',
                              fontSize: 15,
                              color: Color(0xFF111827))),
                    ),
                    _buildCustomSwitch(
                      value: _values[spd['key']] ?? false,
                      onChanged: (val) =>
                          setState(() => _values[spd['key']!] = val),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildOfflineModeNestedCard() {
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video Offline Mode',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildCustomSwitch(
                value: _values['video.offline_mode'] ?? false,
                onChanged: (val) =>
                    setState(() => _values['video.offline_mode'] = val),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allow student to choose download quality',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildCustomSwitch(
                value: _values['video.offline_quality_select'] ?? false,
                onChanged: (val) => setState(
                    () => _values['video.offline_quality_select'] = val),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Video offline limit per subject',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildEditableBadge(
                initialValue:
                    (_values['video.offline_limit'] ?? '24').toString(),
                onChanged: (val) => _values['video.offline_limit'] = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPdfOfflineGroupCard() {
    return Container(
      width: 1118,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PDF Offline Mode',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildCustomSwitch(
                value: _values['pdf.offline'] ?? false,
                onChanged: (val) =>
                    setState(() => _values['pdf.offline'] = val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PDF offline limit per subject',
                  style: TextStyle(
                      fontFamily: 'Google Sans Flex',
                      fontSize: 16,
                      color: Color(0xFF111827))),
              _buildEditableBadge(
                initialValue:
                    (_values['pdf.offline_limit'] ?? '24').toString(),
                onChanged: (val) => _values['pdf.offline_limit'] = val,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryContainer(
      {required List<Widget> children, required GlobalKey key}) {
    return Container(
      key: key,
      width: 1120,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildPlanSelectorTabs() {
    final plans = [
      {'key': 'guest', 'label': 'Guest'},
      {'key': 'free', 'label': 'Center FREE'},
      {'key': 'pro', 'label': 'Center PRO'},
      {'key': 'max', 'label': 'Center MAX'},
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: plans.map((p) {
        final isSelected = _activePlan == p['key'];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ChoiceChip(
            label: Text(p['label']!),
            selected: isSelected,
            selectedColor: const Color(0xFF111827),
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF111827),
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999)),
            onSelected: (val) {
              if (val) setState(() => _activePlan = p['key']!);
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryAnchorTabs() {
    final categories = [
      {'key': 'video_media', 'label': 'Video & Media'},
      {'key': 'pdf_docs', 'label': 'Pdf & documents'},
      {'key': 'learning_assessment', 'label': 'Learning & Assessment'},
      {'key': 'productivity', 'label': 'Productivity'},
      {'key': 'device_security', 'label': 'Device & Security'},
      {'key': 'profile_account', 'label': 'Profile & Account'},
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: categories.map((cat) {
          final isSelected = _activeCategory == cat['key'];
          return GestureDetector(
            onTap: () => _scrollToSection(cat['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF111827)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                cat['label']!,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF4B5563),
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compat wrapper: DashboardShell routes to
// SubscriptionScreen(isTeacher: …). It now forwards to the Figma matrix.
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionScreen extends StatelessWidget {
  final bool isTeacher;

  const SubscriptionScreen({super.key, this.isTeacher = true});

  @override
  Widget build(BuildContext context) {
    return const SubscriptionFeatureMatrixScreen();
  }
}
