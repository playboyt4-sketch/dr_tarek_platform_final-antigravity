import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/bunny_playback_headers.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../student_dashboard/domain/entities/dashboard_subject.dart';
import '../../domain/entities/subject_learning_entities.dart';
import '../providers/subject_navigation_providers.dart';
import '../../../video_streaming/presentation/screens/video_streaming_screen.dart';

/// Double-tap guard: rapid repeated taps on a lecture/cover must not stack
/// multiple player routes (back would then land on a duplicate loading
/// player instead of the subject page). Claims a push slot for 1.2s.
DateTime? _lastVideoPushAt;

bool _claimVideoPush() {
  final now = DateTime.now();
  if (_lastVideoPushAt != null &&
      now.difference(_lastVideoPushAt!) < const Duration(milliseconds: 1200)) {
    return false;
  }
  _lastVideoPushAt = now;
  return true;
}

// ---------------------------------------------------------------------------
// Design constants for "subject page" (Figma node 378-300 — user paste).
// Raw design-pixel values from Figma dev mode, consumed via context.rs() /
// context.rsV() / context.rsFont() — identical to Figma at the 393x852
// reference, proportionally preserved elsewhere.
//
// Frame map (verbatim Figma code paste):
//   canvas    393x852  grade canvas (follows the STUDENT's grade —
//             grade-1 #F59E0B, grade-2 #1D4ED8, grade-3 #15803D,
//             grade-4 #DC2626 — same mapping as Student Home)
//   cover     0,0      393x232 #C4C4C4 bottom radius 35 — the FIRST video
//             of the ACTIVE tab (its thumbnail; gray while loading or
//             when the lecture has no thumbnail). Tapping it plays it.
//   title     38,143   318x85 white 28 Google Sans Flex w400 h1.29
//             centered ("المالية المتقدمة")
//   subtitle  107,200  179x27 white 20 w700 centered ("الفرقة الرابعة";
//             Figma says Sakkal Majalla — NOT bundled in pubspec, so the
//             app font (Google Sans Flex) is used for both lines)
//   back      16,64    44x44 glass circle + chevron (RTL: points right)
//   tabs      y237 h41 white 14: active "المحاضرات (4)" w400 + 107x3
//             #D9D9D9 underline (r2); inactive "المراجعة (1)" /
//             "الفاينال (1)" w100. Each tab shows its own lectures count.
//   cards     12,286+  369x145 r15 glass white 25% + 1px white 40% stroke;
//             info row 41h: title right (126x41 black 14 w100 centered),
//             download icon (23x24), duration left (75x41 "52:43" black
//             14 w100 centered)
// The simulated OS status bar ("9:41", 0-50 chrome) is NOT reproduced.
// ---------------------------------------------------------------------------
abstract final class _SubjectPageDesign {
  static const coverHeight = 232.0;
  static const coverRadius = 35.0;
  static const coverPlaceholder = Color(0xFFC4C4C4);
  static const playButtonSize = 56.0;

  // Header text block: single Column anchored at y143 (title 28 w400
  // h1.29, gap 4, subtitle 20 w700) — never two overlapping Positioneds.
  static const titleBlockTop = 143.0;
  static const titleWidth = 318.0;
  static const titleSize = 28.0;
  static const titleGap = 4.0;
  static const subtitleWidth = 179.0;
  static const subtitleSize = 20.0;

  static const backLeft = 16.0;
  static const backTopOffset = 14.0; // below the real status bar (Figma y64)
  static const backSize = 44.0;

  static const tabsTopGap = 5.0; // tabs y237 − cover h232
  static const tabsHeight = 41.0;
  static const tabFontSize = 14.0;
  static const tabUnderlineWidth = 107.0;
  static const tabUnderlineHeight = 3.0;
  static const tabUnderlineFill = Color(0xFFD9D9D9);

  static const listMarginHorizontal = 12.0;
  static const listTopGap = 8.0; // first card y286 − tabs bottom 278
  static const cardGap = 16.0; // 286 → 447 → 608 → 769
  static const cardHeight = 145.0;
  static const cardRadius = 15.0;
  static const infoBarHeight = 41.0;
  static const durationWidth = 75.0;
  static const metaSize = 14.0;
}

/// Subject page — Figma "subject page" (378:300).
///
/// Sections come from [subjectSectionsProvider]; each visible section renders
/// as a tab (المحاضرات / المراجعة / الفاينال) with its own lectures count,
/// and the selected tab's lectures as glass cards below. Tapping an
/// unlocked lecture — or the header cover, which is the first video —
/// opens [VideoStreamingScreen].
class SubjectNavigationScreen extends ConsumerStatefulWidget {
  final DashboardSubject subject;

  /// Student grade driving the page background (same grade → canvas
  /// mapping as Student Home). Unknown grades fall back to grade one.
  final String? grade;

  /// Explicit background override. When null, the canvas is resolved from
  /// [grade].
  final Color? backgroundColor;

  const SubjectNavigationScreen({
    required this.subject,
    this.grade,
    this.backgroundColor,
    super.key,
  });

  @override
  ConsumerState<SubjectNavigationScreen> createState() =>
      _SubjectNavigationScreenState();
}

/// The 4 canonical subject tabs (fixed order, RTL: lectures rightmost).
/// A tab appears ONLY when the subject has ≥1 visible section of its kind —
/// first explanation lecture ⇒ `المحاضرات` shows, first revision ⇒
/// `المراجعة`, and so on. Never invented from titles.
enum _SubjectTab {
  lectures('المحاضرات', 0),
  revisions('المراجعة', 1),
  finals('الفاينال', 2),
  online('الأونلاين', 3);

  final String label;
  final int order;

  const _SubjectTab(this.label, this.order);
}

/// Classifies a section into its canonical tab (dashboard Feature 03 keys:
/// `explanation` / `revision` / `final_review`; legacy persisted `online`;
/// canonical custom `null` key qualified by title). Returns null for
/// non-video custom sections (e.g. announcements) — hidden from tabs.
_SubjectTab? _tabForSection(LearningSection section) {
  switch (section.sectionKey) {
    case 'explanation':
      return _SubjectTab.lectures;
    case 'revision':
      return _SubjectTab.revisions;
    case 'final_review':
      return _SubjectTab.finals;
    case 'online':
      return _SubjectTab.online;
  }
  if (section.sectionKey != null) return null;
  final normalized = section.title.trim().toLowerCase();
  if (normalized.contains('online') ||
      normalized.contains('أونلاين') ||
      normalized.contains('اونلاين') ||
      normalized.contains('أون لاين') ||
      normalized.contains('اون لاين')) {
    return _SubjectTab.online;
  }
  // Legacy rows written without a key: infer from the Arabic title.
  if (normalized.contains('مراجع') || normalized.contains('revision')) {
    return _SubjectTab.revisions;
  }
  if (normalized.contains('فاينل') ||
      normalized.contains('نهائي') ||
      normalized.contains('final')) {
    return _SubjectTab.finals;
  }
  if (normalized.contains('محاضر') ||
      normalized.contains('شرح') ||
      normalized.contains('explanation')) {
    return _SubjectTab.lectures;
  }
  return null;
}

/// Groups visible sections by canonical tab (each group ordered by
/// `displayOrder`; tabs ordered lectures → revisions → finals → online).
Map<_SubjectTab, List<LearningSection>> _groupSectionsByTab(
  List<LearningSection> visible,
) {
  final groups = <_SubjectTab, List<LearningSection>>{};
  for (final section in visible) {
    final tab = _tabForSection(section);
    if (tab == null) continue;
    (groups[tab] ??= []).add(section);
  }
  for (final list in groups.values) {
    list.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }
  return Map.fromEntries(
    _SubjectTab.values.where(groups.containsKey).map((tab) => MapEntry(tab, groups[tab]!)),
  );
}

class _SubjectNavigationScreenState
    extends ConsumerState<SubjectNavigationScreen> {
  _SubjectTab? selectedTab;

  Color get _background =>
      widget.backgroundColor ?? _gradeBackground(widget.grade);

  /// Background follows the STUDENT's grade canvas identity tokens
  /// (mirrors Student Home — الفرقة بتاعت الطالب). Unknown grades fall
  /// back to grade one, same as Student Home.
  static Color _gradeBackground(String? grade) {
    switch (_normalizeGradeKey(grade)) {
      case 'grade_two':
        return AppColors.grade2Canvas;
      case 'grade_three':
        return AppColors.grade3Canvas;
      case 'grade_four':
        return AppColors.grade4Canvas;
      default:
        return AppColors.grade1Canvas;
    }
  }

  /// Canonicalizes any known grade spelling (`grade_one` … `grade_four`,
  /// digits, English/Arabic labels) so both `grade_three` and
  /// `الفرقة الثالثة` map to the same canvas.
  static String? _normalizeGradeKey(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    const aliases = <String, String>{
      'grade_one': 'grade_one',
      'grade one': 'grade_one',
      'grade_1': 'grade_one',
      'grade 1': 'grade_one',
      '1': 'grade_one',
      'grade_two': 'grade_two',
      'grade two': 'grade_two',
      'grade_2': 'grade_two',
      'grade 2': 'grade_two',
      '2': 'grade_two',
      'grade_three': 'grade_three',
      'grade three': 'grade_three',
      'grade_3': 'grade_three',
      'grade 3': 'grade_three',
      '3': 'grade_three',
      'grade_four': 'grade_four',
      'grade four': 'grade_four',
      'grade_4': 'grade_four',
      'grade 4': 'grade_four',
      '4': 'grade_four',
    };
    if (aliases.containsKey(text)) return aliases[text];
    final folded = text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي');
    if (folded.contains('اول') || folded.contains('one')) {
      return 'grade_one';
    }
    if (folded.contains('ثان') || folded.contains('two')) {
      return 'grade_two';
    }
    if (folded.contains('ثال') || folded.contains('three')) {
      return 'grade_three';
    }
    if (folded.contains('راب') || folded.contains('four')) {
      return 'grade_four';
    }
    return null;
  }

  static String? _gradeLabel(String? gradeKey) {
    switch (gradeKey) {
      case 'grade_one':
        return 'الفرقة الأولى';
      case 'grade_two':
        return 'الفرقة الثانية';
      case 'grade_three':
        return 'الفرقة الثالثة';
      case 'grade_four':
        return 'الفرقة الرابعة';
      default:
        return null;
    }
  }

  /// Header subtitle = the SUBJECT's own grade (فرقة المادة), never a
  /// hardcoded fallback. Falls back to the student's grade label only
  /// when the subject doc carries no parseable grade, so a grade-three
  /// student holding a grade-one subject sees `الفرقة الأولى`.
  String get _headerSubtitle {
    final subjectLabel = widget.subject.gradeLabel;
    if (subjectLabel != null) return subjectLabel;
    final studentLabel = _gradeLabel(_normalizeGradeKey(widget.grade));
    if (studentLabel != null) return studentLabel;
    final legacy = widget.subject.subtitle?.trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(
      subjectSectionsProvider(widget.subject.id),
    );

    return Scaffold(
      backgroundColor: _background,
      body: sectionsAsync.when(
        loading: () => Column(
          children: [
            _Header(
              subject: widget.subject,
              subtitle: _headerSubtitle,
              coverBackground: const _PlainCover(),
            ),
            SizedBox(height: context.rsV(_SubjectPageDesign.tabsTopGap)),
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ],
        ),
        error: (_, _) => Column(
          children: [
            _Header(
              subject: widget.subject,
              subtitle: _headerSubtitle,
              coverBackground: const _PlainCover(),
            ),
            SizedBox(height: context.rsV(_SubjectPageDesign.tabsTopGap)),
            Expanded(
              child: _MessageState(
                message: 'تعذر تحميل أقسام المادة.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => ref.invalidate(
                  subjectSectionsProvider(widget.subject.id),
                ),
              ),
            ),
          ],
        ),
        data: (items) {
          final visible = items.where((item) => item.isVisible).toList();
          final groups = _groupSectionsByTab(visible);
          if (groups.isEmpty) {
            return Column(
              children: [
                _Header(
                  subject: widget.subject,
                  subtitle: _headerSubtitle,
                  coverBackground: const _PlainCover(),
                ),
                SizedBox(
                  height: context.rsV(_SubjectPageDesign.tabsTopGap),
                ),
                const Expanded(
                  child: _MessageState(
                    message: 'لا توجد أقسام منشورة في هذه المادة بعد.',
                  ),
                ),
              ],
            );
          }
          final tabs = groups.keys.toList();
          final currentTab =
              selectedTab != null && groups.containsKey(selectedTab)
              ? selectedTab!
              : tabs.first;
          final currentSections = groups[currentTab]!;
          final unlockedSections = currentSections
              .where((item) => !item.isLocked)
              .toList();
          // Cover = first video of the ACTIVE tab (المحاضرات → first
          // lecture, المراجعة → first revision, ...), so the header always
          // matches the collection being browsed.
          final coverSection = groups[currentTab]!.first;
          return Column(
            children: [
              _Header(
                subject: widget.subject,
                subtitle: _headerSubtitle,
                coverBackground: _FirstVideoCover(
                  subjectId: widget.subject.id,
                  firstSectionId: coverSection.id,
                  seasons: visible,
                ),
              ),
              SizedBox(height: context.rsV(_SubjectPageDesign.tabsTopGap)),
              _Tabs(
                groups: groups,
                selected: currentTab,
                onSelected: (tab) => setState(() => selectedTab = tab),
              ),
              Expanded(
                child: unlockedSections.isEmpty
                    ? const _MessageState(
                        message: 'هذا القسم مقفل ضمن اشتراكك الحالي.',
                      )
                    : _LecturesBody(
                        subjectId: widget.subject.id,
                        tab: currentTab,
                        sections: unlockedSections,
                        seasons: visible,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Header (Figma 0,0 393x232): cover background (FIRST video thumbnail)
/// with bottom radius 35, centered subject title + subject-grade subtitle,
/// glass back button overlay.
class _Header extends StatelessWidget {
  final DashboardSubject subject;
  final Widget coverBackground;

  /// Resolved subtitle (subject's own grade label). Passed in so the
  /// header never falls back to a hardcoded `الفرقة الرابعة`.
  final String subtitle;

  const _Header({
    required this.subject,
    required this.coverBackground,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final coverHeight = context.rsV(_SubjectPageDesign.coverHeight);

    return SizedBox(
      height: coverHeight,
      child: Stack(
        children: [
          Positioned.fill(child: coverBackground),
          // Title + subtitle as ONE column (Figma 38,143): title 318-wide
          // white 28 w400 h1.29 centered (max 2 lines, ellipsis), gap 4,
          // then subtitle 179-wide white 20 w700 centered. A single flow
          // means long subject names can never paint over the grade line.
          Positioned(
            top: context.rsV(_SubjectPageDesign.titleBlockTop),
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: context.rs(_SubjectPageDesign.titleWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      subject.title,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFontFamilies.googleSansFlex,
                        color: Colors.white,
                        fontSize: context.rsFont(
                          _SubjectPageDesign.titleSize,
                        ),
                        fontWeight: FontWeight.w400,
                        height: 1.29,
                      ),
                    ),
                    SizedBox(
                      height: context.rsV(_SubjectPageDesign.titleGap),
                    ),
                    SizedBox(
                      width: context.rs(
                        _SubjectPageDesign.subtitleWidth,
                      ),
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFontFamilies.googleSansFlex,
                          color: Colors.white,
                          fontSize: context.rsFont(
                            _SubjectPageDesign.subtitleSize,
                          ),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Back (Figma 16,64 44x44 glass circle; RTL back points right).
          Positioned(
            top:
                MediaQuery.paddingOf(context).top +
                context.rsV(_SubjectPageDesign.backTopOffset),
            left: context.rs(_SubjectPageDesign.backLeft),
            child: _SubjectBackButton(
              size: context.rs(_SubjectPageDesign.backSize),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain gray cover (Figma #C4C4C4): shown while the first video is
/// loading, when the subject has no sections, or when the first lecture
/// has no thumbnail.
class _PlainCover extends StatelessWidget {
  const _PlainCover();

  @override
  Widget build(BuildContext context) {
    final radius = context.rs(_SubjectPageDesign.coverRadius);
    return Container(
      decoration: BoxDecoration(
        color: _SubjectPageDesign.coverPlaceholder,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        ),
      ),
    );
  }
}

/// Header cover = the FIRST video of the ACTIVE tab: its thumbnail
/// fills the gray area (Figma 393x232, bottom radius 35). Tapping it
/// plays that lecture.
class _FirstVideoCover extends ConsumerWidget {
  final String subjectId;
  final String firstSectionId;
  final List<LearningSection> seasons;

  const _FirstVideoCover({
    required this.subjectId,
    required this.firstSectionId,
    required this.seasons,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lecturesAsync = ref.watch(
      sectionLecturesProvider(firstSectionId),
    );
    final items = lecturesAsync.value;
    // Cover = first lecture of the tab that actually carries a video
    // (denormalized `firstVideo` pointer). A leading video-less row must
    // not gray out the header while playable videos exist below it.
    // Fallbacks preserve the old behavior when nothing is playable.
    LectureSummary? pickCover() {
      if (items == null || items.isEmpty) return null;
      final unlocked = items.where((e) => !e.isLocked).toList();
      if (unlocked.isEmpty) return items.first;
      for (final e in unlocked) {
        if ((e.firstVideo?.bunnyVideoId ?? '').isNotEmpty) return e;
      }
      return unlocked.first;
    }

    final first = pickCover();
    final playable = first != null && !first.isLocked;
    // Doc thumbnail first; otherwise the section-batch media (same poster
    // the cards show + silent preview for autoplay). Locked covers never
    // fetch — lock overlay anyway.
    final docUrl = first?.thumbnailUrl;
    final needsFetch =
        first != null &&
        !first.isLocked &&
        (docUrl == null || docUrl.isEmpty);
    final fetched =
        needsFetch
            ? ref.watch(sectionDisplayMediaProvider(firstSectionId)).value
            : null;
    LectureDisplayMedia? media;
    if (first != null && fetched != null) {
      media = fetched[first.id];
    }
    final coverUrl =
        (docUrl != null && docUrl.isNotEmpty)
            ? docUrl
            : media?.thumbnailUrl;
    final previewUrl = playable ? media?.previewUrl : null;

    final radius = context.rs(_SubjectPageDesign.coverRadius);
    final bottomRadius = BorderRadius.only(
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    void openFirst() {
      final episode = first;
      final episodes = items;
      if (episode == null || episodes == null || episode.isLocked) return;
      if (!_claimVideoPush()) return;
      // Single-route contract: tap pushes DIRECTLY to the full-screen
      // player route — no intermediate screen/AppBar between tap and video.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoStreamingScreen(
            subjectId: subjectId,
            initialEpisode: episode,
            episodes: episodes,
            seasons: seasons,
            loadEpisodes: (id) =>
                ref.read(sectionLecturesProvider(id).future),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: playable ? openFirst : null,
      child: Semantics(
        button: playable,
        label: playable ? 'تشغيل أول محاضرة' : null,
        child: Container(
          decoration: BoxDecoration(
            color: _SubjectPageDesign.coverPlaceholder,
            borderRadius: bottomRadius,
          ),
          child: ClipRRect(
            borderRadius: bottomRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _AutoPlayCover(
                  posterUrl: coverUrl,
                  previewUrl: previewUrl,
                  playable: playable,
                ),
                if (first != null && first.isLocked)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.lock_outline,
                      size: context.rs(32),
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass back button for the subject page. Same Liquid Glass treatment as
/// the canonical [GlassBackButton] (44 circle, white 25% + 1px white 35%,
/// blur 20), but the chevron points RIGHT — back in an RTL layout —
/// which is what Figma's `chevron_backward` means here.
class _SubjectBackButton extends StatelessWidget {
  final double size;

  const _SubjectBackButton({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: Colors.white.withValues(alpha: 0.25),
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.0,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: size,
              height: size,
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.only(left: 2.0),
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tabs row (Figma y237 h41 white 14): the 4 canonical tabs — only tabs
/// having ≥1 visible section appear (first lecture ⇒ المحاضرات, first
/// revision ⇒ المراجعة, …), RTL with lectures rightmost. Each tab shows
/// its total videos count ("المحاضرات (4)"); active is w400 + 107x3
/// #D9D9D9 underline, inactive w100. Horizontally scrollable so all
/// four fit on narrow screens.
class _Tabs extends StatelessWidget {
  final Map<_SubjectTab, List<LearningSection>> groups;
  final _SubjectTab selected;
  final ValueChanged<_SubjectTab> onSelected;

  const _Tabs({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = groups.keys.toList();
    return SizedBox(
      height: context.rsV(_SubjectPageDesign.tabsHeight),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tab in tabs)
                _Tab(
                  tab: tab,
                  sections: groups[tab]!,
                  selected: tab == selected,
                  onTap: () => onSelected(tab),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  final _SubjectTab tab;
  final List<LearningSection> sections;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.tab,
    required this.sections,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Total videos count across the tab's sections ("المحاضرات (4)").
    // Plain label until every section's lectures finish loading so no
    // wrong number flashes.
    int total = 0;
    var ready = true;
    for (final section in sections) {
      final count = ref.watch(sectionLecturesProvider(section.id)).value?.length;
      if (count == null) {
        ready = false;
        break;
      }
      total += count;
    }
    final label = ready ? '${tab.label} ($total)' : tab.label;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.rs(12)),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFontFamilies.googleSansFlex,
                  color: Colors.white,
                  fontSize: context.rsFont(
                    _SubjectPageDesign.tabFontSize,
                  ),
                  fontWeight: selected
                      ? FontWeight.w400
                      : FontWeight.w100,
                  height: 1.43,
                ),
              ),
              SizedBox(height: context.rsV(2)),
              // Figma 107x3 r2 underline, centered under the label.
              Center(
                child: Container(
                  width: context.rs(
                    _SubjectPageDesign.tabUnderlineWidth,
                  ),
                  height: context.rsV(
                    _SubjectPageDesign.tabUnderlineHeight,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _SubjectPageDesign.tabUnderlineFill
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(context.rs(2)),
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

/// Lecture cards of the selected tab (Figma 369x145, gap 16): ALL videos
/// of the tab's sections merged below the tabs, ordered by section then
/// `display_order`.
class _LecturesBody extends ConsumerWidget {
  final String subjectId;
  final _SubjectTab tab;
  final List<LearningSection> sections;
  final List<LearningSection> seasons;

  const _LecturesBody({
    required this.subjectId,
    required this.tab,
    required this.sections,
    required this.seasons,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var loading = false;
    var failed = false;
    final merged = <LectureSummary>[];
    for (final section in sections) {
      final lecturesAsync = ref.watch(sectionLecturesProvider(section.id));
      if (lecturesAsync.isLoading || lecturesAsync.isRefreshing) {
        loading = true;
      }
      if (lecturesAsync.hasError) failed = true;
      final items = lecturesAsync.value;
      if (items == null) {
        if (!lecturesAsync.hasError) loading = true;
        continue;
      }
      merged.addAll(items);
    }
    if (failed && merged.isEmpty && !loading) {
      return _MessageState(
        message: 'تعذر تحميل المحاضرات.',
        actionLabel: 'إعادة المحاولة',
        onAction: () {
          for (final section in sections) {
            ref.invalidate(sectionLecturesProvider(section.id));
          }
        },
      );
    }
    if (loading && merged.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    {
        final items = merged;
        if (items.isEmpty) {
          return const _MessageState(
            message: 'لا توجد محاضرات منشورة في هذا القسم بعد.',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.only(
            top: context.rsV(_SubjectPageDesign.listTopGap),
            left: context.rs(_SubjectPageDesign.listMarginHorizontal),
            right: context.rs(_SubjectPageDesign.listMarginHorizontal),
            bottom: context.rsV(24),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final lecture = items[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == items.length - 1
                    ? 0
                    : context.rsV(_SubjectPageDesign.cardGap),
              ),
              child: _LectureCard(
                lecture: lecture,
                onOpen: lecture.isLocked
                    ? null
                    : () {
                        if (!_claimVideoPush()) return;
                        // Single-route contract: tap pushes DIRECTLY to the
                        // full-screen player route — no intermediate screen.
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoStreamingScreen(
                              subjectId: subjectId,
                              initialEpisode: lecture,
                              episodes: items,
                              seasons: seasons,
                              loadEpisodes: (id) => ref.read(
                                sectionLecturesProvider(id).future,
                              ),
                            ),
                          ),
                        );
                      },
              ),
            );
          },
        );
    }
  }
}

/// Glass lecture card (Figma 369x145 r15, white 25% + 1px white 40%,
/// backdrop blur 17.5): thumbnail on top, info row (title / download /
/// duration) pinned to the bottom 41px.
class _LectureCard extends StatelessWidget {
  final LectureSummary lecture;
  final VoidCallback? onOpen;

  const _LectureCard({required this.lecture, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      context.rs(_SubjectPageDesign.cardRadius),
    );

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.40),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
              child: SizedBox(
                height: context.rsV(_SubjectPageDesign.cardHeight),
                child: Column(
                  children: [
                    // Thumbnail (Figma top ~98px of the 145 card): the
                    // lecture's own image, else a frame of its video.
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _LectureThumb(lecture: lecture),
                          if (lecture.isLocked)
                            Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.lock_outline,
                                size: context.rs(28),
                                color: Colors.white,
                              ),
                            )
                          else
                            const _CardPlayOverlay(),
                        ],
                      ),
                    ),
                    // Info row (Figma 41h): title right, download,
                    // duration left — RTL row keeps Figma order.
                    SizedBox(
                      height: context.rsV(
                        _SubjectPageDesign.infoBarHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(8),
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                lecture.title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily:
                                      AppFontFamilies.googleSansFlex,
                                  color: Colors.black,
                                  fontSize: context.rsFont(
                                    _SubjectPageDesign.metaSize,
                                  ),
                                  fontWeight: FontWeight.w100,
                                  height: 1.43,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.file_download_outlined,
                              size: context.rs(23),
                              color: Colors.black,
                            ),
                            SizedBox(
                              width: context.rs(
                                _SubjectPageDesign.durationWidth,
                              ),
                              child: Text(
                                _formatDuration(lecture.duration),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily:
                                      AppFontFamilies.googleSansFlex,
                                  color: Colors.black,
                                  fontSize: context.rsFont(
                                    _SubjectPageDesign.metaSize,
                                  ),
                                  fontWeight: FontWeight.w100,
                                  height: 1.43,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  /// While true shows a small spinner (media still resolving) so the card
  /// reads as "loading" instead of "broken"; otherwise a plain wash.
  final bool loading;

  const _ThumbnailPlaceholder({this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child:
          loading
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              )
              : null,
    );
  }
}

/// Centered play affordance shared by loaded posters and placeholders
/// (white 25% circle + play arrow, header style at card scale).
class _CardPlayOverlay extends StatelessWidget {
  const _CardPlayOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: context.rs(44),
        height: context.rs(44),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          size: context.rs(28),
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Card/cover image: the lecture doc's own thumbnail when the author set
/// one, otherwise a frame of the lecture's video from the section-batch
/// media ([sectionDisplayMediaProvider]). Placeholder while loading or
/// when no image exists anywhere.
class _LectureThumb extends ConsumerWidget {
  final LectureSummary lecture;

  const _LectureThumb({required this.lecture});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docUrl = lecture.thumbnailUrl;
    if (docUrl != null && docUrl.isNotEmpty) {
      return _NetworkThumb(url: docUrl);
    }
    final sectionId = lecture.sectionId;
    if (sectionId == null || sectionId.isEmpty) {
      return const _ThumbnailPlaceholder();
    }
    final mediaAsync = ref.watch(sectionDisplayMediaProvider(sectionId));
    final url = mediaAsync.value?[lecture.id]?.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return _NetworkThumb(url: url);
    }
    return _ThumbnailPlaceholder(loading: mediaAsync.isLoading);
  }
}

/// Header cover media: the poster immediately, then Bunny's silent HQ
/// preview clip starting 2s after the page opens — muted + looping, so
/// there is never any sound (the track is never unmuted) and no browser
/// autoplay block. Read-only listing URLs only: no signed playback URL is
/// ever minted here, so the 24h window/sessions are untouched. The poster
/// stays underneath, so a missing/slow clip degrades to the still image
/// with zero flash.
class _AutoPlayCover extends StatefulWidget {
  final String? posterUrl;
  final String? previewUrl;

  /// The cover IS the first video: shows the play affordance over the
  /// still poster, hidden the moment the silent preview starts playing.
  final bool playable;

  const _AutoPlayCover({this.posterUrl, this.previewUrl, this.playable = true});

  @override
  State<_AutoPlayCover> createState() => _AutoPlayCoverState();
}

class _AutoPlayCoverState extends State<_AutoPlayCover> {
  VideoPlayerController? _controller;
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedulePreview();
  }

  @override
  void didUpdateWidget(covariant _AutoPlayCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The signed preview URL resolves AFTER first paint (batched fetch);
    // start the 2s countdown when it arrives, not only at init.
    if (oldWidget.previewUrl != widget.previewUrl) {
      _schedulePreview();
    }
  }

  void _schedulePreview() {
    final url = widget.previewUrl;
    if (url == null ||
        url.isEmpty ||
        _timer != null ||
        _controller != null) {
      return;
    }
    _timer = Timer(const Duration(seconds: 2), _startPreview);
  }

  Future<void> _startPreview() async {
    if (!mounted) return;
    final url = widget.previewUrl;
    if (url == null || url.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: bunnyPlaybackHttpHeaders,
    );
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
      await controller.play();
    } catch (error) {
      debugPrint(
        '[VIDEO-THUMB] header preview FAILED '
        'url=${_safeThumbUrl(url)} error=$error',
      );
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posterUrl = widget.posterUrl;
    final controller = _controller;
    final size = controller?.value.size;
    Widget? preview;
    if (_ready &&
        controller != null &&
        size != null &&
        size.width > 0 &&
        size.height > 0) {
      preview = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      );
    }
    final showPlay = widget.playable && preview == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrl != null && posterUrl.isNotEmpty)
          Image.network(
            posterUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => const SizedBox.shrink(),
            loadingBuilder:
                (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
          ),
        ?preview,
        // Play affordance over the still poster only — hidden the moment
        // the silent preview starts so it never covers moving video.
        if (showPlay)
          Center(
            child: Container(
              width: context.rs(_SubjectPageDesign.playButtonSize),
              height: context.rs(_SubjectPageDesign.playButtonSize),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.25),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: context.rs(32),
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _NetworkThumb extends StatelessWidget {
  final String url;

  const _NetworkThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, _) {
        debugPrint(
          '[VIDEO-THUMB] image FAILED url=${_safeThumbUrl(url)} '
          'error=$error',
        );
        return const _ThumbnailPlaceholder();
      },
      loadingBuilder:
          (context, child, progress) =>
              progress == null ? child : const _ThumbnailPlaceholder(),
    );
  }
}

/// Log-safe thumbnail URL: host + file name only, token masked.
String _safeThumbUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return '<unparsable>';
  final segments =
      uri.pathSegments.where((s) => !s.startsWith('bcdn_token=')).toList();
  final tail = segments.length > 2 ? segments.sublist(segments.length - 2) : segments;
  return '${uri.host}/.../${tail.join('/')}';
}

class _MessageState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.rs(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: context.rs(48),
              color: Colors.white.withValues(alpha: 0.8),
            ),
            SizedBox(height: context.rsV(12)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFontFamilies.googleSansFlex,
                color: Colors.white,
                fontSize: context.rsFont(14),
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: context.rsV(8)),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Figma "52:43" duration format (mm:ss).
String _formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}

// NOTE: written without String.padStart because the environment's analyzer
// resolves dart:core incompletely (reports padStart as undefined even in a
// hello-world file); this manual form analyzes cleanly everywhere.
String _twoDigits(int value) => value < 10 ? '0$value' : '$value';
