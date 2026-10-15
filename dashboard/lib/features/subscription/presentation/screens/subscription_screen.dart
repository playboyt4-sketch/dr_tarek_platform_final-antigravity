import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/subscription_matrix_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Subscription — Figma `Subscription` frame (node 821-1465), interactive.
//
// • Header: brand at X:370. Plans nav: Guest / FREE / PRO / MAX only —
//   extra `plans` documents are never shown.
// • Category nav: Video & Media / Pdf & documents / Learning & Assessment /
//   Productivity / Devices & Security / Profile & Account (scroll anchors).
// • Rows, titles, grouping and badges match the Figma frame exactly:
//   no key subtitles, no extra labels.
// • Each plan keeps its own matrix (`plan_features` where
//   plan_id == selected plan); every edit goes through `setPlanFeature`
//   with that planId. Switching plans never leaks values across plans.
// • Shell contract: no menu button here (the shell owns it), returns
//   Material + SizedBox.expand (not a nested Scaffold).
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureDef {
  final String key;
  final String title;
  final bool isNumber;
  final bool isSensitive;

  const _FeatureDef(
    this.key,
    this.title, {
    this.isNumber = false,
    this.isSensitive = false,
  });
}

// ── Feature keys (one row = one plan_features document) ─────────────────────
const _dVideoAccess =
    _FeatureDef('video.access', 'Video access');
const _dRollingEnabled = _FeatureDef(
    'video.rolling_window.enabled', 'Video Rolling Window',
    isSensitive: true);
const _dRollingHours = _FeatureDef(
    'video.rolling_window.hours', 'Video Rolling hours',
    isNumber: true, isSensitive: true);
const _dPreview = _FeatureDef(
    'video.preview_duration', 'Video Preview Duration',
    isNumber: true);
const _dQuality144 =
    _FeatureDef('video.quality.144p', '144 p');
const _dQuality240 =
    _FeatureDef('video.quality.240p', '240 p');
const _dQuality360 =
    _FeatureDef('video.quality.360p', '360 p');
const _dQuality480 =
    _FeatureDef('video.quality.480p', '480 p');
const _dQuality720 =
    _FeatureDef('video.quality.720p', '720 p');
const _dQuality1080 =
    _FeatureDef('video.quality.1080p', '1080 p');
const _dQuality2k = _FeatureDef('video.quality.2k', '2K p');
const _dQuality4k = _FeatureDef('video.quality.4k', '4K p');
const _dSpeed05 =
    _FeatureDef('video.playback_speed.x0_5', 'X0.50');
const _dSpeed10 =
    _FeatureDef('video.playback_speed.x1_0', 'X1.00');
const _dSpeed20 =
    _FeatureDef('video.playback_speed.x2_0', 'X2.00');
const _dSpeed30 =
    _FeatureDef('video.playback_speed.x3_0', 'X3.00');
const _dSpeed40 =
    _FeatureDef('video.playback_speed.x4_0', 'X4.00');
const _dPip =
    _FeatureDef('video.pip', 'Video Picture-in-Picture');
const _dCast = _FeatureDef('video.cast', 'Video Cast on tv');
const _dResume =
    _FeatureDef('video.resume', 'Video Resume Position');
const _dSeek =
    _FeatureDef('video.skip_forward_backward', 'Video Forward / Backward');
const _dHeatmap =
    _FeatureDef('video.heatmap', 'Video watch time heatmap');
const _dOfflineMode =
    _FeatureDef('video.download', 'Video Offline Mode');
const _dOfflineQuality = _FeatureDef(
    'video.download.choose_quality',
    'Allow student to choose download quality');
const _dOfflineLimit = _FeatureDef(
    'video.download.max_count', 'Video offline limit per subject',
    isNumber: true);
const _dVideoWatermark =
    _FeatureDef('video.watermark', 'Video Watermark');
const _dVideoRecord = _FeatureDef(
    'video.security.screen_record_detect',
    'Video security screen record detect');
const _dVideoShot = _FeatureDef(
    'video.security.screenshot_prevent',
    'Video security screenshot prevent');

const _dPdfAccess = _FeatureDef('pdf.access', 'PDF access');
const _dPdfOffline =
    _FeatureDef('pdf.offline', 'PDF Offline Mode');
const _dPdfOfflineLimit = _FeatureDef(
    'pdf.offline_max_files', 'PDF offline limit per subject',
    isNumber: true);
const _dPdfWatermark =
    _FeatureDef('pdf.watermark', 'PDF Watermark');
const _dPdfRecord = _FeatureDef(
    'pdf.security.screen_record_detect',
    'PDF security screen record detect');
const _dPdfShot = _FeatureDef(
    'pdf.security.screenshot_prevent',
    'PDF security screenshot prevent');
const _dPdfSearch =
    _FeatureDef('pdf.search', 'PDF Search within');
const _dPdfToc =
    _FeatureDef('pdf.toc', 'PDF Table of contents');
const _dPdfZoom = _FeatureDef('pdf.zoom', 'PDF Zoom control');
const _dPdfBookmarks =
    _FeatureDef('pdf.bookmarks', 'PDF Bookmarks');

const _dExamAccess =
    _FeatureDef('exam.access', 'Exams access');
const _dQuizAccess =
    _FeatureDef('quiz.access', 'Timeline Video Quizzes');
const _dExamReview = _FeatureDef(
    'exam.review_solutions', 'Review Exam Solutions');
const _dExamAttempts = _FeatureDef(
    'exam.attempts', 'Exam Retake Attempts Limit',
    isNumber: true);
const _dExamAntiCheat = _FeatureDef(
    'exam.anti_cheat', 'Anti-Cheat Exam Protection');
const _dExamCountdown = _FeatureDef(
    'exam.countdown', 'Enforced Exam Countdown Timer');
const _dExamShuffle = _FeatureDef(
    'exam.shuffle', 'Shuffle Questions & Options');
const _dExamBank = _FeatureDef(
    'exam.question_bank', 'Self-Practice Question Bank');
const _dExamAnalytics = _FeatureDef(
    'progress.analytics', 'Performance & Weakness Analytics');
const _dExamGate = _FeatureDef(
    'exam.prerequisite', 'Exam Prerequisite Gate');

const _dNotesCreate =
    _FeatureDef('notes.create', 'Create Personal Note');
const _dBookmarkCreate =
    _FeatureDef('bookmarks.create', 'Create Bookmarks');
const _dProgressTracking = _FeatureDef(
    'progress.tracking', 'Course Progress Tracking');
const _dNotesSearch =
    _FeatureDef('notes.search', 'Search in Personal Notes');
const _dNotesExport =
    _FeatureDef('notes.export', 'Export Personal Notes');
const _dNotesReminders = _FeatureDef(
    'notes.reminders', 'Study Reminders & Schedule');
const _dNotesRevision = _FeatureDef(
    'notes.revision_tag', 'Lecture Revision Tagging');

const _dDeviceMax = _FeatureDef(
    'device.max_count', 'Max active devices',
    isNumber: true);
const _dGeneralOfflineMode =
    _FeatureDef('offline.mode', 'General Offline Mode');
const _dSecurityScore =
    _FeatureDef('security.score', 'View security score');
const _dBlockRoot =
    _FeatureDef('security.block_root', 'Block Root & Emulators');

const _dEditName =
    _FeatureDef('profile.edit_name', 'Edit full name');
const _dEditPhoto =
    _FeatureDef('profile.edit_photo', 'Edit profile photo');
const _dViewMembership = _FeatureDef(
    'profile.view_membership', 'View membership details');

/// Static fallback matrix for contexts without a ProviderScope
/// (plain widget tests): Doctor-only rows stay verifiable offline.
Map<String, PlanFeatureState> _fallbackMatrix() =>
    const <String, PlanFeatureState>{
      'video.access':
          PlanFeatureState(key: 'video.access', enabled: true),
      'video.rolling_window.enabled': PlanFeatureState(
          key: 'video.rolling_window.enabled', enabled: false),
      'video.rolling_window.hours': PlanFeatureState(
          key: 'video.rolling_window.hours',
          enabled: false,
          value: 24),
    };

class SubscriptionFeatureMatrixScreen extends StatefulWidget {
  /// Doctor (Platform Owner) sessions may edit every row. Non-doctor
  /// sessions (delegated Admins) see the Doctor-only monetization rows
  /// (video rolling window, mirroring backend `SENSITIVE_PLAN_FEATURES`)
  /// disabled; all other rows stay editable. The backend `setPlanFeature`
  /// gate remains the true enforcement boundary.
  final bool isDoctor;

  const SubscriptionFeatureMatrixScreen({super.key, this.isDoctor = false});

  @override
  State<SubscriptionFeatureMatrixScreen> createState() =>
      _SubscriptionFeatureMatrixScreenState();
}

class _SubscriptionFeatureMatrixScreenState
    extends State<SubscriptionFeatureMatrixScreen> {
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
  String _activePlan = 'guest';
  bool _isAutoScrolling = false;
  final Set<String> _pending = <String>{};
  // Plan awaiting a scroll restore: after switching plans the content
  // reloads (offset resets), so we jump back to the active category
  // section to keep comparing plans section-by-section.
  String? _restorePlanId;

  /// Badge field state, keyed by plan + feature so a value can never leak
  /// across plans and always mirrors the current plan's stream data.
  final Map<String, TextEditingController> _badgeControllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _badgeFocusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final TextEditingController c in _badgeControllers.values) {
      c.dispose();
    }
    for (final FocusNode f in _badgeFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  bool _hasProviderScope() {
    try {
      ProviderScope.containerOf(context);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onScroll() {
    if (_isAutoScrolling) return;
    // Scroll-spy: the active tab is the last section whose top reached
    // the header band (dy <= 350). Section tops are far apart, so a
    // narrow "top inside band" match would freeze the tab at most resting
    // positions. At max scroll the last section wins explicitly.
    String current = _sectionKeys.keys.first;
    for (final entry in _sectionKeys.entries) {
      final sectionContext = entry.value.currentContext;
      if (sectionContext == null) continue;
      final box = sectionContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final double dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= 350) {
        current = entry.key;
      } else {
        break; // sections are ordered top-to-bottom
      }
    }
    if (_atMaxScroll()) current = _sectionKeys.keys.last;
    if (_activeCategory != current) {
      setState(() => _activeCategory = current);
    }
  }

  bool _atMaxScroll() {
    try {
      final position = _scrollController.position;
      return position.hasPixels &&
          position.hasContentDimensions &&
          position.pixels >= position.maxScrollExtent - 8;
    } catch (_) {
      return false;
    }
  }

  void _scrollToSection(String categoryKey) async {
    final key = _sectionKeys[categoryKey];
    final targetContext = key?.currentContext;
    if (targetContext == null) return;
    setState(() {
      _isAutoScrolling = true;
      _activeCategory = categoryKey;
    });
    // Never leave _isAutoScrolling stuck: if the target detaches
    // mid-animation (matrix reload / plan switch), ensureVisible throws
    // and a stuck flag would freeze the tabs on manual scroll forever.
    try {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
      );
    } catch (_) {
      // Tab selection above already applied; nothing else to do.
    } finally {
      if (mounted) {
        setState(() {
          _isAutoScrolling = false;
        });
      }
    }
  }

  String _valueTypeFor(Object? value, bool isNumber) {
    if (isNumber || value is num) return 'number';
    if (value is String) return 'string';
    return 'boolean';
  }

  Future<void> _toggleFeature(
    WidgetRef? ref,
    _FeatureDef def,
    PlanFeatureState? current,
    bool enabled,
  ) async {
    final String featureKey = def.key;
    if (_pending.contains(featureKey)) return;
    if (ref == null) return;
    setState(() => _pending.add(featureKey));
    try {
      await ref.read(subscriptionActionsProvider).setFeature(
            planId: _activePlan,
            featureKey: featureKey,
            enabled: enabled,
            value: current?.value,
            valueType: _valueTypeFor(current?.value, def.isNumber),
          );
    } finally {
      if (mounted) setState(() => _pending.remove(featureKey));
    }
  }

  Future<void> _saveNumericValue(
    WidgetRef? ref,
    _FeatureDef def,
    PlanFeatureState? current,
    String raw, {
    bool? parentEnabled,
  }) async {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null || ref == null) return;
    if (_pending.contains(def.key)) return;
    setState(() => _pending.add(def.key));
    try {
      await ref.read(subscriptionActionsProvider).setFeature(
            planId: _activePlan,
            featureKey: def.key,
            enabled: parentEnabled ?? current?.enabled ?? true,
            value: parsed,
            valueType: 'number',
          );
    } finally {
      if (mounted) setState(() => _pending.remove(def.key));
    }
  }

  static String _shownValue(PlanFeatureState? state) {
    final Object? value = state?.value;
    if (value == null) return '';
    final String text = value.toString();
    return text == 'null' ? '' : text;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasProviderScope()) return _buildStaticFallback();
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AsyncValue<List<SubscriptionPlan>> plansAsync =
            ref.watch(subscriptionPlansProvider);
        final AsyncValue<Map<String, PlanFeatureState>> matrixAsync =
            ref.watch(subscriptionMatrixProvider(_activePlan));

        return Material(
          color: Colors.white,
          child: SizedBox.expand(
            child: Column(
              children: [
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
                      _buildPlanSelectorTabs(_planList(plansAsync)),
                      const SizedBox(height: 16),
                      _buildCategoryAnchorTabs(),
                    ],
                  ),
                ),
                Expanded(
                  // Remount the whole matrix whenever the selected plan
                  // changes: stateful fields (value badges) must never
                  // carry over text from another plan. No visual change.
                  child: KeyedSubtree(
                    key: ValueKey<String>('matrix-$_activePlan'),
                    child: matrixAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (Object e, _) => Center(
                          child: Text('Failed to load $_activePlan: $e')),
                      data: (Map<String, PlanFeatureState> matrix) {
                        _restoreScrollIfNeeded();
                        return _buildBody(ref, matrix);
                      },
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

  /// After a plan switch, jump back to the active category section so
  /// comparing plans keeps the user on the same section (no animation,
  /// no tab change — purely positional).
  void _restoreScrollIfNeeded() {
    if (_restorePlanId != _activePlan) return;
    _restorePlanId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _sectionKeys[_activeCategory]?.currentContext;
      if (targetContext == null) return;
      try {
        Scrollable.ensureVisible(
          targetContext,
          duration: Duration.zero,
          alignment: 0.05,
        );
      } catch (_) {
        // Section detached (reload race); next frames settle it.
      }
    });
  }

  /// Only the four canonical plans are ever shown. Extra `plans`
  /// documents (e.g. legacy bundle docs) are ignored here on purpose.
  List<SubscriptionPlan> _planList(
      AsyncValue<List<SubscriptionPlan>> plansAsync) {
    final List<SubscriptionPlan> all = plansAsync.maybeWhen(
      data: (List<SubscriptionPlan> d) =>
          d.isEmpty ? SubscriptionPlan.fallback() : d,
      orElse: () => SubscriptionPlan.fallback(),
    );
    return _canonicalPlans(all);
  }

  /// Canonical-only filter for plain plan lists (scope-less fallback).
  List<SubscriptionPlan> _canonicalPlans(List<SubscriptionPlan> all) {
    final List<SubscriptionPlan> canonical = <SubscriptionPlan>[
      for (final String id in subscriptionPlanOrder)
        for (final SubscriptionPlan p in all)
          if (p.id == id) p,
    ];
    return canonical.isEmpty ? SubscriptionPlan.fallback() : canonical;
  }

  /// Scope-less fallback: same header/tabs/rows, static matrix values.
  Widget _buildStaticFallback() {
    final List<SubscriptionPlan> plans =
        _canonicalPlans(SubscriptionPlan.fallback());
    final Map<String, PlanFeatureState> matrix = _fallbackMatrix();
    return Material(
      color: Colors.white,
      child: SizedBox.expand(
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(color: Colors.white),
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 12),
                  _buildPlanSelectorTabs(plans),
                  const SizedBox(height: 16),
                  _buildCategoryAnchorTabs(),
                ],
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey<String>('matrix-$_activePlan'),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 80, vertical: 32),
                  child: _buildSections(null, matrix),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(WidgetRef ref, Map<String, PlanFeatureState> matrix) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 32),
      child: _buildSections(ref, matrix),
    );
  }

  Widget _buildSections(
      WidgetRef? ref, Map<String, PlanFeatureState> matrix) {
    return Column(
      children: [
        _buildSectionCard(
          key: _sectionKeys['video_media']!,
          children: [
            _singleRow(ref, matrix, _dVideoAccess),
            _pairCard(ref, matrix,
                toggleDef: _dRollingEnabled,
                valueDef: _dRollingHours,
                badgeKey: const Key('rolling-hours-badge')),
            _pairCard(ref, matrix,
                toggleDef: const _FeatureDef(
                    'video.preview_duration', 'Video Limited Duration'),
                valueDef: _dPreview),
            _nestedCard(ref, matrix,
                title: 'Video Resolution',
                defs: const [
                  _dQuality144,
                  _dQuality240,
                  _dQuality360,
                  _dQuality480,
                  _dQuality720,
                  _dQuality1080,
                  _dQuality2k,
                  _dQuality4k,
                ]),
            _nestedCard(ref, matrix,
                title: 'Video Playback Speed',
                defs: const [
                  _dSpeed05,
                  _dSpeed10,
                  _dSpeed20,
                  _dSpeed30,
                  _dSpeed40,
                ]),
            _singleRow(ref, matrix, _dPip),
            _singleRow(ref, matrix, _dCast),
            _singleRow(ref, matrix, _dResume),
            _singleRow(ref, matrix, _dSeek),
            _singleRow(ref, matrix, _dHeatmap),
            _tripleCard(ref, matrix,
                first: _dOfflineMode,
                second: _dOfflineQuality,
                valueDef: _dOfflineLimit),
            _singleRow(ref, matrix, _dVideoWatermark),
            _singleRow(ref, matrix, _dVideoRecord),
            _singleRow(ref, matrix, _dVideoShot),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          key: _sectionKeys['pdf_docs']!,
          children: [
            _singleRow(ref, matrix, _dPdfAccess),
            _pairCard(ref, matrix,
                toggleDef: _dPdfOffline, valueDef: _dPdfOfflineLimit),
            _singleRow(ref, matrix, _dPdfWatermark),
            _singleRow(ref, matrix, _dPdfRecord),
            _singleRow(ref, matrix, _dPdfShot),
            _singleRow(ref, matrix, _dPdfSearch),
            _singleRow(ref, matrix, _dPdfToc),
            _singleRow(ref, matrix, _dPdfZoom),
            _singleRow(ref, matrix, _dPdfBookmarks),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          key: _sectionKeys['learning_assessment']!,
          children: [
            _singleRow(ref, matrix, _dExamAccess),
            _singleRow(ref, matrix, _dQuizAccess),
            _singleRow(ref, matrix, _dExamReview),
            _singleBadgeRow(ref, matrix, _dExamAttempts),
            _singleRow(ref, matrix, _dExamAntiCheat),
            _singleRow(ref, matrix, _dExamCountdown),
            _singleRow(ref, matrix, _dExamShuffle),
            _singleRow(ref, matrix, _dExamBank),
            _singleRow(ref, matrix, _dExamAnalytics),
            _singleRow(ref, matrix, _dExamGate),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          key: _sectionKeys['productivity']!,
          children: [
            _singleRow(ref, matrix, _dNotesCreate),
            _singleRow(ref, matrix, _dBookmarkCreate),
            _singleRow(ref, matrix, _dProgressTracking),
            _singleRow(ref, matrix, _dNotesSearch),
            _singleRow(ref, matrix, _dNotesExport),
            _singleRow(ref, matrix, _dNotesReminders),
            _singleRow(ref, matrix, _dNotesRevision),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          key: _sectionKeys['device_security']!,
          children: [
            _singleBadgeRow(ref, matrix, _dDeviceMax),
            _singleRow(ref, matrix, _dGeneralOfflineMode),
            _singleRow(ref, matrix, _dSecurityScore),
            _singleRow(ref, matrix, _dBlockRoot),
          ],
        ),
        const SizedBox(height: 32),
        _buildSectionCard(
          key: _sectionKeys['profile_account']!,
          children: [
            _singleRow(ref, matrix, _dEditName),
            _singleRow(ref, matrix, _dEditPhoto),
            _singleRow(ref, matrix, _dViewMembership),
          ],
        ),
        const SizedBox(height: 60),
      ],
    );
  }

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

  Widget _buildPlanSelectorTabs(List<SubscriptionPlan> plans) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 692),
        child: Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF979797), width: 1),
          ),
          child: Row(
            children: plans.map((SubscriptionPlan p) {
              final bool isSelected = _activePlan == p.id;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_activePlan == p.id) return;
                    setState(() {
                      _activePlan = p.id;
                      _restorePlanId = p.id;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF111827)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      p.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        fontSize: 14,
                        letterSpacing: 0,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF111827),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryAnchorTabs() {
    const categories = [
      {'key': 'video_media', 'label': 'Video & Media'},
      {'key': 'pdf_docs', 'label': 'Pdf & documents'},
      {'key': 'learning_assessment', 'label': 'Learning & Assessment'},
      {'key': 'productivity', 'label': 'Productivity'},
      {'key': 'device_security', 'label': 'Devices & Security'},
      {'key': 'profile_account', 'label': 'Profile & Account'},
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: const Color(0xFF979797), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: categories.map((cat) {
                final isSelected = _activeCategory == cat['key'];
                return GestureDetector(
                  onTap: () => _scrollToSection(cat['key']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 40,
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF111827)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat['label']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Google Sans Flex',
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF4B5563),
                        fontSize: 14,
                        letterSpacing: 0,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Figma cards ──────────────────────────────────────────────────────────

  /// Outer section card (Figma: #F8FAFC, 1px #E5E7EB, radius 16).
  Widget _buildSectionCard(
      {required GlobalKey key, required List<Widget> children}) {
    return Container(
      key: key,
      width: 1120,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
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

  /// Inner row card (Figma: white, 2px #979797, radius 16).
  Widget _rowCard({required List<Widget> rows}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF979797), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _rowLine({
    required String title,
    required Widget trailing,
    bool centeredTitle = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            textAlign: centeredTitle ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontFamily: 'Google Sans Flex',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF111827),
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  /// Figma toggle switch (green #34C759 / gray #E5E7EB, white thumb).
  Widget _figmaSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? key,
    bool cupertino = true,
  }) {
    if (!cupertino) {
      return Switch(
        key: key,
        value: value,
        onChanged: onChanged,
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF34C759);
          }
          return const Color(0xFFE5E7EB);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      );
    }
    return CupertinoSwitch(
      key: key,
      value: value,
      activeTrackColor: const Color(0xFF34C759),
      onChanged: onChanged,
    );
  }

  /// Toggle control for one feature. The rolling-window row and the
  /// video-access row use the Material Switch (its disabled state is the
  /// lock representation); every other row uses CupertinoSwitch.
  Widget _toggleFor(
      WidgetRef? ref, _FeatureDef def, PlanFeatureState? state) {
    final bool enabled = state?.enabled ?? false;
    final bool locked = def.isSensitive && !widget.isDoctor;
    final ValueChanged<bool>? onChanged =
        locked ? null : (bool v) => _toggleFeature(ref, def, state, v);
    if (def.key == 'video.rolling_window.enabled') {
      return _figmaSwitch(
        key: const Key('rolling-window-switch'),
        value: enabled,
        onChanged: onChanged,
        cupertino: false,
      );
    }
    if (def.key == 'video.access') {
      return _figmaSwitch(
        key: Key('switch-${def.key}'),
        value: enabled,
        onChanged: onChanged,
        cupertino: false,
      );
    }
    return _figmaSwitch(
      key: Key('switch-${def.key}'),
      value: enabled,
      onChanged: onChanged,
    );
  }

  /// Numeric pill badge (Figma: 92x40 outer, value pill). Editable:
  /// submit writes the value for the current plan.
  Widget _badgeFor(
    WidgetRef? ref,
    _FeatureDef def,
    PlanFeatureState? state, {
    Key? key,
    bool valueEditable = true,
    bool? parentEnabled,
  }) {
    final bool locked = def.isSensitive && !widget.isDoctor;
    if (_pending.contains(def.key)) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // Controller per plan + feature, synced from the stream on every
    // build while the user is not editing: the shown number can never
    // stick from another plan, with zero visual change.
    final String cacheKey = '$_activePlan:${def.key}';
    final TextEditingController controller =
        _badgeControllers.putIfAbsent(cacheKey, TextEditingController.new);
    final FocusNode focusNode =
        _badgeFocusNodes.putIfAbsent(cacheKey, FocusNode.new);
    final String shown = _shownValue(state);
    if (!focusNode.hasFocus && controller.text != shown) {
      controller.text = shown;
    }
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
        key: key ?? Key('badge-${def.key}'),
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        enabled: !locked && valueEditable,
        onFieldSubmitted: (String v) => _saveNumericValue(
            ref, def, state, v,
            parentEnabled: parentEnabled),
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

  /// Single toggle row (Figma 56px row card).
  Widget _singleRow(
      WidgetRef? ref, Map<String, PlanFeatureState> matrix, _FeatureDef def) {
    if (_pending.contains(def.key) && !def.isNumber) {
      return _rowCard(rows: [
        _rowLine(
          title: def.title,
          trailing: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ]);
    }
    return _rowCard(rows: [
      _rowLine(
        title: def.title,
        trailing: _toggleFor(ref, def, matrix[def.key]),
      ),
    ]);
  }

  /// Single row with a value badge instead of a toggle
  /// (Figma: Exam Retake Attempts Limit / Max active devices).
  Widget _singleBadgeRow(
      WidgetRef? ref, Map<String, PlanFeatureState> matrix, _FeatureDef def) {
    return _rowCard(rows: [
      _rowLine(
        title: def.title,
        trailing: _badgeFor(ref, def, matrix[def.key]),
      ),
    ]);
  }

  /// Paired card: toggle row + value row (Figma rolling / limited cards).
  /// The value badge follows its toggle: a disabled feature keeps its
  /// number non-editable (and the saved value doc mirrors the toggle).
  Widget _pairCard(
    WidgetRef? ref,
    Map<String, PlanFeatureState> matrix, {
    required _FeatureDef toggleDef,
    required _FeatureDef valueDef,
    Key? badgeKey,
  }) {
    final bool toggleOn = matrix[toggleDef.key]?.enabled ?? false;
    return _rowCard(rows: [
      _rowLine(
        title: toggleDef.title,
        trailing: _toggleFor(ref, toggleDef, matrix[toggleDef.key]),
      ),
      const SizedBox(height: 10),
      _rowLine(
        title: valueDef.title,
        trailing: _badgeFor(ref, valueDef, matrix[valueDef.key],
            key: badgeKey ??
                (valueDef.key == 'video.rolling_window.hours'
                    ? const Key('rolling-hours-badge')
                    : null),
            valueEditable: toggleOn,
            parentEnabled: toggleOn),
      ),
    ]);
  }

  /// Offline card: two toggles + one value row (Figma). The limit badge
  /// follows the offline-mode toggle.
  Widget _tripleCard(
    WidgetRef? ref,
    Map<String, PlanFeatureState> matrix, {
    required _FeatureDef first,
    required _FeatureDef second,
    required _FeatureDef valueDef,
  }) {
    final bool toggleOn = matrix[first.key]?.enabled ?? false;
    return _rowCard(rows: [
      _rowLine(
        title: first.title,
        trailing: _toggleFor(ref, first, matrix[first.key]),
      ),
      const SizedBox(height: 10),
      _rowLine(
        title: second.title,
        trailing: _toggleFor(ref, second, matrix[second.key]),
      ),
      const SizedBox(height: 10),
      _rowLine(
        title: valueDef.title,
        trailing: _badgeFor(ref, valueDef, matrix[valueDef.key],
            valueEditable: toggleOn, parentEnabled: toggleOn),
      ),
    ]);
  }

  /// Nested card with a header (Figma Resolution / Playback Speed cards).
  Widget _nestedCard(
    WidgetRef? ref,
    Map<String, PlanFeatureState> matrix, {
    required String title,
    required List<_FeatureDef> defs,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF979797), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 10),
          for (final _FeatureDef def in defs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _rowLine(
                title: def.title,
                trailing: _pending.contains(def.key)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _toggleFor(ref, def, matrix[def.key]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backward-compat wrapper: DashboardShell routes to
// SubscriptionScreen(isDoctor: …).
// ─────────────────────────────────────────────────────────────────────────────

class SubscriptionScreen extends StatelessWidget {
  final bool isDoctor;

  const SubscriptionScreen({super.key, this.isDoctor = true});

  @override
  Widget build(BuildContext context) {
    return SubscriptionFeatureMatrixScreen(isDoctor: isDoctor);
  }
}
